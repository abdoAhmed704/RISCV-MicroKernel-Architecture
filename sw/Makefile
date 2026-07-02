# ==============================================================
# RISC-V RV32I Bare-Metal Makefile
# ==============================================================
CROSS = C:/Users/ABDOU/Desktop/GP_folder/RISC-V/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-


CC      = $(CROSS)gcc
LD      = $(CROSS)ld
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump

# CRITICAL FLAGS:
#   -march=rv32i   → ONLY base integer instructions (no M, A, F, D, C)
#   -mabi=ilp32    → 32-bit integer ABI, no float
#   -nostdlib      → no C standard library
#   -ffreestanding → freestanding (no OS)
#   -O1            → optimize to reduce stack usage
CFLAGS  = -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib -O1 -Wall
ASFLAGS = -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib
LDFLAGS = -T linker.ld -nostdlib -m elf32lriscv

OBJS    = build/start.o build/main.o
TARGET  = build/firmware

all: $(TARGET).hex $(TARGET).dis
	@echo "=== Build complete ==="
	@echo "Hex file: $(TARGET).hex"

build/start.o: src/start.s | build
	$(CC) $(ASFLAGS) -c $< -o $@

build/main.o: src/main.c | build
	$(CC) $(CFLAGS) -c $< -o $@

$(TARGET).elf: $(OBJS)
	$(LD) $(LDFLAGS) $(OBJS) -o $@

# Convert ELF to plain hex (one 32-bit word per line) for $readmemh
$(TARGET).hex: $(TARGET).elf
	python elf2hex.py $< $@

# Generate disassembly for debugging
$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

build:
	@if not exist build mkdir build

clean:
	@if exist build\*.o del /Q build\*.o
	@if exist build\firmware.* del /Q build\firmware.*

.PHONY: all clean
