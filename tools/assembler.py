import argparse
import re
import sys

# Define opcode mappings from our microarchitecture definition
OPCODES = {
    'LOAD':   0x0,
    'STORE':  0x1,
    'LIMM':   0x2,
    'POP':    0x3,
    'ADD':    0x4,
    'ADDI':   0x5,
    'BRANCH': 0x6,
    'CALL':   0x7,
    'SUB':    0x8,
    'AND':    0x9,
    'OR':     0xA,
    'XOR':    0xB,
    'SHL':    0xC,
    'SHR':    0xD,
    'PUSH':   0xE,
    'HALT':   0xF,
}

# R-type ALU mnemonics (each has its own opcode above)
ALU_R_MNEMONICS = {'ADD', 'SUB', 'AND', 'OR', 'XOR', 'SHL', 'SHR'}

# Define condition codes for branches
BRANCH_CONDITIONS = {
    'BRA': 0x0, # Unconditional
    'BEQ': 0x1, # Equal / Zero
    'BNE': 0x2, # Not Equal / Non-Zero
    'BMI': 0x3, # Minus / Negative
    'BPL': 0x4, # Positive
}

def parse_register(reg_str):
    """Converts a register string like 'R5' or 'r5' to its integer value (5)."""
    match = re.match(r'^[Rr](\d+)$', reg_str.strip())
    if not match:
        raise ValueError(f"Invalid register syntax: '{reg_str}'")
    reg_num = int(match.group(1))
    if reg_num < 0 or reg_num > 15:
        raise ValueError(f"Register out of range R0-R15: 'R{reg_num}'")
    return reg_num

def parse_immediate(imm_str, max_bits=8, signed=False):
    """Parses immediate numbers supporting decimal and base-16 hex values."""
    imm_str = imm_str.strip()
    if imm_str.lower().startswith('0x'):
        val = int(imm_str, 16)
    else:
        val = int(imm_str, 10)

    # Boundary tracking masks
    mask = (1 << max_bits) - 1
    if signed:
        min_val = -(1 << (max_bits - 1))
        max_val = (1 << (max_bits - 1)) - 1
        if not (min_val <= val <= max_val):
            raise ValueError(f"Immediate value '{imm_str}' out of signed {max_bits}-bit boundary limits.")
        return val & mask
    else:
        if not (0 <= val <= mask):
            raise ValueError(f"Immediate value '{imm_str}' out of unsigned {max_bits}-bit boundary limits.")
        return val

def strip_line(line):
    """Remove comments and whitespace, return cleaned line or empty string."""
    line = line.split(';')[0].split('//')[0].strip()
    return line

def is_label_def(line):
    """Check if a line is a label definition (ends with colon)."""
    clean = strip_line(line)
    if not clean:
        return None
    if clean.endswith(':'):
        label = clean[:-1].strip()
        if re.match(r'^[A-Za-z_]\w*$', label):
            return label
    return None

def is_instruction(line):
    """Check if a stripped line contains an actual instruction (not blank, not label-only)."""
    clean = strip_line(line)
    if not clean:
        return False
    if clean.endswith(':'):
        return False
    return True

RESERVED_MNEMONICS = (
    set(OPCODES.keys()) | set(BRANCH_CONDITIONS.keys()) |
    {'NOP', 'RET', 'JAL', 'HALT', 'CMPI', 'MUL', 'MULH', 'DIV', 'MOD',
     'MOV', 'NOT', 'NEG', 'ROL', 'ROR', 'SEI', 'CLI', 'IRET', 'LUI'}
)

def count_directive_words(line):
    """Return how many 16-bit words a data directive produces, or 0 if not a directive."""
    tokens = line.replace(',', ' ').split()
    if not tokens:
        return 0
    directive = tokens[0].upper()
    if directive == '.WORD':
        return len(tokens) - 1
    elif directive == '.BYTE':
        num_bytes = len(tokens) - 1
        return (num_bytes + 1) // 2  # pack 2 bytes per word, pad if odd
    return 0

def pass_one(source_text):
    """First pass: collect label addresses and build a clean instruction/directive list."""
    labels = {}
    instructions = []
    addr = 0

    for line_num, raw_line in enumerate(source_text.strip().split('\n'), 1):
        clean = strip_line(raw_line)
        if not clean:
            continue

        label = is_label_def(clean)
        if label:
            if label.upper() in RESERVED_MNEMONICS:
                raise ValueError(f"Line {line_num}: Label '{label}' conflicts with a mnemonic name")
            if label in labels:
                raise ValueError(f"Line {line_num}: Duplicate label '{label}' (first defined at address {labels[label]})")
            labels[label] = addr
            rest = clean[len(label)+1:].strip()
            if rest:
                word_count = count_directive_words(rest)
                if word_count > 0:
                    instructions.append((line_num, rest))
                    addr += word_count
                else:
                    instructions.append((line_num, rest))
                    addr += 1
        else:
            word_count = count_directive_words(clean)
            if word_count > 0:
                instructions.append((line_num, clean))
                addr += word_count
            else:
                instructions.append((line_num, clean))
                addr += 1

    return labels, instructions

