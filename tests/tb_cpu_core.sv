`timescale 1ns / 1ps

module tb_cpu_core;

    // Inputs to Unit Under Test (UUT)
    reg clk;
    reg rst_n;

    // ---------------------------------------------------------
    // CPU Bus Signals (directly from cpu_core outputs)
    // ---------------------------------------------------------
    wire [23:0] cpu_mem_addr;
    wire [15:0] cpu_mem_write_data;
    wire        cpu_mem_write_en;

    // ---------------------------------------------------------
    // DMA Bus Signals (from dma_controller outputs)
    // ---------------------------------------------------------
    wire [23:0] dma_bus_addr;
    wire [15:0] dma_bus_write_data;
    wire        dma_bus_write_en;
    wire        dma_bus_req;
    wire        dma_irq;
    wire [15:0] dma_read_data;

    // ---------------------------------------------------------
    // Bus Arbitration — DMA takes priority when it needs the bus
    // ---------------------------------------------------------
    // When bus_req is asserted, the memory bus switches from CPU
    // to DMA, and the CPU is frozen via its hold input.
    wire dma_active = dma_bus_req;

    wire [23:0] mem_addr       = dma_active ? dma_bus_addr       : cpu_mem_addr;
    wire [15:0] mem_write_data = dma_active ? dma_bus_write_data : cpu_mem_write_data;
    wire        mem_write_en   = dma_active ? dma_bus_write_en   : cpu_mem_write_en;
    wire [15:0] mem_read_data;

    // Address Decode: I/O space 0x00FFF0 - 0x00FFFF
    wire is_io = (mem_addr[15:4] == 12'hFFF);

    // Timer peripheral
    wire        timer_irq;
    wire [15:0] timer_read_data;
    wire        timer_select = is_io && (mem_addr[3:0] >= 4'h2 && mem_addr[3:0] <= 4'h5);
    wire [1:0]  timer_reg_addr = mem_addr[3:0] - 4'h2;
    wire        timer_write_en = mem_write_en && timer_select;

    // DMA peripheral — mapped at 0xFFF8–0xFFFB
    wire        dma_select = is_io && (mem_addr[3:0] >= 4'h8 && mem_addr[3:0] <= 4'hB);
    wire [1:0]  dma_reg_addr = mem_addr[1:0];
    wire        dma_write_en = mem_write_en && dma_select;

    // ---------------------------------------------------------
    // UART RX FIFO
    // ---------------------------------------------------------
    reg [7:0]  rx_fifo [0:15];
    integer    rx_head, rx_tail, rx_count;
    reg        rx_data_available;
    reg [7:0]  rx_data_reg;
    reg        rx_int_enable;
    wire       uart_rx_irq = rx_data_available & rx_int_enable;

    // Interrupt: OR of all interrupt sources
    wire irq = timer_irq | uart_rx_irq | dma_irq;

    // Instantiate the CPU Core Module
    cpu_core uut (
        .clk(clk),
        .rst_n(rst_n),
        .mem_addr(cpu_mem_addr),
        .mem_read_data(mem_read_data),
        .mem_write_data(cpu_mem_write_data),
        .mem_write_en(cpu_mem_write_en),
        .irq(irq),
        .hold(dma_active)
    );

    // Instantiate Timer Peripheral
    timer timer0 (
        .clk(clk),
        .rst_n(rst_n),
        .reg_addr(timer_reg_addr),
        .write_data(mem_write_data),
        .write_en(timer_write_en),
        .read_data(timer_read_data),
        .irq(timer_irq)
    );

    // Instantiate DMA Controller
    dma_controller dma0 (
        .clk(clk),
        .rst_n(rst_n),
        .reg_addr(dma_reg_addr),
        .write_data(mem_write_data),
        .write_en(dma_write_en),
        .read_data(dma_read_data),
        .bus_addr(dma_bus_addr),
        .bus_read_data(mem_read_data),
        .bus_write_data(dma_bus_write_data),
        .bus_write_en(dma_bus_write_en),
        .bus_req(dma_bus_req),
        .bus_grant(dma_bus_req),
        .irq(dma_irq)
    );

    // ---------------------------------------------------------
    // Mock Synchronous RAM Model (Preloaded with instructions)
    // ---------------------------------------------------------
    reg [15:0] sram [0:63];

    // ---------------------------------------------------------
    // Mock I/O Registers
    // ---------------------------------------------------------
    reg [15:0] io_read_data;

    always @(*) begin
        if (timer_select)
            io_read_data = timer_read_data;
        else if (dma_select)
            io_read_data = dma_read_data;
        else begin
            case (mem_addr[3:0])
                4'h1:    io_read_data = {14'b0, rx_data_available, 1'b1}; // Status: bit 0=TX ready, bit 1=RX available
                4'h6:    io_read_data = {8'h00, rx_data_reg};             // UART RX data
                4'h7:    io_read_data = {15'b0, rx_int_enable};           // UART RX control
                default: io_read_data = 16'h0000;
            endcase
        end
    end

    // Address-decoded read mux
    assign mem_read_data = is_io ? io_read_data : sram[mem_addr[5:0]];

    // Capture UART output
    reg [8*64-1:0] uart_buffer;
    integer uart_len;

    // Synchronous writes — RAM or I/O
    always @(posedge clk) begin
        if (mem_write_en) begin
            if (is_io) begin
                case (mem_addr[3:0])
                    4'h0: begin // UART TX Data
                        $write("%c", mem_write_data[7:0]);
                        uart_buffer[uart_len*8 +: 8] = mem_write_data[7:0];
                        uart_len = uart_len + 1;
                    end
                    4'h2, 4'h3, 4'h4, 4'h5: begin
                        // Timer registers — handled by timer module
                    end
                    4'h6: begin // UART RX acknowledge (pop FIFO)
                        if (rx_count > 0) begin
                            rx_head = (rx_head + 1) & 4'hF;
                            rx_count = rx_count - 1;
                            if (rx_count > 0) begin
                                rx_data_reg = rx_fifo[rx_head];
                            end else begin
                                rx_data_available = 0;
                            end
                        end
                    end
                    4'h7: begin // UART RX control
                        rx_int_enable = mem_write_data[0];
                    end
                    4'h8, 4'h9, 4'hA, 4'hB: begin
                        // DMA registers — handled by DMA controller
                    end
                    default: begin
                        $display("[IO WRITE] Unknown register 0x%h | Data: 0x%h", mem_addr, mem_write_data);
                    end
                endcase
            end else begin
                sram[mem_addr[5:0]] <= mem_write_data;
                $display("[MEM WRITE] Addr: 0x%h | Data: 0x%h", mem_addr, mem_write_data);
            end
        end
    end

    // ---------------------------------------------------------
    // Hardware Execution Termination Watchdog
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (uut.instr_reg == 16'hF000) begin
            $display("\n[HALT DETECTED] Gracefully terminating simulation loop.");

            if (uart_len > 0) begin
                $display("[UART OUTPUT] %0d character(s) transmitted.", uart_len);
            end

            $display("[RESULTS] sram[30]=0x%h  sram[31]=0x%h  sram[32]=0x%h  sram[33]=0x%h  sram[34]=0x%h",
                     sram[30], sram[31], sram[32], sram[33], sram[34]);

            if (sram[30] == 16'h0048 && sram[31] == 16'h0069) begin
                $display("[SIMULATION PASSED] UART RX test verified:");
                $display("  Char 1=0x%h ('%c')  Char 2=0x%h ('%c')\n",
                         sram[30], sram[30][7:0], sram[31], sram[31][7:0]);
            end else if (sram[30] == 16'h0055 && sram[31] == 16'h0042 &&
                sram[32] == 16'h0001) begin
                $display("[SIMULATION PASSED] Interrupt test verified:");
                $display("  Main continued=0x%h  Handler ran=0x%h  Flags preserved=0x%h\n",
                         sram[30], sram[31], sram[32]);
            end else if (sram[30] == 16'h0042 && sram[31] == 16'hFF00 &&
                         sram[32] == 16'hFFFF && sram[33] == 16'h0F10 &&
                         sram[34] == 16'hF001) begin
                $display("[SIMULATION PASSED] PDP-16 instructions verified:");
                $display("  MOV=0x%h  NOT=0x%h  NEG=0x%h", sram[30], sram[31], sram[32]);
                $display("  ROL=0x%h  ROR=0x%h\n", sram[33], sram[34]);
            end else begin
                $display("[SIMULATION FAILED] Unexpected values in data area.\n");
            end
            $finish;
        end
    end

    // ---------------------------------------------------------
    // Clock Generation (50 MHz Simulation Clock Cycle)
    // ---------------------------------------------------------
    always #10 clk = ~clk;

    // ---------------------------------------------------------
    // Test Vectors Initialization Block
    // ---------------------------------------------------------
    initial begin
        integer idx;

        // --- GTKWave Waveform Visual Dumper Setup ---
        $dumpfile("simulation_waves.vcd");
        $dumpvars(0, tb_cpu_core);

        // Clear out the simulation RAM block space completely
        for (idx = 0; idx < 64; idx = idx + 1) begin
            sram[idx] = 16'h0000;
        end

        uart_len = 0;

        // Initialize UART RX FIFO with test data
        rx_fifo[0] = 8'h48; // 'H'
        rx_fifo[1] = 8'h69; // 'i'
        rx_head = 0;
        rx_tail = 2;
        rx_count = 2;
        rx_data_available = 1;
        rx_data_reg = rx_fifo[0];
        rx_int_enable = 0;

        // Stream raw machine code dynamically from your tools directory
        $readmemh("./program.hex", sram);
        $display("[RAM INITIALIZATION] Streamed program.hex successfully into array targets.");

        // Initialize Control Lines
        clk   = 0;
        rst_n = 0;

        // Hold reset active for 2 full clock cycles
        #25;
        rst_n = 1;
        $display("[SIMULATION START] CPU Reset Released.");

        // Monitor critical CPU internal states as simulation updates
        $monitor("Time: %0t ns | PC: 0x%h | Opcode: 0x%h | R0: 0x%h | R1: 0x%h | R2: 0x%h",
                 $time, uut.pc, uut.opcode, uut.rf[0], uut.rf[1], uut.rf[2]);

        // Fallback Timeout Limit
        #10000;
        $display("[TIMEOUT ALERT] Simulation hit max runtime fallback limit.");
        $finish;
    end

endmodule
