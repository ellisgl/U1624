# U1624

A custom 16-bit softcore CPU targeting FPGA, inspired by the **65C816**, **Z8000**, **8086/8088**, **Nintendo SA1**, and **PDP-16**.

## Architecture

- **16-bit fixed-length instructions** — single-cycle decode via wire slices, no microcode
- **16 general-purpose 16-bit registers** (R0–R15, R15 = Stack Pointer)
- **24-bit address bus** (16MB addressable, flat — no segmentation)
- **Multi-state FSM** execution: FETCH → EXECUTE → MEM_READ/MEM_WRITE → FETCH
- **Hardware multiply** (16×16→32) and **divide** with divide-by-zero protection
- **Memory-mapped I/O** at `0xFFF0`–`0xFFFF`

## Instruction Set

### Instruction Formats

```
R-Type:  [Opcode (4)][Rs (4)][Rt (4)][Rd (4)]
I-Type:  [Opcode (4)][Rs (4)][Rt (4)][Imm4 (4)]
J-Type:  [Opcode (4)][Rs (4)][Imm8 (8)]
B-Type:  [Opcode (4)][Cond (4)][Offset8 (8)]
```

### Instructions

| Category | Mnemonic | Description | Encoding |
|----------|----------|-------------|----------|
| **Data Transfer** | `MOV Rd, Rs` | Register copy | OR Rd, Rs, Rs |
| | `LIMM Rd, Imm8` | Load 8-bit immediate | `0x2` J-Type |
| | `LOAD Rt, [Rs+Imm4]` | Load from memory | `0x0` I-Type |
| | `STORE Rt, [Rs+Imm4]` | Store to memory | `0x1` I-Type |
| | `PUSH Rs` | Push to stack (pre-decrement SP) | `0xE` |
| | `POP Rd` | Pop from stack (post-increment SP) | `0x3` |
| **Arithmetic** | `ADD Rd, Rs, Rt` | Add | `0x4` R-Type |
| | `ADDI Rt, Rs, Imm4` | Add immediate | `0x5` I-Type |
| | `SUB Rd, Rs, Rt` | Subtract | `0x8` R-Type |
| | `NEG Rd, Rs` | Two's complement negate | SUB with Rs==Rt |
| | `MUL Rd, Rs, Rt` | Multiply (low 16 bits) | `0xF` ext, Rd R0–R7 |
| | `MULH Rd, Rs, Rt` | Multiply (high 16 bits) | `0xF` ext, Rd R0–R7 |
| | `DIV Rd, Rs, Rt` | Unsigned divide | `0xF` ext, Rd/Rt R0–R7 |
| | `MOD Rd, Rs, Rt` | Unsigned modulo | `0xF` ext, Rd/Rt R0–R7 |
| **Logic** | `AND Rd, Rs, Rt` | Bitwise AND | `0x9` R-Type |
| | `OR Rd, Rs, Rt` | Bitwise OR | `0xA` R-Type |
| | `XOR Rd, Rs, Rt` | Bitwise XOR | `0xB` R-Type |
| | `NOT Rd, Rs` | Bitwise complement | XOR with Rs==Rt |
| **Shift/Rotate** | `SHL Rd, Rs, Rt` | Shift left | `0xC` R-Type |
| | `SHR Rd, Rs, Rt` | Shift right | `0xD` R-Type |
| | `ROL Rd, Rs, Rt` | Rotate left | `0xC` ext, Rd R0–R7 |
| | `ROR Rd, Rs, Rt` | Rotate right | `0xD` ext, Rd R0–R7 |
| **Compare** | `CMPI Rs, Imm4` | Compare immediate (sets flags) | `0x5` with Rt=0 |
| **Control Flow** | `BRA/BEQ/BNE/BMI/BPL Offset8` | Conditional branch | `0x6` B-Type |
| | `CALL Rs` | Call subroutine (push return addr) | `0x7` |
| | `RET` | Return from subroutine | `0x7000` |
| | `JAL Rd, Rs` | Jump and link | `0x7` |
| | `NOP` | No operation | BRA +1 (`0x6001`) |
| | `HALT` | Stop execution | `0xF000` |
| **Directives** | `.word val, ...` | Embed 16-bit constants | |
| | `.byte val, ...` | Embed 8-bit values (packed 2/word) | |

### Flags

ALU and compare instructions set two flags:
- **Z** (Zero) — result is zero
- **N** (Negative) — result bit 15 is set

Data transfer instructions (LOAD, STORE, PUSH, POP, LIMM) do not modify flags.

## Project Structure

```
U1624/
├── rtl/
│   └── cpu_core.sv          # CPU core RTL (SystemVerilog)
├── tests/
│   └── tb_cpu_core.sv       # Testbench with mock SRAM and UART
├── tools/
│   └── assembler.py         # Two-pass assembler with label support
└── run_sim.sh               # Build and simulate script
```

## Toolchain

### Assembler

The Python assembler is a standalone CLI tool supporting symbolic labels, all instructions, and data directives:

```bash
# Assemble a source file to program.hex (default output)
python3 tools/assembler.py my_program.asm

# Specify output file
python3 tools/assembler.py my_program.asm -o output.hex

# Verbose mode (print word mapping)
python3 tools/assembler.py my_program.asm -v
```

Example assembly:

```asm
    LIMM  R15, 60          ; Initialize stack pointer
    LIMM  R0, 7
    LIMM  R1, 9
    LIMM  R4, multiply     ; Label reference
    CALL  R4
    HALT

multiply:
    MUL   R2, R0, R1       ; R2 = 7 * 9 = 63
    RET
```

Run the full simulation pipeline:

```bash
bash run_sim.sh                        # uses tests/test_program.asm
bash run_sim.sh my_program.asm         # uses a custom source file
```

This assembles the source, compiles the RTL with Icarus Verilog, and launches the simulation.

### Requirements

- [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`) with `-g2012` flag
- Python 3
- [GTKWave](http://gtkwave.sourceforge.net/) (optional, for viewing `simulation_waves.vcd`)

## Memory Map

| Address Range | Description |
|---------------|-------------|
| `0x000000`–`0x00FFEF` | RAM / Program memory |
| `0x00FFF0` | UART TX Data (write) |
| `0x00FFF1` | UART Status (read, bit 0 = TX ready) |
| `0x00FFF2`–`0x00FFFF` | Reserved I/O |

## Design Influences

| CPU | What U1624 borrows |
|-----|-------------------|
| **65C816** | 24-bit address bus, clean orthogonal ISA |
| **Z8000** | Large uniform register file (16 GPRs) |
| **8086/8088** | Practical I/O integration philosophy |
| **Nintendo SA1** | Hardware multiply/divide (16×16→32) |
| **PDP-16** | MOV, NOT, NEG, rotate instructions |

## License

BSD 3-Clause — see [LICENSE](LICENSE).
