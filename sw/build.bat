@echo off
set "ToolchainPath=..\..\..\riscv-toolchain\xpack-riscv-none-elf-gcc-15.2.0-1\bin"

where /q riscv-none-elf-gcc
if errorlevel 1 (
    set "CC=%ToolchainPath%\riscv-none-elf-gcc.exe"
    set "LD=%ToolchainPath%\riscv-none-elf-ld.exe"
    set "OBJDUMP=%ToolchainPath%\riscv-none-elf-objdump.exe"
) else (
    set "CC=riscv-none-elf-gcc"
    set "LD=riscv-none-elf-ld"
    set "OBJDUMP=riscv-none-elf-objdump"
)

if not exist build mkdir build

echo Compiling start.s...
"%CC%" -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -nostdlib -c src\start.s -o build\start.o
if %ERRORLEVEL% neq 0 (
    echo Failed to compile start.s
    exit /b %ERRORLEVEL%
)

echo Compiling main.c...
"%CC%" -march=rv32im_zicsr -mabi=ilp32 -ffreestanding -nostdlib -O1 -c src\main.c -o build\main.o
if %ERRORLEVEL% neq 0 (
    echo Failed to compile main.c
    exit /b %ERRORLEVEL%
)

echo Linking...
"%LD%" -T linker.ld -nostdlib -m elf32lriscv build\start.o build\main.o -o build\firmware.elf
if %ERRORLEVEL% neq 0 (
    echo Failed to link firmware.elf
    exit /b %ERRORLEVEL%
)

echo Converting ELF to firmware.hex...
python elf2hex.py build\firmware.elf build\firmware.hex
if %ERRORLEVEL% neq 0 (
    echo Failed to convert to hex
    exit /b %ERRORLEVEL%
)

echo Generating disassembly...
"%OBJDUMP%" -d build\firmware.elf > build\firmware.dis

echo Build Successful!