def resolve_operand(token, labels, current_addr, context='immediate'):
    """Try to resolve a token as a label; return the label's address or the original token."""
    stripped = token.strip()
    if stripped in labels:
        if context == 'branch_offset':
            offset = labels[stripped] - current_addr
            return str(offset)
        else:
            return str(labels[stripped])
    return stripped

def parse_value(token, labels):
    """Parse a numeric literal or label reference into an integer."""
    token = token.strip()
    if token in labels:
        return labels[token]
    if token.lower().startswith('0x'):
        return int(token, 16)
    return int(token, 10)

def assemble_directive(line, line_num, labels):
    """Assemble a data directive into one or more hex words. Returns a list."""
    tokens = line.replace(',', ' ').split()
    directive = tokens[0].upper()
    values = tokens[1:]

    if directive == '.WORD':
        words = []
        for v in values:
            val = parse_value(v, labels)
            if not (-32768 <= val <= 65535):
                raise ValueError(f".word value '{v}' out of 16-bit range")
            words.append(f"{val & 0xFFFF:04X} // .word {v}")
        return words

    elif directive == '.BYTE':
        byte_vals = []
        for v in values:
            val = parse_value(v, labels)
            if not (0 <= val <= 255):
                raise ValueError(f".byte value '{v}' out of 8-bit range (0-255)")
            byte_vals.append(val)
        if len(byte_vals) % 2 != 0:
            byte_vals.append(0)  # pad to even
        words = []
        for i in range(0, len(byte_vals), 2):
            word = (byte_vals[i] << 8) | byte_vals[i+1]
            words.append(f"{word:04X} // .byte {values[i]}" +
                         (f", {values[i+1]}" if i+1 < len(values) else ", 0x00 (pad)"))
        return words

    return None

