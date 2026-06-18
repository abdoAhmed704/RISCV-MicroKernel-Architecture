#!/usr/bin/env python3
"""
Convert a RISC-V ELF file to a plain hex file for $readmemh.
Outputs one 32-bit word per line in hex (big-endian word order).

Usage:
    python elf2hex.py build/firmware.elf build/firmware.hex
"""
import sys
import struct

def elf2hex(elf_path, hex_path):
    with open(elf_path, "rb") as f:
        elf = f.read()

    # Parse ELF header (32-bit little-endian)
    if elf[:4] != b'\x7fELF':
        print(f"Error: {elf_path} is not an ELF file", file=sys.stderr)
        sys.exit(1)

    ei_class = elf[4]  # 1 = 32-bit, 2 = 64-bit
    if ei_class != 1:
        print("Error: Only 32-bit ELF files are supported", file=sys.stderr)
        sys.exit(1)

    # ELF32 header fields
    e_phoff = struct.unpack_from('<I', elf, 28)[0]  # Program header offset
    e_phentsize = struct.unpack_from('<H', elf, 42)[0]  # Program header entry size
    e_phnum = struct.unpack_from('<H', elf, 44)[0]  # Number of program headers

    # Collect all loadable segments
    segments = []
    for i in range(e_phnum):
        ph_offset = e_phoff + i * e_phentsize
        p_type   = struct.unpack_from('<I', elf, ph_offset + 0)[0]
        p_offset = struct.unpack_from('<I', elf, ph_offset + 4)[0]
        p_vaddr  = struct.unpack_from('<I', elf, ph_offset + 8)[0]
        p_filesz = struct.unpack_from('<I', elf, ph_offset + 16)[0]
        p_memsz  = struct.unpack_from('<I', elf, ph_offset + 20)[0]

        if p_type == 1 and p_filesz > 0:  # PT_LOAD
            data = elf[p_offset:p_offset + p_filesz]
            segments.append((p_vaddr, data, p_memsz))

    if not segments:
        print("Error: No loadable segments found in ELF", file=sys.stderr)
        sys.exit(1)

    # Find the address range
    min_addr = min(seg[0] for seg in segments)
    max_addr = max(seg[0] + seg[2] for seg in segments)

    # Create a flat memory image
    mem_size = max_addr - min_addr
    memory = bytearray(mem_size)

    for vaddr, data, memsz in segments:
        offset = vaddr - min_addr
        memory[offset:offset + len(data)] = data

    # Pad to word boundary
    while len(memory) % 4 != 0:
        memory.append(0)

    # Write as one 32-bit hex word per line
    with open(hex_path, "w") as f:
        for i in range(0, len(memory), 4):
            word = struct.unpack_from('<I', memory, i)[0]  # Little-endian word
            f.write(f"{word:08X}\n")

    n_words = len(memory) // 4
    print(f"Converted {elf_path} -> {hex_path} ({n_words} words, "
          f"addr range 0x{min_addr:08X}-0x{max_addr:08X})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.elf> <output.hex>", file=sys.stderr)
        sys.exit(1)
    elf2hex(sys.argv[1], sys.argv[2])
