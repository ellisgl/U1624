// =============================================================================
// U1624 DMA Controller
// =============================================================================
//
// A single-channel DMA (Direct Memory Access) controller that performs
// memory-to-memory block transfers without CPU intervention.
//
// Why DMA matters:
//   Without DMA, the CPU must copy data word-by-word using LOAD/STORE loops.
//   A 100-word copy takes ~400 CPU cycles (load, store, increment, branch
//   per word). With DMA, the CPU programs the transfer (4 register writes)
//   and the DMA hardware copies at 2 cycles per word — the CPU is free to
//   resume immediately after the transfer completes.
//
// How it works:
//   1. CPU writes source address, destination address, and length to DMA regs
//   2. CPU writes the start bit to the control register
//   3. DMA asserts bus_req, which freezes the CPU via its hold input
//   4. DMA takes over the memory bus and copies data word by word
//   5. When done, DMA releases the bus; CPU resumes where it left off
//
// Bus arbitration:
//   The CPU and DMA share the same memory bus. Only one can use it at a time.
//   The DMA signals bus_req when it needs the bus. An external mux (in the
//   top-level or testbench) switches the memory bus between CPU and DMA.
//   The CPU's hold input freezes it so it doesn't try to access memory
//   while the DMA is using the bus.
//
// Transfer speed: 2 clock cycles per word (one read cycle, one write cycle).
//
// =============================================================================

`timescale 1ns / 1ps

module dma_controller (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Register Interface — memory-mapped at 0xFFF8–0xFFFB
    // The CPU programs the DMA by writing to these registers before starting.
    input  wire [1:0]  reg_addr,    // Which register (0=src, 1=dst, 2=len, 3=ctrl)
    input  wire [15:0] write_data,  // Data from the CPU
    input  wire        write_en,    // CPU is writing to a DMA register
    output reg  [15:0] read_data,   // Data read by the CPU

    // Bus Master Interface — active during transfers
    // These signals drive the memory bus when the DMA has control.
    output reg  [23:0] bus_addr,
    input  wire [15:0] bus_read_data,
    output reg  [15:0] bus_write_data,
    output reg         bus_write_en,

    // Arbitration — active-high request/grant handshake
    output wire        bus_req,     // 1 = DMA needs the memory bus
    input  wire        bus_grant,   // 1 = DMA may use the memory bus

    // Interrupt — active-high, fires when transfer completes (if enabled)
    output wire        irq
);

    // =========================================================================
    // DMA State Machine
    // =========================================================================
    // Three active states form a simple read-write loop:
    //   IDLE → COPY_SETUP → COPY_READ ⇄ COPY_WRITE → IDLE
    //
    // COPY_SETUP: Request bus, set up first read address
    // COPY_READ:  Source data is on bus_read_data; latch it, set up write
    // COPY_WRITE: Write completes on this clock edge; advance to next word

    localparam [1:0] S_IDLE       = 2'd0,
                     S_COPY_SETUP = 2'd1,
                     S_COPY_READ  = 2'd2,
                     S_COPY_WRITE = 2'd3;

    reg [1:0]  state;

    // =========================================================================
    // DMA Registers — programmed by the CPU before starting a transfer
    // =========================================================================

    reg [15:0] src_reg;    // Source start address (auto-increments during transfer)
    reg [15:0] dst_reg;    // Destination start address (auto-increments)
    reg [15:0] len_reg;    // Transfer length in words (set before start)
    reg [15:0] count;      // Words remaining (counts down during transfer)
    reg        int_enable; // If set, fires IRQ when transfer completes
    reg        done_flag;  // Set when transfer finishes, cleared on next start

    // Bus request is active whenever the DMA is transferring
    assign bus_req = (state != S_IDLE);

    // Interrupt fires only when transfer is done AND interrupts are enabled
    assign irq = done_flag & int_enable;

    // =========================================================================
    // Register Read — combinational, always available for CPU reads
    // =========================================================================
    // Status register (reg 3) layout:
    //   Bit 0: Busy — transfer is in progress
    //   Bit 1: Interrupt enable
    //   Bit 2: Done — transfer has completed (cleared on next start)

    always @(*) begin
        case (reg_addr)
            2'd0:    read_data = src_reg;
            2'd1:    read_data = dst_reg;
            2'd2:    read_data = len_reg;
            2'd3:    read_data = {13'b0, done_flag, int_enable, bus_req};
        endcase
    end

    // =========================================================================
    // Main State Machine
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            src_reg        <= 16'h0000;
            dst_reg        <= 16'h0000;
            len_reg        <= 16'h0000;
            count          <= 16'h0000;
            int_enable     <= 1'b0;
            done_flag      <= 1'b0;
            bus_addr       <= 24'h000000;
            bus_write_data <= 16'h0000;
            bus_write_en   <= 1'b0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                // IDLE — waiting for CPU to start a transfer
                // ---------------------------------------------------------
                // The CPU programs src, dst, and len, then writes the start
                // bit (bit 0) to the control register to kick off the transfer.
                S_IDLE: begin
                    bus_write_en <= 1'b0;
                    if (write_en) begin
                        case (reg_addr)
                            2'd0: src_reg <= write_data;
                            2'd1: dst_reg <= write_data;
                            2'd2: len_reg <= write_data;
                            2'd3: begin
                                int_enable <= write_data[1];
                                if (write_data[0] && len_reg != 16'h0000) begin
                                    count     <= len_reg;
                                    done_flag <= 1'b0;
                                    state     <= S_COPY_SETUP;
                                end
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                // COPY_SETUP — request bus and set up first read address
                // ---------------------------------------------------------
                // Wait for bus_grant (in this system it's immediate since
                // there's only one alternative bus master). Then point the
                // bus address at the source and proceed to read.
                S_COPY_SETUP: begin
                    if (bus_grant) begin
                        bus_addr     <= {8'h00, src_reg};
                        bus_write_en <= 1'b0;
                        state        <= S_COPY_READ;
                    end
                end

                // ---------------------------------------------------------
                // COPY_READ — latch source data, set up write
                // ---------------------------------------------------------
                // The memory is combinational-read, so bus_read_data already
                // has the word from the source address (set in COPY_SETUP or
                // the previous COPY_WRITE). Latch it, point the bus at the
                // destination, and enable writing.
                S_COPY_READ: begin
                    bus_write_data <= bus_read_data;
                    bus_addr       <= {8'h00, dst_reg};
                    bus_write_en   <= 1'b1;
                    state          <= S_COPY_WRITE;
                end

                // ---------------------------------------------------------
                // COPY_WRITE — write completes, advance to next word
                // ---------------------------------------------------------
                // The write to destination happens on this clock edge (the
                // testbench/memory sees write_en=1 from COPY_READ). Now
                // deassert write_en, increment addresses, decrement count.
                // If more words remain, set up the next read; otherwise done.
                S_COPY_WRITE: begin
                    bus_write_en <= 1'b0;
                    src_reg      <= src_reg + 1;
                    dst_reg      <= dst_reg + 1;
                    count        <= count - 1;
                    if (count == 16'h0001) begin
                        done_flag <= 1'b1;
                        state     <= S_IDLE;
                    end else begin
                        bus_addr  <= {8'h00, src_reg + 16'd1};
                        state     <= S_COPY_READ;
                    end
                end
            endcase
        end
    end

endmodule