def assemble_line(line, line_num, labels=None, current_addr=0):
    """Parses a single line of text assembly into a 16-bit hex word."""
    if not line:
        return None

    # Check for data directives first (before punctuation stripping)
    first_token = line.split()[0].upper() if line.split() else ''
    if first_token in ('.WORD', '.BYTE'):
        return assemble_directive(line, line_num, labels or {})

    # Replace punctuation characters with spaces for straightforward tokenization
    clean_line = line.replace(',', ' ').replace('[', ' ').replace(']', ' ').replace('+', ' ')
    tokens = clean_line.split()
    if not tokens:
        return None

    mnemonic = tokens[0].upper()
    if labels is None:
        labels = {}

    try:
        # 1. Handle ALU Math Operations (each gets its own opcode)
        if mnemonic in ALU_R_MNEMONICS:
            if len(tokens) < 4:
                raise ValueError(f"ALU instruction requires 3 registers: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            rt = parse_register(tokens[3])
            word = (OPCODES[mnemonic] << 12) | (rs << 8) | (rt << 4) | rd
            return f"{word:04X} // {line}"

        # 2. Handle LOAD/STORE Instructions
        elif mnemonic in ('LOAD', 'STORE'):
            if len(tokens) < 4:
                raise ValueError(f"Memory operation requires Target, Base, Offset: '{line}'")
            rt = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            imm4 = parse_immediate(tokens[3], max_bits=4)
            word = (OPCODES[mnemonic] << 12) | (rs << 8) | (rt << 4) | imm4
            return f"{word:04X} // {line}"

        # 3. Handle ADDI Instruction
        elif mnemonic == 'ADDI':
            if len(tokens) < 4:
                raise ValueError(f"ADDI requires Destination, Source, Immediate: '{line}'")
            rt = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            imm4 = parse_immediate(tokens[3], max_bits=4)
            word = (OPCODES['ADDI'] << 12) | (rs << 8) | (rt << 4) | imm4
            return f"{word:04X} // {line}"

        # Handle CMPI Instruction (sub-format of ADDI with Rt=0)
        elif mnemonic == 'CMPI':
            if len(tokens) < 3:
                raise ValueError(f"CMPI requires Source, Immediate: '{line}'")
            rs = parse_register(tokens[1])
            imm4 = parse_immediate(tokens[2], max_bits=4)
            word = (OPCODES['ADDI'] << 12) | (rs << 8) | (0 << 4) | imm4
            return f"{word:04X} // {line}"

        # Handle LUI Instruction (sub-format of POP: opcode 0x3 with imm8≠0)
        elif mnemonic == 'LUI':
            if len(tokens) < 3:
                raise ValueError(f"LUI requires Destination, Immediate: '{line}'")
            rd = parse_register(tokens[1])
            imm8 = parse_immediate(tokens[2], max_bits=8)
            if imm8 == 0:
                raise ValueError("LUI immediate must be non-zero (0 collides with POP encoding)")
            word = (OPCODES['POP'] << 12) | (rd << 8) | imm8
            return f"{word:04X} // {line}"

        # 4. Handle LIMM Instruction — supports label references as the immediate
        elif mnemonic == 'LIMM':
            if len(tokens) < 3:
                raise ValueError(f"LIMM requires Destination, Immediate: '{line}'")
            rd = parse_register(tokens[1])
            imm_token = resolve_operand(tokens[2], labels, current_addr)
            imm8 = parse_immediate(imm_token, max_bits=8)
            word = (OPCODES['LIMM'] << 12) | (rd << 8) | imm8
            return f"{word:04X} // {line}"

        # Handle MOV pseudo-instruction (encodes as OR Rd, Rs, Rs)
        elif mnemonic == 'MOV':
            if len(tokens) < 3:
                raise ValueError(f"MOV requires Destination, Source: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            word = (OPCODES['OR'] << 12) | (rs << 8) | (rs << 4) | rd
            return f"{word:04X} // {line}"

        # Handle NOT (sub-format of XOR: Rs==Rt)
        elif mnemonic == 'NOT':
            if len(tokens) < 3:
                raise ValueError(f"NOT requires Destination, Source: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            word = (OPCODES['XOR'] << 12) | (rs << 8) | (rs << 4) | rd
            return f"{word:04X} // {line}"

        # Handle NEG (sub-format of SUB: Rs==Rt)
        elif mnemonic == 'NEG':
            if len(tokens) < 3:
                raise ValueError(f"NEG requires Destination, Source: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            word = (OPCODES['SUB'] << 12) | (rs << 8) | (rs << 4) | rd
            return f"{word:04X} // {line}"

        # Handle ROL (sub-format of SHL: rd[3]=1, dest R0-R7)
        elif mnemonic == 'ROL':
            if len(tokens) < 4:
                raise ValueError(f"ROL requires 3 registers: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            rt = parse_register(tokens[3])
            if rd > 7:
                raise ValueError(f"ROL destination limited to R0-R7, got R{rd}")
            word = (OPCODES['SHL'] << 12) | (rs << 8) | (rt << 4) | (0x8 | rd)
            return f"{word:04X} // {line}"

        # Handle ROR (sub-format of SHR: rd[3]=1, dest R0-R7)
        elif mnemonic == 'ROR':
            if len(tokens) < 4:
                raise ValueError(f"ROR requires 3 registers: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            rt = parse_register(tokens[3])
            if rd > 7:
                raise ValueError(f"ROR destination limited to R0-R7, got R{rd}")
            word = (OPCODES['SHR'] << 12) | (rs << 8) | (rt << 4) | (0x8 | rd)
            return f"{word:04X} // {line}"

        # Handle PUSH Instruction (Opcode=0xE)
        elif mnemonic == 'PUSH':
            if len(tokens) < 2:
                raise ValueError(f"PUSH requires a source register: '{line}'")
            rs = parse_register(tokens[1])
            word = (OPCODES['PUSH'] << 12) | (rs << 8)
            return f"{word:04X} // {line}"

        # Handle POP Instruction (Opcode=0x3)
        elif mnemonic == 'POP':
            if len(tokens) < 2:
                raise ValueError(f"POP requires a destination register: '{line}'")
            rd = parse_register(tokens[1])
            word = (OPCODES['POP'] << 12) | (rd << 8)
            return f"{word:04X} // {line}"

        # 5. Handle Conditional Branches — supports label targets
        elif mnemonic in BRANCH_CONDITIONS:
            if len(tokens) < 2:
                raise ValueError(f"Branch instruction requires an offset or label target: '{line}'")
            cond = BRANCH_CONDITIONS[mnemonic]
            target_token = resolve_operand(tokens[1], labels, current_addr, context='branch_offset')
            offset8 = parse_immediate(target_token, max_bits=8, signed=True)
            word = (OPCODES['BRANCH'] << 12) | (cond << 8) | offset8
            return f"{word:04X} // {line}"

        # 6. Handle JAL Instruction
        elif mnemonic == 'JAL':
            if len(tokens) < 3:
                raise ValueError(f"JAL requires Link Register, Target Register: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            word = (OPCODES['JAL'] << 12) | (rs << 8) | (rd << 4)
            return f"{word:04X} // {line}"

        # Handle CALL Instruction (Opcode=0x7)
        elif mnemonic == 'CALL':
            if len(tokens) < 2:
                raise ValueError(f"CALL requires a target address register: '{line}'")
            rs = parse_register(tokens[1])
            word = (OPCODES['CALL'] << 12) | (rs << 8)
            return f"{word:04X} // {line}"

        # Handle RET Instruction (Opcode=0x7, sub-format 0x7000)
        elif mnemonic == 'RET':
            word = 0x7000
            return f"{word:04X} // {line}"

        elif mnemonic == 'IRET':
            word = 0x7001
            return f"{word:04X} // IRET"

        elif mnemonic == 'SEI':
            word = 0x7002
            return f"{word:04X} // SEI"

        elif mnemonic == 'CLI':
            word = 0x7003
            return f"{word:04X} // CLI"

        elif mnemonic == 'NOP':
            word = 0x6001
            return f"{word:04X} // NOP"

        elif mnemonic in ('MUL', 'MULH', 'DIV', 'MOD'):
            if len(tokens) < 4:
                raise ValueError(f"{mnemonic} requires 3 registers: '{line}'")
            rd = parse_register(tokens[1])
            rs = parse_register(tokens[2])
            rt = parse_register(tokens[3])
            if rd > 7:
                raise ValueError(f"{mnemonic} destination limited to R0-R7, got R{rd}")
            if rt > 7:
                raise ValueError(f"{mnemonic} second operand limited to R0-R7, got R{rt}")
            # rt[3]: 0=mul family, 1=div family; rd[3]: 0=low/quot, 1=high/rem
            rt_enc = rt | (0x8 if mnemonic in ('DIV', 'MOD') else 0x0)
            rd_enc = rd | (0x8 if mnemonic in ('MULH', 'MOD') else 0x0)
            if rs == 0 and rt_enc == 0 and rd_enc == 0:
                raise ValueError("MUL R0, R0, R0 collides with HALT encoding")
            word = (0xF << 12) | (rs << 8) | (rt_enc << 4) | rd_enc
            return f"{word:04X} // {line}"

        elif mnemonic == 'HALT':
            return f"F000 // HALT"

        else:
            raise ValueError(f"Unknown instruction mnemonic: '{mnemonic}'")

    except ValueError as err:
        print(f"Assembly Error on Line {line_num}: {err}", file=sys.stderr)
        return None

def assemble_program(source_text):
    """Two-pass assembler: resolves labels then encodes instructions."""
    # Pass 1: collect labels, build instruction list
    labels, instructions = pass_one(source_text)

    if labels:
        print(f"[LABELS] Resolved {len(labels)} label(s): {labels}")

    # Pass 2: assemble each instruction with label resolution
    binary_lines = []
    addr = 0
    for line_num, line_text in instructions:
        assembled = assemble_line(line_text, line_num, labels, addr)
        if assembled is None:
            continue
        if isinstance(assembled, list):
            binary_lines.extend(assembled)
            addr += len(assembled)
        else:
            binary_lines.append(assembled)
            addr += 1
    return binary_lines

def save_to_hex_file(hex_lines, filename="program.hex"):
    """Writes the pure 4-digit hex opcodes into a file for Verilog $readmemh."""
    try:
        with open(filename, 'w') as f:
            for line in hex_lines:
                clean_hex = line.split('//')[0].strip()
                f.write(f"{clean_hex}\n")
        print(f"[SUCCESS] Compiled machine code written to: {filename}")
    except IOError as e:
        print(f"[ERROR] Failed to write hex file: {e}")

def main():
    parser = argparse.ArgumentParser(description='U1624 Assembler — assemble .asm source into .hex machine code')
    parser.add_argument('input', help='Input assembly source file (.asm)')
    parser.add_argument('-o', '--output', default='program.hex', help='Output hex file (default: program.hex)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Print word mapping summary')
    args = parser.parse_args()

    try:
        with open(args.input, 'r') as f:
            assembly_code = f.read()
    except FileNotFoundError:
        print(f"Error: File not found: {args.input}", file=sys.stderr)
        sys.exit(1)
    except IOError as e:
        print(f"Error: Could not read file: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"--- U1624 Assembler ---")
    print(f"Source: {args.input}")
    hex_output = assemble_program(assembly_code)
    if hex_output:
        save_to_hex_file(hex_output, args.output)
        if args.verbose:
            print("\n--- Generated Word Mapping Summary ---")
            for index, instruction in enumerate(hex_output):
                print(f"sram[{index}] = 16'h{instruction}")
    else:
        print("Error: Assembly produced no output.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
