# =============================================================================
# Makefile — RISC-V QEMU OS + GUI build system
#
# Toolchain:  xPack RISC-V GCC (same as the main project)
# Target:     QEMU virt  (qemu-system-riscv32 -machine virt -nographic)
# Output:     build/qemu_os.elf  (loadable ELF)
#             build/qemu_os.bin  (raw binary, for direct load with -kernel)
#             build/qemu_os.dis  (disassembly listing)
#
# Usage:
#   make          — build everything
#   make run      — build and launch in QEMU
#   make clean    — remove build artefacts
# =============================================================================

# ── Toolchain path (matches the xPack install used by build.ps1) ───────────
TOOLCHAIN := C:/Users/ABDOU/Desktop/GP_folder/RISC-V/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin
CC        := $(TOOLCHAIN)/riscv-none-elf-gcc.exe
LD        := $(TOOLCHAIN)/riscv-none-elf-ld.exe
OBJCOPY   := $(TOOLCHAIN)/riscv-none-elf-objcopy.exe
OBJDUMP   := $(TOOLCHAIN)/riscv-none-elf-objdump.exe

# ── Compiler flags ─────────────────────────────────────────────────────────
#   -march=rv32ima_zicsr   — RV32 base + M(mul/div) + A(atomics) + Zicsr
#   -mabi=ilp32            — 32-bit integer, 32-bit pointer
#   -ffreestanding         — no standard library startup code
#   -nostdlib              — do not link libc or libgcc
#   -O2                    — optimise for size/speed (safe for bare-metal)
#   -Wall -Wextra          — catch common mistakes
#   -g                     — include debug info (useful with QEMU -s -S)
CFLAGS := -march=rv32ima_zicsr -mabi=ilp32 \
           -ffreestanding -nostdlib \
           -O2 -Wall -Wextra -g \
           -I include

ASFLAGS := -march=rv32ima_zicsr -mabi=ilp32 \
            -ffreestanding -nostdlib

LDFLAGS := -T linker_qemu.ld -nostdlib -m elf32lriscv

# ── Source files ────────────────────────────────────────────────────────────
SRCS_S := kernel/start.s

SRCS_C := kernel/kernel.c      \
           drivers/uart.c       \
           drivers/framebuffer.c \
           gui/gui.c             \
           apps/desktop.c

# ── Build directory ─────────────────────────────────────────────────────────
BUILD := build

# ── Derived object list ─────────────────────────────────────────────────────
OBJS_S := $(patsubst kernel/%.s,   $(BUILD)/%.o, $(SRCS_S))
OBJS_C := $(patsubst %.c,          $(BUILD)/%.o, $(notdir $(SRCS_C)))
OBJS   := $(OBJS_S) $(OBJS_C)

# ── Output artefacts ────────────────────────────────────────────────────────
ELF := $(BUILD)/qemu_os.elf
BIN := $(BUILD)/qemu_os.bin
DIS := $(BUILD)/qemu_os.dis

# =============================================================================
# Default target
# =============================================================================
.PHONY: all
all: $(ELF) $(BIN) $(DIS)
	@echo ""
	@echo "  =============================================="
	@echo "  Build complete!"
	@echo "  ELF : $(ELF)"
	@echo "  BIN : $(BIN)"
	@echo "  DIS : $(DIS)"
	@echo "  =============================================="
	@echo ""
	@echo "  To run: make run"
	@echo "  Or:     qemu-system-riscv32 -machine virt -nographic -bios none -kernel $(ELF)"
	@echo ""

# =============================================================================
# Link
# =============================================================================
$(ELF): $(OBJS)
	@echo "[LD]  $@"
	$(LD) $(LDFLAGS) $(OBJS) -o $@

# =============================================================================
# Raw binary
# =============================================================================
$(BIN): $(ELF)
	@echo "[BIN] $@"
	$(OBJCOPY) -O binary $< $@

# =============================================================================
# Disassembly
# =============================================================================
$(DIS): $(ELF)
	@echo "[DIS] $@"
	$(OBJDUMP) -d -S $< > $@

# =============================================================================
# Assemble start.s
# =============================================================================
$(BUILD)/start.o: kernel/start.s | $(BUILD)
	@echo "[AS]  $<"
	$(CC) $(ASFLAGS) -c $< -o $@

# =============================================================================
# Compile C sources (each file → object in BUILD/ flat directory)
# =============================================================================
$(BUILD)/kernel.o: kernel/kernel.c | $(BUILD)
	@echo "[CC]  $<"
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/uart.o: drivers/uart.c | $(BUILD)
	@echo "[CC]  $<"
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/framebuffer.o: drivers/framebuffer.c | $(BUILD)
	@echo "[CC]  $<"
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/gui.o: gui/gui.c | $(BUILD)
	@echo "[CC]  $<"
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/desktop.o: apps/desktop.c | $(BUILD)
	@echo "[CC]  $<"
	$(CC) $(CFLAGS) -c $< -o $@

# =============================================================================
# Create build directory
# =============================================================================
$(BUILD):
	mkdir -p $(BUILD)

# =============================================================================
# Run in QEMU
# =============================================================================
.PHONY: run
run: $(ELF)
	@echo ""
	@echo "  Starting QEMU... (Press Ctrl-A X to quit QEMU)"
	@echo ""
	qemu-system-riscv32 \
	    -machine virt    \
	    -nographic       \
	    -bios none       \
	    -m 128M          \
	    -kernel $(ELF)

# =============================================================================
# Debug: attach GDB
# =============================================================================
.PHONY: debug
debug: $(ELF)
	@echo "  Starting QEMU in debug mode (waiting for GDB on :1234)..."
	qemu-system-riscv32 \
	    -machine virt    \
	    -nographic       \
	    -bios none       \
	    -m 128M          \
	    -kernel $(ELF)   \
	    -s -S

# =============================================================================
# Clean
# =============================================================================
.PHONY: clean
clean:
	rm -rf $(BUILD)
	@echo "  Build directory removed."
