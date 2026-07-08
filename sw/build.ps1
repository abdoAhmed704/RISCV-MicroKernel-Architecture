# ==============================================================
# RISC-V RV32I Bare-Metal Build Script
# ==============================================================

$ToolchainPath = "C:/Users/ABDOU/Desktop/GP_folder/RISC-V/riscv-toolchain/xpack-riscv-none-elf-gcc-15.2.0-1/bin/"
$CC = "${ToolchainPath}riscv-none-elf-gcc.exe"
$LD = "${ToolchainPath}riscv-none-elf-ld.exe"
$OBJDUMP = "${ToolchainPath}riscv-none-elf-objdump.exe"

# Create build directory if it doesn't exist
if (-not (Test-Path "build")) {
    New-Item -ItemType Directory -Path "build" | Out-Null
}

Write-Host "Compiling start.s..."
& $CC -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -nostdlib -c src/start.s -o build/start.o
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to compile start.s"; exit 1 }

Write-Host "Compiling main.c..."
& $CC -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -nostdlib -O1 -c src/main.c -o build/main.o
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to compile main.c"; exit 1 }

Write-Host "Linking..."
& $LD -T linker.ld -nostdlib -m elf32lriscv build/start.o build/main.o -o build/firmware.elf
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to link firmware.elf"; exit 1 }

Write-Host "Converting ELF to firmware.hex..."
python elf2hex.py build/firmware.elf build/firmware.hex
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to convert to hex"; exit 1 }

Write-Host "Generating disassembly..."
Get-Content -Path "build/firmware.dis" -ErrorAction SilentlyContinue | Out-Null
& $OBJDUMP -d build/firmware.elf > build/firmware.dis

Write-Host "Build Successful!" -ForegroundColor Green
