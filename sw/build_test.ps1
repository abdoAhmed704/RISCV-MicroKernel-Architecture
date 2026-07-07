# ==============================================================
# RISC-V RV32I Assembly Test Build Script
# Compiles: rtl/RV32I/riscv_test.s -> sw/build/firmware.hex
# ==============================================================

$ToolchainPath = "C:/Users/ABDOU/Desktop/GP_folder/RISC-V/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/"
$CC = "${ToolchainPath}riscv-none-elf-gcc.exe"
$LD = "${ToolchainPath}riscv-none-elf-ld.exe"
$OBJDUMP = "${ToolchainPath}riscv-none-elf-objdump.exe"

# Create build directory if it doesn't exist
if (-not (Test-Path "build")) {
    New-Item -ItemType Directory -Path "build" | Out-Null
}

Write-Host "Compiling riscv_test.s..." -ForegroundColor Cyan
& $CC -march=rv32ic_zicsr -mabi=ilp32 -ffreestanding -nostdlib -c src/riscv_test.s -o build/riscv_test.o
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to compile riscv_test.s"; exit 1 }

Write-Host "Linking..." -ForegroundColor Cyan
& $LD -T linker.ld -nostdlib -m elf32lriscv build/riscv_test.o -o build/firmware.elf
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to link firmware.elf"; exit 1 }

Write-Host "Converting ELF to firmware.hex..." -ForegroundColor Cyan
python elf2hex.py build/firmware.elf build/firmware.hex
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to convert to hex"; exit 1 }

Write-Host "Generating disassembly..." -ForegroundColor Cyan
& $OBJDUMP -d build/firmware.elf > build/firmware.dis

Write-Host "Build Successful! firmware.hex updated at sw/build/firmware.hex" -ForegroundColor Green
