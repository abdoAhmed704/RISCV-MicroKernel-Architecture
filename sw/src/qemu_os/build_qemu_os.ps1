# build_qemu_os.ps1 - Windows PowerShell build script for RISC-V QEMU OS + GUI
# Usage: powershell -ExecutionPolicy Bypass -File .\build_qemu_os.ps1

$ErrorActionPreference = "Stop"

# Toolchain
$BIN  = "C:\Users\ABDOU\Desktop\GP_folder\RISC-V\riscv-toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin"
$CC   = "$BIN\riscv-none-elf-gcc.exe"
$LD   = "$BIN\riscv-none-elf-ld.exe"
$OBJCOPY = "$BIN\riscv-none-elf-objcopy.exe"
$OBJDUMP = "$BIN\riscv-none-elf-objdump.exe"

# Compiler / linker flag strings (expanded inline)
$MFLAGS = @("-march=rv32ima_zicsr", "-mabi=ilp32")
$CFLAGS  = $MFLAGS + @("-ffreestanding", "-nostdlib", "-O2", "-Wall", "-Wextra", "-g", "-Iinclude")
$ASFLAGS = $MFLAGS + @("-ffreestanding", "-nostdlib")

# Create build output directory
if (-not (Test-Path "build")) {
    New-Item -ItemType Directory -Path "build" | Out-Null
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  RISC-V QEMU OS + GUI  - Build Script"        -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# --- Compile start.s (assembly) ---
Write-Host "  [AS]  kernel\start.s ..." -NoNewline
& $CC @ASFLAGS -c kernel\start.s -o build\start.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Compile kernel.c ---
Write-Host "  [CC]  kernel\kernel.c ..." -NoNewline
& $CC @CFLAGS -c kernel\kernel.c -o build\kernel.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Compile uart.c ---
Write-Host "  [CC]  drivers\uart.c ..." -NoNewline
& $CC @CFLAGS -c drivers\uart.c -o build\uart.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Compile framebuffer.c ---
Write-Host "  [CC]  drivers\framebuffer.c ..." -NoNewline
& $CC @CFLAGS -c drivers\framebuffer.c -o build\framebuffer.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Compile gui.c ---
Write-Host "  [CC]  gui\gui.c ..." -NoNewline
& $CC @CFLAGS -c gui\gui.c -o build\gui.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Compile kmem.c (memset/memcpy for GCC freestanding builds) ---
Write-Host "  [CC]  kernel\kmem.c ..." -NoNewline
& $CC @CFLAGS -c kernel\kmem.c -o build\kmem.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Compile desktop.c ---
Write-Host "  [CC]  apps\desktop.c ..." -NoNewline
& $CC @CFLAGS -c apps\desktop.c -o build\desktop.o
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Link ---
Write-Host ""
Write-Host "  [LD]  build\qemu_os.elf ..." -NoNewline
& $LD -T linker_qemu.ld -nostdlib -m elf32lriscv `
      build\start.o `
      build\kernel.o `
      build\kmem.o `
      build\uart.o `
      build\framebuffer.o `
      build\gui.o `
      build\desktop.o `
      -o build\qemu_os.elf
if ($LASTEXITCODE -ne 0) { Write-Host " FAILED" -ForegroundColor Red; exit 1 }
Write-Host " OK" -ForegroundColor Green

# --- Raw binary ---
Write-Host "  [BIN] build\qemu_os.bin ..." -NoNewline
& $OBJCOPY -O binary build\qemu_os.elf build\qemu_os.bin
Write-Host " OK" -ForegroundColor Green

# --- Disassembly ---
Write-Host "  [DIS] build\qemu_os.dis ..." -NoNewline
& $OBJDUMP -d -S build\qemu_os.elf > build\qemu_os.dis
Write-Host " OK" -ForegroundColor Green

# --- Summary ---
Write-Host ""
$elfSize = (Get-Item "build\qemu_os.elf").Length
$binSize = (Get-Item "build\qemu_os.bin").Length
Write-Host "  Output:" -ForegroundColor Yellow
Write-Host "    qemu_os.elf  $elfSize bytes"
Write-Host "    qemu_os.bin  $binSize bytes"
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Build SUCCESSFUL!"                              -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Run with:"  -ForegroundColor Yellow
Write-Host "    qemu-system-riscv32 -machine virt -nographic -bios none -m 128M -kernel build\qemu_os.elf"
Write-Host ""
Write-Host "  Quit QEMU: press Ctrl-A then X"  -ForegroundColor Cyan
Write-Host ""
