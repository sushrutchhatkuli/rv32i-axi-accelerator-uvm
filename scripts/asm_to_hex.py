#!/usr/bin/env python3
# =============================================================================
# File: asm_to_hex.py
# Project: Heterogeneous RISC-V SoC with AXI4-Lite & Accelerator
# Description: Standalone RV32I Assembler.
#              Assembles RISC-V assembly source into 32-bit hex words for
#              SystemVerilog $readmemh memory initialization.
# =============================================================================

import sys, re

REG_MAP = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7, 's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15, 'a6': 16, 'a7': 17,
    's2': 18, 's3': 19, 's4': 20, 's5': 21, 's6': 22, 's7': 23, 's8': 24, 's9': 25,
    's10': 26, 's11': 27, 't3': 28, 't4': 29, 't5': 30, 't6': 31
}

def parse_val(s):
    s = s.strip()
    return int(s, 0)

def parse_reg(s):
    s = s.strip().lower()
    if s in REG_MAP:
        return REG_MAP[s]
    if s.startswith('x'):
        return int(s[1:])
    raise ValueError(f"Unknown register: {s}")

def assemble(input_file, output_file):
    with open(input_file, 'r') as f:
        lines = f.readlines()

    # Pass 1: Collect labels and strip comments/directives
    labels = {}
    clean_lines = []
    pc = 0

    for line in lines:
        line = line.split('#')[0].strip()
        if not line:
            continue
        if line.startswith('.'):
            continue

        # Check for label
        if ':' in line:
            parts = line.split(':')
            label = parts[0].strip()
            labels[label] = pc
            rem = ':'.join(parts[1:]).strip()
            if rem:
                clean_lines.append((pc, rem))
                pc += 4
        else:
            clean_lines.append((pc, line))
            pc += 4

    # Pass 2: Encode instructions
    hex_words = []
    for cur_pc, line in clean_lines:
        tokens = re.split(r'[\s,()]+', line.strip())
        tokens = [t for t in tokens if t]
        op = tokens[0].lower()

        instr = 0
        if op == 'lui':
            rd = parse_reg(tokens[1])
            imm = parse_val(tokens[2])
            instr = ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37

        elif op == 'ori':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            imm = parse_val(tokens[3])
            instr = ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b110 << 12) | (rd << 7) | 0x13

        elif op == 'addi':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            imm = parse_val(tokens[3])
            instr = ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0x13

        elif op == 'andi':
            rd = parse_reg(tokens[1])
            rs1 = parse_reg(tokens[2])
            imm = parse_val(tokens[3])
            instr = ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b111 << 12) | (rd << 7) | 0x13

        elif op == 'lw':
            rd = parse_reg(tokens[1])
            imm = parse_val(tokens[2])
            rs1 = parse_reg(tokens[3])
            instr = ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b010 << 12) | (rd << 7) | 0x03

        elif op == 'sw':
            rs2 = parse_reg(tokens[1])
            imm = parse_val(tokens[2])
            rs1 = parse_reg(tokens[3])
            imm_11_5 = (imm >> 5) & 0x7F
            imm_4_0  = imm & 0x1F
            instr = (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0b010 << 12) | (imm_4_0 << 7) | 0x23

        elif op == 'beq':
            rs1 = parse_reg(tokens[1])
            rs2 = parse_reg(tokens[2])
            target = tokens[3]
            offset = labels[target] - cur_pc
            b_imm = (((offset >> 12) & 1) << 31) | (((offset >> 5) & 0x3F) << 25) | (((offset >> 1) & 0xF) << 8) | (((offset >> 11) & 1) << 7)
            instr = b_imm | (rs2 << 20) | (rs1 << 15) | (0b000 << 12) | 0x63

        elif op == 'bne':
            rs1 = parse_reg(tokens[1])
            rs2 = parse_reg(tokens[2])
            target = tokens[3]
            offset = labels[target] - cur_pc
            b_imm = (((offset >> 12) & 1) << 31) | (((offset >> 5) & 0x3F) << 25) | (((offset >> 1) & 0xF) << 8) | (((offset >> 11) & 1) << 7)
            instr = b_imm | (rs2 << 20) | (rs1 << 15) | (0b001 << 12) | 0x63

        elif op == 'j':
            target = tokens[1]
            offset = labels[target] - cur_pc
            j_imm = (((offset >> 20) & 1) << 31) | (((offset >> 1) & 0x3FF) << 21) | (((offset >> 11) & 1) << 20) | (((offset >> 12) & 0xFF) << 12)
            instr = j_imm | (0 << 7) | 0x6F

        elif op == 'nop':
            instr = 0x00000013

        else:
            raise ValueError(f"Unsupported instruction: {op} at PC 0x{cur_pc:04x}")

        hex_words.append(f"{instr:08x}")

    with open(output_file, 'w') as f:
        for hw in hex_words:
            f.write(f"{hw}\n")

    print(f"[ASSEMBLER] Successfully assembled {len(hex_words)} instructions ({len(hex_words)*4} bytes) into {output_file}")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 asm_to_hex.py <input.s> <output.hex>")
        sys.exit(1)
    assemble(sys.argv[1], sys.argv[2])
