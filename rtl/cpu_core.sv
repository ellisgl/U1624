// =============================================================================
// U1624 CPU Core
// =============================================================================
//
// A 16-bit softcore CPU with a fixed-length instruction set, designed for
// FPGA implementation and as a teaching tool for CPU architecture.
//
// Key concepts demonstrated:
//   - Finite State Machine (FSM) based control — the CPU steps through states
//     to fetch, decode, and execute each instruction
//   - Register file — 16 general-purpose 16-bit registers (like a small scratchpad)
//   - Arithmetic Logic Unit (ALU) — performs math and logic operations
//   - Memory-mapped I/O — peripherals (UART, timer) appear as memory addresses
//   - Interrupts — hardware signals that pause the program to handle events
//
// How a CPU works (simplified):
//   1. FETCH:   Read the next instruction from memory at the Program Counter (PC)
//   2. DECODE:  Break the instruction into fields (opcode, registers, immediates)
//   3. EXECUTE: Perform the operation (ALU math, memory access, branch, etc.)
//   4. Repeat from step 1
//
// This CPU combines decode and execute into one state for simplicity, and adds
// extra states for multi-cycle operations like memory reads/writes and interrupts.
//
// =============================================================================

`timescale 1ns / 1ps

module cpu_core (
    input  wire        clk,       // Clock — the heartbeat that drives all state changes
    input  wire        rst_n,     // Active-low reset — when 0, CPU resets to initial state

    // Memory Interface — how the CPU talks to RAM and I/O devices
    // The CPU puts an address on mem_addr and either reads data from mem_read_data
    // or writes data via mem_write_data + mem_write_en.
    output reg  [23:0] mem_addr,       // Address bus (24-bit = 16MB addressable space)
    input  wire [15:0] mem_read_data,  // Data coming IN from memory/peripherals
    output reg  [15:0] mem_write_data, // Data going OUT to memory/peripherals
    output reg         mem_write_en,   // Write enable — 1 = writing, 0 = reading

    // Interrupt Interface — external signal to request CPU attention
    // When irq is high and interrupts are enabled, the CPU will pause the current
    // program and jump to the interrupt handler at address 0x0008.
    input  wire        irq,

    // Bus Hold — when asserted, the CPU freezes in its current state.
    // Used by the DMA controller to take over the memory bus for block
    // transfers without the CPU interfering. All registers and outputs
    // hold their values until hold is deasserted.
    input  wire        hold
);

    // =========================================================================
    // FSM States
    // =========================================================================
    // The CPU is a Finite State Machine. Each clock cycle it's in exactly one
    // state. The state determines what the CPU does that cycle.
    //
    // Normal instruction flow: FETCH → EXECUTE → (back to FETCH, or MEM_READ/WRITE)
    // Interrupt flow:          FETCH → INT_PUSH_PC → INT_PUSH_FLAGS → MEM_WRITE → FETCH
    // Return from interrupt:   EXECUTE(IRET) → IRET_FLAGS → MEM_READ → FETCH
    //
    // We use 4 bits for the state register since we have 8 states (3 bits would
    // suffice, but 4 bits leaves room for future expansion).
    localparam [3:0] S_FETCH          = 4'd0, // Read instruction from memory
                     S_EXECUTE        = 4'd1, // Decode + execute the instruction
                     S_MEM_READ       = 4'd2, // Wait for memory read to complete
                     S_MEM_WRITE      = 4'd3, // Wait for memory write to complete
                     S_HALTED         = 4'd4, // CPU stopped (HALT instruction)
                     S_INT_PUSH_PC    = 4'd5, // Interrupt: save return address
                     S_INT_PUSH_FLAGS = 4'd6, // Interrupt: save CPU flags
                     S_IRET_FLAGS     = 4'd7; // Interrupt return: restore flags

    // Fixed address where the interrupt handler must be located.
    // When an interrupt fires, the CPU jumps here. The programmer must place
    // their interrupt service routine (ISR) at this address.
    localparam [23:0] INT_VECTOR = 24'h000008;

    // =========================================================================
    // CPU Registers
    // =========================================================================

    // Program Counter — holds the address of the NEXT instruction to fetch.
    // 24 bits wide, giving access to 16MB of address space.
    reg [23:0] pc;

    // Register File — 16 general-purpose 16-bit registers.
    // These are the CPU's fast working storage. Instructions read operands from
    // registers and write results back to registers. Much faster than memory.
    // R0–R14: general purpose (use for anything)
    // R15:    Stack Pointer (SP) — used by PUSH, POP, CALL, RET, and interrupts
    reg [15:0] rf [0:15];

    // Instruction Register — holds the instruction currently being executed.
    // Latched during FETCH so it stays stable during EXECUTE.
    reg [15:0] instr_reg;

    // FSM state register — which state the CPU is currently in.
    reg [3:0] state;

    // Interrupt enable flag — controls whether the CPU responds to IRQ.
    // Set by SEI (Set Enable Interrupts), cleared by CLI (Clear Interrupts).
    // Also cleared automatically on interrupt entry (prevents nested interrupts)
    // and restored on IRET (interrupt return).
    reg int_enable;

    // =========================================================================
    // Instruction Decode — Wire Slices
    // =========================================================================
    // Every instruction is 16 bits. We use "wire slices" to extract the fields.
    // This is purely combinational — no logic, just selecting bits. The hardware
    // equivalent of looking at different parts of the same number.
    //
    // The instruction formats are:
    //   R-Type:  [Opcode(4)][Rs(4)][Rt(4)][Rd(4)]     — register operations
    //   I-Type:  [Opcode(4)][Rs(4)][Rt(4)][Imm4(4)]   — immediate operations
    //   J-Type:  [Opcode(4)][Rs(4)][Imm8(8)]           — wide immediate
    //   B-Type:  [Opcode(4)][Cond(4)][Offset8(8)]      — branches
    //
    // All formats share the same opcode position, so we can always decode it.
    wire [15:0] instr  = instr_reg;
    wire [3:0]  opcode = instr[15:12]; // What operation to perform
    wire [3:0]  rs     = instr[11:8];  // First source register (or destination)
    wire [3:0]  rt     = instr[7:4];   // Second source register
    wire [3:0]  rd     = instr[3:0];   // Destination register
    wire [3:0]  imm4   = instr[3:0];   // 4-bit immediate value (shares bits with rd)
    wire [7:0]  imm8   = instr[7:0];   // 8-bit immediate value (shares bits with rt+rd)
    wire [3:0]  cond   = instr[11:8];  // Branch condition code (shares bits with rs)

    // =========================================================================
    // Internal Data Buses
    // =========================================================================
    // These wires carry data between the register file, ALU, and other units.

    // Register read ports — reading from the register file is instant (combinational).
    // We can read two registers simultaneously, which is needed for operations
    // like ADD Rd, Rs, Rt (need both Rs and Rt values at the same time).
    wire [15:0] rs_val = rf[rs]; // Value of register Rs
    wire [15:0] rt_val = rf[rt]; // Value of register Rt

    // ALU output signals
    reg  [15:0] alu_result;   // 16-bit result of the ALU operation
    reg  [16:0] alu_wide;     // 17-bit intermediate — the extra bit captures carry/borrow
    reg         alu_carry;    // Carry flag output from the ALU
    reg         alu_overflow; // Overflow flag output — signed overflow detection

    // Extended ALU operand — for MUL/DIV, the second operand is restricted
    // to R0–R7 (3-bit register select using lower 3 bits of rt field).
    wire [15:0] ext_b = rf[rt[2:0]];

    // Hardware multiply — combinational (single-cycle) 16×16 → 32-bit multiply.
    // The full 32-bit result is split: MUL gets the low 16, MULH gets the high 16.
    wire [31:0] mul_result = rs_val * ext_b;

    // Hardware divide — combinational with divide-by-zero protection.
    // Returns 0 for both quotient and remainder if dividing by zero.
    wire [15:0] div_quot = (ext_b != 0) ? rs_val / ext_b : 16'h0000;
    wire [15:0] div_rem  = (ext_b != 0) ? rs_val % ext_b : 16'h0000;

    // Branch decision — set by the branch condition evaluator (see below).
    reg take_branch;

    // =========================================================================
    // Status Flags
    // =========================================================================
    // Flags record properties of the most recent ALU result. Branch instructions
    // test these flags to decide whether to jump. Only ALU and compare
    // instructions update flags — data moves (LOAD, STORE, etc.) do NOT.
    //
    // This is a common CPU design pattern. It lets you do something like:
    //   SUB R0, R1, R2    ← sets flags based on the subtraction result
    //   BEQ label          ← branches if the result was zero (R1 == R2)

    reg flag_z; // Zero flag:     1 if the result was zero
    reg flag_n; // Negative flag: 1 if the result's highest bit (bit 15) was set
    reg flag_c; // Carry flag:    1 if the operation produced a carry or no borrow
                //   ADD: C=1 means unsigned overflow (result > 65535)
                //   SUB: C=1 means no borrow (Rs >= Rt), like the 6502 processor
    reg flag_v; // Overflow flag: 1 if signed overflow occurred
                //   Set when the result's sign is wrong — e.g., adding two
                //   positives gives a negative, or subtracting a negative from
                //   a positive gives a negative. Required for correct signed
                //   comparisons (BGE, BLT).

    // =========================================================================
    // Main FSM — Sequential Logic
    // =========================================================================
    // Everything inside this always block happens on the rising edge of the clock
    // (posedge clk) or when reset goes low (negedge rst_n).
    //
    // This is the "brain" of the CPU. Each state performs one step of work,
    // then transitions to the next state.

    integer i;           // Loop variable for register file initialization
    reg [15:0] next_sp;  // Temporary for stack pointer calculation (blocking assign)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // =================================================================
            // Reset — initialize everything to a known state
            // =================================================================
            // When rst_n goes low, the CPU resets immediately regardless of
            // what it was doing. This is asynchronous reset (negedge rst_n).
            pc             <= 24'h000000;  // Start executing from address 0
            instr_reg      <= 16'h0000;
            state          <= S_FETCH;     // Begin by fetching the first instruction
            flag_z         <= 1'b0;
            flag_n         <= 1'b0;
            flag_c         <= 1'b0;
            flag_v         <= 1'b0;
            mem_addr       <= 24'h000000;
            mem_write_data <= 16'h0000;
            mem_write_en   <= 1'b0;
            int_enable     <= 1'b0;        // Interrupts disabled on reset

            // Clear all 16 registers to zero
            for (i = 0; i < 16; i = i + 1)
                rf[i] <= 16'h0000;
        end else if (!hold) begin
            case (state)
                // =============================================================
                // FETCH — Read the next instruction from memory
                // =============================================================
                // On the previous cycle, we set mem_addr = PC, so mem_read_data
                // now contains the instruction at that address.
                //
                // Before fetching, we check for pending interrupts. If an IRQ
                // is active and interrupts are enabled, we divert to the
                // interrupt entry sequence instead of executing the next
                // instruction. This ensures interrupts are handled between
                // instructions, never mid-instruction.
                S_FETCH: begin
                    if (irq && int_enable) begin
                        // Interrupt requested! Enter the interrupt sequence.
                        state <= S_INT_PUSH_PC;
                    end else begin
                        // Normal fetch: latch the instruction and move to execute.
                        instr_reg    <= mem_read_data;
                        mem_write_en <= 1'b0;     // Not writing to memory
                        mem_addr     <= pc;        // Set up address for next fetch
                        state        <= S_EXECUTE;
                    end
                end

                // =============================================================
                // EXECUTE — Decode and execute the instruction
                // =============================================================
                // This is the biggest state. We look at the opcode to determine
                // what to do. Some instructions complete in this single cycle
                // (LIMM, ALU ops, branches). Others need an additional cycle
                // for memory access (LOAD, STORE, PUSH, POP, CALL, RET).
                S_EXECUTE: begin
                    case (opcode)
                        // ----- LOAD Rt, [Rs + Imm4] -----
                        // Read a value from memory into a register.
                        // Address = Rs register value + 4-bit offset.
                        // Needs an extra cycle (S_MEM_READ) to wait for memory.
                        4'h0: begin
                            mem_addr <= {8'h00, rs_val} + {20'h00000, imm4};
                            pc       <= pc + 1;
                            state    <= S_MEM_READ;
                        end

                        // ----- STORE Rt, [Rs + Imm4] -----
                        // Write a register value to memory.
                        // Address = Rs register value + 4-bit offset.
                        4'h1: begin
                            mem_addr       <= {8'h00, rs_val} + {20'h00000, imm4};
                            mem_write_data <= rt_val;
                            mem_write_en   <= 1'b1; // Tell memory we're writing
                            pc             <= pc + 1;
                            state          <= S_MEM_WRITE;
                        end

                        // ----- LIMM Rs, Imm8 -----
                        // Load an 8-bit immediate value into a register.
                        // The upper byte is zeroed. Use LUI after this to set
                        // the upper byte for full 16-bit constants.
                        4'h2: begin
                            rf[rs]   <= {8'h00, imm8}; // Zero-extend to 16 bits
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;  // Pre-set address for next fetch
                            state    <= S_FETCH;
                        end

                        // ----- POP Rd (imm8=0) or LUI Rd, Imm8 (imm8≠0) -----
                        // Two instructions share this opcode, distinguished by imm8:
                        //   imm8 = 0: POP — read value from stack into Rd
                        //   imm8 ≠ 0: LUI — load upper immediate, keeping lower byte
                        //
                        // LUI + LIMM together build 16-bit constants:
                        //   LIMM R0, 0xF0   → R0 = 0x00F0
                        //   LUI  R0, 0xFF   → R0 = 0xFFF0
                        4'h3: begin
                            if (imm8 == 8'h00) begin
                                // POP: read from address in SP, then increment SP
                                mem_addr <= {8'h00, rf[15]};
                                rf[15]   <= rf[15] + 1;  // Post-increment stack pointer
                                pc       <= pc + 1;
                                state    <= S_MEM_READ;
                            end else begin
                                // LUI: replace upper byte, preserve lower byte
                                rf[rs]   <= {imm8, rf[rs][7:0]};
                                pc       <= pc + 1;
                                mem_addr <= pc + 1;
                                state    <= S_FETCH;
                            end
                        end

                        // ----- ALU R-Type Operations -----
                        // ADD/ADC(4), SUB/SBC(8), AND(9), OR(A), XOR/NOT(B),
                        // SHL/ROL(C), SHR/ROR(D)
                        //
                        // The ALU result is computed combinationally (see the ALU
                        // section below). Here we just write the result to the
                        // destination register and update flags.
                        //
                        // Several opcodes use rd[3] as a variant selector:
                        //   ADD with rd[3]=1 → ADC (add with carry)
                        //   SUB with rd[3]=1 → SBC (subtract with carry/borrow)
                        //   SHL with rd[3]=1 → ROL (rotate left)
                        //   SHR with rd[3]=1 → ROR (rotate right)
                        // When rd[3] is set, the destination wraps to R0–R7.
                        4'h4, 4'h8, 4'h9, 4'hA, 4'hB, 4'hC, 4'hD: begin
                            if ((opcode == 4'h4 || opcode == 4'h8 ||
                                 opcode == 4'hC || opcode == 4'hD) && rd[3])
                                rf[rd[2:0]] <= alu_result; // ADC/SBC/ROL/ROR dest R0-R7
                            else
                                rf[rd] <= alu_result;

                            // Update Zero and Negative flags for all ALU ops
                            flag_z   <= (alu_result == 16'h0000);
                            flag_n   <= alu_result[15];

                            // Carry and overflow flags only updated for ADD/ADC and SUB/SBC
                            if (opcode == 4'h4 || opcode == 4'h8) begin
                                flag_c <= alu_carry;
                                flag_v <= alu_overflow;
                            end

                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end

                        // ----- ADDI Rt, Rs, Imm4 / CMPI Rs, Imm4 -----
                        // When Rt ≠ 0: ADDI — add 4-bit immediate to Rs, store in Rt
                        // When Rt = 0: CMPI — compare Rs against Imm4 (sets flags only,
                        //              no result stored; "compare" = subtract and discard)
                        4'h5: begin
                            if (rt != 4'h0)
                                rf[rt] <= alu_result;
                            flag_z   <= (alu_result == 16'h0000);
                            flag_n   <= alu_result[15];
                            flag_c   <= alu_carry;
                            flag_v   <= alu_overflow;
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end

                        // ----- BRANCH Cond, Offset8 -----
                        // Conditional branch — if the condition is met, jump to
                        // PC + signed_offset. Otherwise continue to next instruction.
                        //
                        // The offset is sign-extended from 8 to 24 bits, allowing
                        // branches ±127 instructions from current position.
                        // {{16{imm8[7]}}, imm8} is sign extension: it replicates
                        // the sign bit (bit 7) to fill the upper 16 bits.
                        4'h6: begin
                            if (take_branch) begin
                                pc       <= pc + {{16{imm8[7]}}, imm8};
                                mem_addr <= pc + {{16{imm8[7]}}, imm8};
                            end else begin
                                pc       <= pc + 1;
                                mem_addr <= pc + 1;
                            end
                            state <= S_FETCH;
                        end

                        // ----- CALL, RET, IRET, SEI, CLI, GETF, SETF -----
                        // Multiple instructions packed under opcode 0x7,
                        // distinguished by the lower 12 or 8 bits.
                        //
                        // This encoding trick saves opcode space — with only
                        // 4 bits for the opcode (16 possible values), we need
                        // to be creative about fitting all instructions.
                        //
                        // Fixed encodings (rs=0, full 12-bit match):
                        //   0x7000 = RET, 0x7001 = IRET,
                        //   0x7002 = SEI, 0x7003 = CLI
                        // Register encodings (rs selects register, low 8 bits match):
                        //   0x7R04 = GETF Rs, 0x7R05 = SETF Rs
                        // Anything else = CALL Rs
                        4'h7: begin
                            if (instr[11:0] == 12'h000) begin
                                // RET — return from subroutine
                                // Pop the return address from the stack into PC.
                                mem_addr <= {8'h00, rf[15]};
                                rf[15]   <= rf[15] + 1; // Post-increment SP
                                state    <= S_MEM_READ;
                            end else if (instr[11:0] == 12'h001) begin
                                // IRET — return from interrupt
                                // First restore flags (S_IRET_FLAGS), then PC.
                                mem_addr <= {8'h00, rf[15]};
                                rf[15]   <= rf[15] + 1;
                                state    <= S_IRET_FLAGS;
                            end else if (instr[11:0] == 12'h002) begin
                                // SEI — Set Enable Interrupts
                                int_enable <= 1'b1;
                                pc         <= pc + 1;
                                mem_addr   <= pc + 1;
                                state      <= S_FETCH;
                            end else if (instr[11:0] == 12'h003) begin
                                // CLI — Clear (disable) Interrupts
                                int_enable <= 1'b0;
                                pc         <= pc + 1;
                                mem_addr   <= pc + 1;
                                state      <= S_FETCH;
                            end else if (imm8 == 8'h04) begin
                                // GETF Rs — read status register into Rs
                                // Packs all CPU flags into a single 16-bit value.
                                // Bit layout: {11'b0, V, I, C, N, Z}
                                //   Bit 0: Z (zero flag)
                                //   Bit 1: N (negative flag)
                                //   Bit 2: C (carry flag)
                                //   Bit 3: I (interrupt enable)
                                //   Bit 4: V (signed overflow flag)
                                rf[rs] <= {11'b0, flag_v, int_enable, flag_c, flag_n, flag_z};
                                pc         <= pc + 1;
                                mem_addr   <= pc + 1;
                                state      <= S_FETCH;
                            end else if (imm8 == 8'h05) begin
                                // SETF Rs — write status register from Rs
                                // Restores flags from a register value, using the
                                // same bit layout as GETF. Useful for saving and
                                // restoring CPU state across context switches.
                                flag_z     <= rs_val[0];
                                flag_n     <= rs_val[1];
                                flag_c     <= rs_val[2];
                                int_enable <= rs_val[3];
                                flag_v     <= rs_val[4];
                                pc         <= pc + 1;
                                mem_addr   <= pc + 1;
                                state      <= S_FETCH;
                            end else if (imm8 == 8'h06) begin
                                // ENTER n — set up stack frame
                                // 1. Push R14 (old frame pointer) onto the stack
                                // 2. R14 ← SP (new frame base)
                                // 3. SP ← SP − n (allocate n words for locals)
                                // The frame size n (0–15) is encoded in the rs field.
                                // R14 is the dedicated frame pointer register.
                                next_sp         = rf[15] - 1;
                                mem_addr        <= {8'h00, next_sp};
                                mem_write_data  <= rf[14];
                                mem_write_en    <= 1'b1;
                                rf[14]          <= next_sp;
                                rf[15]          <= next_sp - {12'b0, rs};
                                pc              <= pc + 1;
                                state           <= S_MEM_WRITE;
                            end else if (imm8 == 8'h07) begin
                                // LEAVE — tear down stack frame
                                // 1. SP ← R14 + 1 (deallocate locals + pop)
                                // 2. Pop old R14 from [R14] (restore caller's FP)
                                mem_addr <= {8'h00, rf[14]};
                                rf[15]   <= rf[14] + 1;
                                pc       <= pc + 1;
                                state    <= S_MEM_READ;
                            end else begin
                                // CALL Rs — call subroutine at address in Rs
                                // Push the return address (PC+1) onto the stack,
                                // then jump to the address in Rs.
                                //
                                // Stack grows downward: SP is decremented before
                                // writing (pre-decrement), like x86 and ARM.
                                // Note: next_sp uses blocking assignment (=) so
                                // it's available immediately in this same cycle.
                                next_sp  = rf[15] - 1;
                                rf[15]          <= next_sp;

                                mem_addr        <= {8'h00, next_sp};
                                mem_write_data  <= pc + 1;    // Return address
                                mem_write_en    <= 1'b1;

                                pc              <= {8'h00, rs_val}; // Jump to target
                                state           <= S_MEM_WRITE;
                            end
                        end

                        // ----- PUSH Rs -----
                        // Push a register value onto the stack.
                        // Pre-decrement SP, then write the value.
                        4'hE: begin
                            next_sp         = rf[15] - 1;
                            rf[15]          <= next_sp;

                            mem_addr        <= {8'h00, next_sp};
                            mem_write_data  <= rs_val;
                            mem_write_en    <= 1'b1;
                            pc              <= pc + 1;
                            state           <= S_MEM_WRITE;
                        end

                        // ----- Extended ALU (opcode 0xF) -----
                        // HALT or MUL/MULH/DIV/MOD operations.
                        // These use a 2-bit selector from rt[3] and rd[3]:
                        //   00 = MUL  (low 16 bits of multiply)
                        //   01 = MULH (high 16 bits of multiply)
                        //   10 = DIV  (quotient)
                        //   11 = MOD  (remainder)
                        4'hF: begin
                            if (instr[11:0] == 12'h000) begin
                                // HALT — stop the CPU. Only a reset can restart it.
                                state <= S_HALTED;
                            end else begin
                                case ({rt[3], rd[3]})
                                    2'b00: begin // MUL Rd, Rs, Rt — low 16 bits
                                        rf[rd[2:0]] <= mul_result[15:0];
                                        flag_z      <= (mul_result[15:0] == 16'h0000);
                                        flag_n      <= mul_result[15];
                                    end
                                    2'b01: begin // MULH Rd, Rs, Rt — high 16 bits
                                        rf[rd[2:0]] <= mul_result[31:16];
                                        flag_z      <= (mul_result[31:16] == 16'h0000);
                                        flag_n      <= mul_result[31];
                                    end
                                    2'b10: begin // DIV Rd, Rs, Rt — quotient
                                        rf[rd[2:0]] <= div_quot;
                                        flag_z      <= (div_quot == 16'h0000);
                                        flag_n      <= div_quot[15];
                                    end
                                    2'b11: begin // MOD Rd, Rs, Rt — remainder
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

                        // Unknown opcode — skip and continue
                        default: begin
                            pc       <= pc + 1;
                            mem_addr <= pc + 1;
                            state    <= S_FETCH;
                        end
                    endcase
                end

                // =============================================================
                // MEM_READ — Complete a memory read operation
                // =============================================================
                // We get here after LOAD, POP, RET, or IRET requested a read.
                // The memory has had one clock cycle to respond, so mem_read_data
                // now contains the value at the address we set in the previous state.
                //
                // What we do with the data depends on which instruction started
                // the read — we check the opcode and instruction bits to decide.
                S_MEM_READ: begin
                    if (opcode == 4'h3) begin
                        // POP — write the popped value to the destination register
                        rf[rs]   <= mem_read_data;
                        mem_addr <= pc;
                    end else if (opcode == 4'h7 && instr[11:0] == 12'h000) begin
                        // RET — the value is the return address; load it into PC
                        pc       <= {8'h00, mem_read_data};
                        mem_addr <= {8'h00, mem_read_data};
                    end else if (opcode == 4'h7 && instr[11:0] == 12'h001) begin
                        // IRET (second phase) — restore PC from stack
                        pc       <= {8'h00, mem_read_data};
                        mem_addr <= {8'h00, mem_read_data};
                    end else if (opcode == 4'h7 && imm8 == 8'h07) begin
                        // LEAVE (second phase) — restore frame pointer
                        rf[14]   <= mem_read_data;
                        mem_addr <= pc;
                    end else begin
                        // LOAD — write the loaded value to the destination register
                        rf[rt]   <= mem_read_data;
                        mem_addr <= pc;
                    end
                    state    <= S_FETCH;
                end

                // =============================================================
                // MEM_WRITE — Complete a memory write operation
                // =============================================================
                // The write was initiated in the previous state. Here we just
                // deassert the write enable and return to FETCH.
                S_MEM_WRITE: begin
                    mem_write_en <= 1'b0;  // Done writing
                    mem_addr     <= pc;     // Set up address for next fetch
                    state        <= S_FETCH;
                end

                // =============================================================
                // Interrupt Entry — Push PC and Flags to Stack
                // =============================================================
                // When an interrupt is detected, we need to save the CPU's state
                // so we can restore it later with IRET. This is a 2-step process:
                //
                // Step 1 (S_INT_PUSH_PC): Push the current PC to the stack.
                //   This is the address the CPU will return to after the interrupt.
                //
                // Step 2 (S_INT_PUSH_FLAGS): Push the flags (Z, N, C) to the stack.
                //   Then disable interrupts (prevent nesting) and jump to the
                //   interrupt vector (0x0008).
                //
                // After these two pushes, the stack looks like:
                //   [SP]     → flags  (pushed last, popped first by IRET)
                //   [SP + 1] → PC     (pushed first, popped second by IRET)

                S_INT_PUSH_PC: begin
                    // Push PC onto the stack (pre-decrement SP)
                    next_sp         = rf[15] - 1;
                    rf[15]          <= next_sp;
                    mem_addr        <= {8'h00, next_sp};
                    mem_write_data  <= pc[15:0];   // Save return address
                    mem_write_en    <= 1'b1;
                    state           <= S_INT_PUSH_FLAGS;
                end

                S_INT_PUSH_FLAGS: begin
                    // Push flags onto the stack (pre-decrement SP)
                    next_sp         = rf[15] - 1;
                    rf[15]          <= next_sp;
                    mem_addr        <= {8'h00, next_sp};
                    mem_write_data  <= {11'b0, flag_v, 1'b0, flag_c, flag_n, flag_z}; // Pack flags (bit 3 reserved for I)
                    mem_write_en    <= 1'b1;
                    int_enable      <= 1'b0;       // Disable interrupts during handler
                    pc              <= INT_VECTOR;  // Jump to interrupt handler (0x0008)
                    state           <= S_MEM_WRITE; // Finish the write, then FETCH
                end

                // =============================================================
                // Interrupt Return — Restore Flags
                // =============================================================
                // IRET pops flags then PC from the stack (reverse of push order).
                // This state handles the flags; it then transitions to MEM_READ
                // which handles the PC restoration.
                S_IRET_FLAGS: begin
                    // Restore flags from the value we just read from the stack
                    flag_z     <= mem_read_data[0];
                    flag_n     <= mem_read_data[1];
                    flag_c     <= mem_read_data[2];
                    flag_v     <= mem_read_data[4];
                    int_enable <= 1'b1;            // Re-enable interrupts

                    // Set up to pop the return address (PC) next
                    mem_addr   <= {8'h00, rf[15]};
                    rf[15]     <= rf[15] + 1;      // Post-increment SP
                    state      <= S_MEM_READ;      // MEM_READ will load PC
                end

                // =============================================================
                // HALTED — CPU is stopped
                // =============================================================
                // The CPU stays here until reset. No instructions execute.
                S_HALTED: begin
                end

                default: state <= S_FETCH;
            endcase
        end
    end

    // =========================================================================
    // Combinational ALU
    // =========================================================================
    // The ALU (Arithmetic Logic Unit) computes results combinationally — meaning
    // the output updates instantly whenever the inputs change, with no clock needed.
    // This is like a complex calculator circuit that always shows the answer.
    //
    // The EXECUTE state reads alu_result and decides whether to use it.
    // The ALU computes a result for EVERY cycle, but it's only written to a
    // register when the current instruction actually needs it.
    //
    // For carry detection, we use a 17-bit intermediate (alu_wide). The 17th bit
    // captures carry out of the 16-bit addition, which tells us if the result
    // overflowed the 16-bit range.
    //
    // Carry convention (6502-style):
    //   ADD: C = 1 when the result wraps around (unsigned overflow)
    //   SUB: C = 1 when there's NO borrow (Rs >= Rt)
    //        C = 0 when there IS a borrow (Rs < Rt)
    //   This is computed as: Rs + (~Rt) + 1 (two's complement subtraction)
    //   The carry out of this addition is naturally 1 when Rs >= Rt.

    always @(*) begin
        alu_carry    = 1'b0;
        alu_overflow = 1'b0;
        case (opcode)
            4'h4: begin // ADD or ADC (rd[3]=1)
                // ADD: Rs + Rt
                // ADC: Rs + Rt + Carry (for multi-word addition chains)
                if (rd[3])
                    alu_wide = {1'b0, rs_val} + {1'b0, rt_val} + {16'b0, flag_c};
                else
                    alu_wide = {1'b0, rs_val} + {1'b0, rt_val};
                alu_result   = alu_wide[15:0];
                alu_carry    = alu_wide[16];
                // Signed overflow: both operands same sign, result different sign
                alu_overflow = (rs_val[15] == rt_val[15]) && (alu_result[15] != rs_val[15]);
            end
            4'h5: begin // ADDI or CMPI
                if (rt == 4'h0) begin
                    // CMPI: subtract immediate (for comparison, sets flags)
                    alu_wide = {1'b0, rs_val} + {1'b0, ~{12'h000, imm4}} + 17'd1;
                    alu_result   = alu_wide[15:0];
                    alu_carry    = alu_wide[16];
                    // SUB overflow: operands differ in sign, result sign differs from Rs
                    alu_overflow = (rs_val[15] != imm4[3]) && (alu_result[15] != rs_val[15]);
                end else begin
                    // ADDI: add immediate
                    alu_wide = {1'b0, rs_val} + {13'b0, imm4};
                    alu_result   = alu_wide[15:0];
                    alu_carry    = alu_wide[16];
                    // ADD overflow: imm4 is always positive (unsigned), so overflow
                    // only if Rs positive and result negative
                    alu_overflow = (!rs_val[15]) && alu_result[15];
                end
            end
            4'h8: begin // SUB, SBC (rd[3]=1), or NEG (rs==rt)
                if (rd[3])
                    // SBC: Rs + ~Rt + Carry (6502-style subtract with borrow)
                    // When C=1 (no borrow): Rs - Rt
                    // When C=0 (borrow in): Rs - Rt - 1
                    alu_wide = {1'b0, rs_val} + {1'b0, ~rt_val} + {16'b0, flag_c};
                else if (rs == rt)
                    // NEG: two's complement negate (0 - Rs)
                    alu_wide = {1'b0, ~rs_val} + 17'd1;
                else
                    // SUB: Rs - Rt using two's complement addition
                    alu_wide = {1'b0, rs_val} + {1'b0, ~rt_val} + 17'd1;
                alu_result   = alu_wide[15:0];
                alu_carry    = alu_wide[16];
                // SUB overflow: operands differ in sign, result sign differs from Rs
                alu_overflow = (rs_val[15] != rt_val[15]) && (alu_result[15] != rs_val[15]);
            end
            4'h9:    alu_result = rs_val & rt_val;          // AND — bitwise AND
            4'hA:    alu_result = rs_val | rt_val;          // OR  — bitwise OR
            4'hB:    alu_result = (rs == rt) ? ~rs_val              // NOT — bitwise complement (when Rs==Rt)
                                              : (rs_val ^ rt_val);  // XOR — bitwise exclusive OR
            4'hC:    alu_result = rd[3] ? (rs_val << rt_val[3:0]) | (rs_val >> (5'd16 - {1'b0, rt_val[3:0]})) // ROL — rotate left
                                        : (rs_val << rt_val[3:0]);  // SHL — shift left (zeros fill)
            4'hD:    alu_result = rd[3] ? (rs_val >> rt_val[3:0]) | (rs_val << (5'd16 - {1'b0, rt_val[3:0]})) // ROR — rotate right
                                        : (rs_val >> rt_val[3:0]);  // SHR — shift right (zeros fill)
            default: alu_result = 16'h0000;
        endcase
    end

    // =========================================================================
    // Branch Condition Evaluator
    // =========================================================================
    // Evaluates the branch condition code against the current flags.
    // Like the ALU, this is combinational — it always produces a result,
    // but the EXECUTE state only uses it for branch instructions (opcode 0x6).
    //
    // Each condition code tests a different flag combination:
    //   0 = always (unconditional jump)
    //   1 = zero set (equal)
    //   2 = zero clear (not equal)
    //   3 = negative set (result was negative)
    //   4 = positive (not negative and not zero)
    //   5 = carry set (unsigned >=, or ADD overflow)
    //   6 = carry clear (unsigned <, or no ADD overflow)
    //   7 = signed >= (N == V)
    //   8 = signed <  (N != V)
    //
    // BGE and BLT use the classic N XOR V test for signed comparisons.
    // After SUB or CMPI, N alone is unreliable when signed overflow occurs
    // (e.g., 100 - (-100) overflows to a negative result). The overflow
    // flag V corrects for this: N == V means the true result is >= 0.

    always @(*) begin
        case (cond)
            4'h0:    take_branch = 1'b1;                // BRA (Unconditional)
            4'h1:    take_branch = flag_z;              // BEQ (Equal / Zero)
            4'h2:    take_branch = !flag_z;             // BNE (Not Equal / Non-Zero)
            4'h3:    take_branch = flag_n;              // BMI (Minus / Negative)
            4'h4:    take_branch = !flag_n && !flag_z;  // BPL (Positive)
            4'h5:    take_branch = flag_c;              // BCS (Carry Set / Unsigned >=)
            4'h6:    take_branch = !flag_c;             // BCC (Carry Clear / Unsigned <)
            4'h7:    take_branch = (flag_n == flag_v);  // BGE (Signed >=)
            4'h8:    take_branch = (flag_n != flag_v);  // BLT (Signed <)
            default: take_branch = 1'b0;
        endcase
    end

endmodule
