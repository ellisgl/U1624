`timescale 1ns / 1ps

module cpu_core (
    input  wire        clk,
    input  wire        rst_n,

    // Memory Interface
    output reg  [23:0] mem_addr,
    input  wire [15:0] mem_read_data,
    output reg  [15:0] mem_write_data,
    output reg         mem_write_en,

    // Interrupt Interface
    input  wire        irq
);

    // FSM States
    localparam [3:0] S_FETCH          = 4'd0,
                     S_EXECUTE        = 4'd1,
                     S_MEM_READ       = 4'd2,
                     S_MEM_WRITE      = 4'd3,
                     S_HALTED         = 4'd4,
                     S_INT_PUSH_PC    = 4'd5,
                     S_INT_PUSH_FLAGS = 4'd6,
                     S_IRET_FLAGS     = 4'd7;

    // Interrupt vector address
    localparam [23:0] INT_VECTOR = 24'h000008;

    // Program Counter
    reg [23:0] pc;

    // Register File: 16 general-purpose 16-bit registers
    reg [15:0] rf [0:15];

    // Pipeline Buffer: Instruction Register
    reg [15:0] instr_reg;

    // FSM State
    reg [3:0] state;

    // Interrupt enable flag
    reg int_enable;

    // Instruction Register wire slices
    wire [15:0] instr  = instr_reg;
    wire [3:0]  opcode = instr[15:12];
    wire [3:0]  rs     = instr[11:8];
    wire [3:0]  rt     = instr[7:4];
    wire [3:0]  rd     = instr[3:0];
    wire [3:0]  imm4   = instr[3:0];
    wire [7:0]  imm8   = instr[7:0];
    wire [3:0]  cond   = instr[11:8];

    // Internal execution buses
    wire [15:0] rs_val = rf[rs];
    wire [15:0] rt_val = rf[rt];
    reg  [15:0] alu_result;
    wire [15:0] ext_b      = rf[rt[2:0]]; // Second operand for extended ops (R0-R7)
    wire [31:0] mul_result = rs_val * ext_b;
    wire [15:0] div_quot   = (ext_b != 0) ? rs_val / ext_b : 16'h0000;
    wire [15:0] div_rem    = (ext_b != 0) ? rs_val % ext_b : 16'h0000;
    reg         take_branch;

    // Status Flags
    reg flag_z;
    reg flag_n;

    // Main FSM
    integer i;
    reg [15:0] next_sp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc             <= 24'h000000;
            instr_reg      <= 16'h0000;
            state          <= S_FETCH;
            flag_z         <= 1'b0;
            flag_n         <= 1'b0;
            mem_addr       <= 24'h000000;
            mem_write_data <= 16'h0000;
            mem_write_en   <= 1'b0;
            int_enable     <= 1'b0;

            for (i = 0; i < 16; i = i + 1)
                rf[i] <= 16'h0000;
        end else begin
            case (state)
                S_FETCH: begin
                    if (irq && int_enable) begin
                        state <= S_INT_PUSH_PC;
                    end else begin
                        instr_reg    <= mem_read_data;
                        mem_write_en <= 1'b0;
                        mem_addr     <= pc;
                        state        <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    case (opcode)
                        4'h0: begin // LOAD Rt, [Rs + Imm4]
                            mem_addr <= {8'h00, rs_val} + {20'h00000, imm4};
                            pc       <= pc + 1;
                            state    <= S_MEM_READ;
                        end

                        4'h1: begin // STORE Rt, [Rs + Imm4]
                            mem_addr       <= {8'h00, rs_val} + {20'h00000, imm4};
                            mem_write_data <= rt_val;
                            mem_write_en   <= 1'b1;
                            pc             <= pc + 1;
                            state          <= S_MEM_WRITE;
                        end

                        4'h2: begin // LIMM Rs, Imm8
                            rf[rs]   <= {8'h00, imm8};
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end
                        
                        4'h3: begin // POP Rd (Uses rs field as destination register Rd)
                            // Read from the current address pointed to by R15 (SP)
                            mem_addr <= {8'h00, rf[15]}; 
                            
                            // Increment Stack Pointer post-read
                            rf[15]   <= rf[15] + 1; 
                            pc       <= pc + 1;
                            
                            // Divert to memory read state, but we need to tell it to latch into Rd (rs position)
                            state    <= S_MEM_READ; 
                        end

                        4'h4, 4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD: begin // ALU R-type
                            if ((opcode == 4'hC || opcode == 4'hD) && rd[3])
                                rf[rd[2:0]] <= alu_result; // ROL/ROR dest R0-R7
                            else
                                rf[rd] <= alu_result;
                            flag_z   <= (alu_result == 16'h0000);
                            flag_n   <= alu_result[15];
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end

                        4'h5: begin // ADDI Rt, Rs, Imm4 — or CMPI Rs, Imm4 when Rt == 0
                            if (rt != 4'h0)
                                rf[rt] <= alu_result;
                            flag_z   <= (alu_result == 16'h0000);
                            flag_n   <= alu_result[15];
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end

                        4'h6: begin // BRANCH Cond, Offset8
                            if (take_branch) begin
                                pc       <= pc + {{16{imm8[7]}}, imm8};
                                mem_addr <= pc + {{16{imm8[7]}}, imm8};
                            end else begin
                                pc       <= pc + 1;
                                mem_addr <= pc + 1;
                            end
                            state <= S_FETCH;
                        end

                        4'h7: begin // CALL, RET, IRET, SEI, CLI (Opcode 0x7)
                            if (instr[11:0] == 12'h000) begin // RET
                                mem_addr <= {8'h00, rf[15]};
                                rf[15]   <= rf[15] + 1;
                                state    <= S_MEM_READ;
                            end else if (instr[11:0] == 12'h001) begin // IRET
                                mem_addr <= {8'h00, rf[15]};
                                rf[15]   <= rf[15] + 1;
                                state    <= S_IRET_FLAGS;
                            end else if (instr[11:0] == 12'h002) begin // SEI
                                int_enable <= 1'b1;
                                pc         <= pc + 1;
                                mem_addr   <= pc + 1;
                                state      <= S_FETCH;
                            end else if (instr[11:0] == 12'h003) begin // CLI
                                int_enable <= 1'b0;
                                pc         <= pc + 1;
                                mem_addr   <= pc + 1;
                                state      <= S_FETCH;
                            end else begin
                                // --- CALL Rs EXECUTION ---
                                next_sp  = rf[15] - 1;
                                rf[15]          <= next_sp;

                                mem_addr        <= {8'h00, next_sp};
                                mem_write_data  <= pc + 1;
                                mem_write_en    <= 1'b1;

                                pc              <= {8'h00, rs_val};
                                state           <= S_MEM_WRITE;
                            end
                        end

                        4'hE: begin // PUSH Rs
                            next_sp         = rf[15] - 1; // Removed 'reg [15:0]' keyword
                            rf[15]          <= next_sp;
                            
                            mem_addr        <= {8'h00, next_sp};
                            mem_write_data  <= rs_val;
                            mem_write_en    <= 1'b1;
                            pc              <= pc + 1;
                            state           <= S_MEM_WRITE;
                        end

                        4'hF: begin
                            if (instr[11:0] == 12'h000) begin // HALT
                                state <= S_HALTED;
                            end else begin
                                // Extended ALU: rt[3] selects mul(0)/div(1), rd[3] selects variant
                                case ({rt[3], rd[3]})
                                    2'b00: begin // MUL Rd, Rs, Rt
                                        rf[rd[2:0]] <= mul_result[15:0];
                                        flag_z      <= (mul_result[15:0] == 16'h0000);
                                        flag_n      <= mul_result[15];
                                    end
                                    2'b01: begin // MULH Rd, Rs, Rt
                                        rf[rd[2:0]] <= mul_result[31:16];
                                        flag_z      <= (mul_result[31:16] == 16'h0000);
                                        flag_n      <= mul_result[31];
                                    end
                                    2'b10: begin // DIV Rd, Rs, Rt
                                        rf[rd[2:0]] <= div_quot;
                                        flag_z      <= (div_quot == 16'h0000);
                                        flag_n      <= div_quot[15];
                                    end
                                    2'b11: begin // MOD Rd, Rs, Rt
                                        rf[rd[2:0]] <= div_rem;
                                        flag_z      <= (div_rem == 16'h0000);
                                        flag_n      <= div_rem[15];
                                    end
                                endcase
                                pc       <= pc + 1;
                                mem_addr <= pc + 1;
                                state    <= S_FETCH;
                            end
                        end

                        default: begin
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end
                    endcase
                end

                S_MEM_READ: begin
                    if (opcode == 4'h3) begin
                        rf[rs]   <= mem_read_data; // POP target
                        mem_addr <= pc;
                    end else if (opcode == 4'h7 && instr[11:0] == 12'h000) begin
                        pc       <= {8'h00, mem_read_data}; // RET
                        mem_addr <= {8'h00, mem_read_data};
                    end else if (opcode == 4'h7 && instr[11:0] == 12'h001) begin
                        pc       <= {8'h00, mem_read_data}; // IRET — restore PC
                        mem_addr <= {8'h00, mem_read_data};
                    end else begin
                        rf[rt]   <= mem_read_data; // LOAD target
                        mem_addr <= pc;
                    end
                    state    <= S_FETCH;
                end

                S_MEM_WRITE: begin
                    mem_write_en <= 1'b0;
                    mem_addr     <= pc;
                    state        <= S_FETCH;
                end

                S_INT_PUSH_PC: begin
                    next_sp         = rf[15] - 1;
                    rf[15]          <= next_sp;
                    mem_addr        <= {8'h00, next_sp};
                    mem_write_data  <= pc[15:0];
                    mem_write_en    <= 1'b1;
                    state           <= S_INT_PUSH_FLAGS;
                end

                S_INT_PUSH_FLAGS: begin
                    next_sp         = rf[15] - 1;
                    rf[15]          <= next_sp;
                    mem_addr        <= {8'h00, next_sp};
                    mem_write_data  <= {14'b0, flag_n, flag_z};
                    mem_write_en    <= 1'b1;
                    int_enable      <= 1'b0;
                    pc              <= INT_VECTOR;
                    state           <= S_MEM_WRITE;
                end

                S_IRET_FLAGS: begin
                    flag_z     <= mem_read_data[0];
                    flag_n     <= mem_read_data[1];
                    int_enable <= 1'b1;
                    mem_addr   <= {8'h00, rf[15]};
                    rf[15]     <= rf[15] + 1;
                    state      <= S_MEM_READ;
                end

                S_HALTED: begin
                    // Permanently stopped
                end

                default: state <= S_FETCH;
            endcase
        end
    end

    // Combinatorial ALU (selected by opcode, not a shared funct field)
    always @(*) begin
        case (opcode)
            4'h4:    alu_result = rs_val + rt_val;          // ADD
            4'h5:    alu_result = (rt == 4'h0) ? rs_val - {12'h000, imm4}  // CMPI
                                              : rs_val + {12'h000, imm4}; // ADDI
            4'h8:    alu_result = (rs == rt) ? (~rs_val + 16'd1)   // NEG
                                              : (rs_val - rt_val);  // SUB
            4'h9:    alu_result = rs_val & rt_val;          // AND
            4'hA:    alu_result = rs_val | rt_val;          // OR
            4'hB:    alu_result = (rs == rt) ? ~rs_val              // NOT
                                              : (rs_val ^ rt_val);  // XOR
            4'hC:    alu_result = rd[3] ? (rs_val << rt_val[3:0]) | (rs_val >> (5'd16 - {1'b0, rt_val[3:0]})) // ROL
                                        : (rs_val << rt_val[3:0]);  // SHL
            4'hD:    alu_result = rd[3] ? (rs_val >> rt_val[3:0]) | (rs_val << (5'd16 - {1'b0, rt_val[3:0]})) // ROR
                                        : (rs_val >> rt_val[3:0]);  // SHR
            default: alu_result = 16'h0000;
        endcase
    end

    // Combinatorial Branch Condition Evaluation
    always @(*) begin
        case (cond)
            4'h0:    take_branch = 1'b1;                // BRA (Unconditional)
            4'h1:    take_branch = flag_z;              // BEQ (Equal / Zero)
            4'h2:    take_branch = !flag_z;             // BNE (Not Equal / Non-Zero)
            4'h3:    take_branch = flag_n;              // BMI (Minus / Negative)
            4'h4:    take_branch = !flag_n && !flag_z;  // BPL (Positive)
            default: take_branch = 1'b0;
        endcase
    end

endmodule
