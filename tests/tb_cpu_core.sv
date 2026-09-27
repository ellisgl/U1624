`timescale 1ns / 1ps

module tb_cpu_core;

    // Inputs to Unit Under Test (UUT)
    reg clk;
    reg rst_n;

    // Interconnect wires between UUT and Mock Memory
    wire [23:0] mem_addr;
    wire [15:0] mem_read_data;
    wire [15:0] mem_write_data;
    wire        mem_write_en;

    // Instantiate the CPU Core Module
    cpu_core uut (
        .clk(clk),
        .rst_n(rst_n),
        .mem_addr(mem_addr),
        .mem_read_data(mem_read_data),
        .mem_write_data(mem_write_data),
        .mem_write_en(mem_write_en)
    );

    // ---------------------------------------------------------
    // Address Decode: I/O space starts at 0xFF0000
    // ---------------------------------------------------------
    wire is_io = (mem_addr[15:4] == 12'hFFF); // I/O space: 0x00FFF0 - 0x00FFFF

    // ---------------------------------------------------------
    // Mock Synchronous RAM Model (Preloaded with instructions)
    // ---------------------------------------------------------
    reg [15:0] sram [0:63];

    // ---------------------------------------------------------
    // Mock I/O Registers
    // ---------------------------------------------------------
    // 0xFF0000 = UART TX Data (write-only)
    // 0xFF0001 = UART Status  (read-only, bit 0 = TX ready)
    reg [15:0] io_read_data;

    always @(*) begin
        case (mem_addr[3:0])
            4'h1:    io_read_data = 16'h0001; // UART status: always ready
            default: io_read_data = 16'h0000;
        endcase
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

            if (sram[30] == 16'h0042 && sram[31] == 16'hFF00 &&
                sram[32] == 16'hFFFF && sram[33] == 16'h0F10 &&
                sram[34] == 16'hF001) begin
                $display("[SIMULATION PASSED] PDP-16 instructions verified:");
                $display("  MOV=0x%h  NOT=0x%h  NEG=0x%h", sram[30], sram[31], sram[32]);
                $display("  ROL=0x%h  ROR=0x%h\n", sram[33], sram[34]);
            end else begin
                $display("[SIMULATION FAILED] PDP-16 instruction mismatch:");
                $display("  MOV: 0x%h (exp 0042)  NOT: 0x%h (exp FF00)", sram[30], sram[31]);
                $display("  NEG: 0x%h (exp FFFF)  ROL: 0x%h (exp 0F10)", sram[32], sram[33]);
                $display("  ROR: 0x%h (exp F001)\n", sram[34]);
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
        #3200;
        $display("[TIMEOUT ALERT] Simulation hit max runtime fallback limit.");
        $finish;
    end

endmodule
