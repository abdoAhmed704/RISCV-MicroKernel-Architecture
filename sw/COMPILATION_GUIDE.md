# RISC-V Compilation Guide: C & Assembly to firmware.hex

This workspace contains two distinct testing flows:
1. **Pure Assembly testing** (`riscv_test.s`) — testing baseline CPU pipelines, forwarding, hazards, and branches.
2. **C / Assembly mixed testing** (`start.s` + `main.c`) — testing privilege execution, CSR behavior, delegation, and traps.

Both compilation paths generate the file **`sw/build/firmware.hex`**, which is loaded automatically by your Questasim/ModelSim simulation environment.

---

Ensure the RISC-V GCC toolchain is available on your system PATH. The scripts assume the toolchain executables (like `riscv-none-elf-gcc`) are directly runnable, or they fallback to looking in a configured local directory.

---

## Option 1: Pure Assembly Compilation (`riscv_test.s`)

This mode compiles [riscv_test.s](src/riscv_test.s) directly to test base integer execution, stalls, forwarding, and branches.

### Automatic Scripts (Recommended)
Navigate to the `sw/` folder in your terminal and execute:

* **Command Prompt (CMD):**
  ```cmd
  cd sw
  build_test.bat
  ```
* **PowerShell:**
  ```powershell
  cd sw
  ./build_test.ps1
  ```

### Manual Command-by-Command Flow
1. **Compile assembly to object file:**
   ```cmd
   riscv-none-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib -c src/riscv_test.s -o build/riscv_test.o
   ```
2. **Link to ELF binary:**
   ```cmd
   riscv-none-elf-ld -T linker.ld -nostdlib -m elf32lriscv build/riscv_test.o -o build/firmware.elf
   ```
3. **Convert ELF to HEX:**
   ```cmd
   python elf2hex.py build/firmware.elf build/firmware.hex
   ```

---

## Option 2: C / Assembly Mixed Compilation (`start.s` + `main.c`)

This mode compiles [start.s](src/start.s) and [main.c](src/main.c) together to test traps, interrupts, privilege levels, and delegation.

### Automatic Scripts (Recommended)
Navigate to the `sw/` folder in your terminal and execute:

* **Command Prompt (CMD):**
  ```cmd
  cd sw
  build.bat
  ```
* **PowerShell:**
  ```powershell
  cd sw
  ./build.ps1
  ```
* **Linux / Make Utility:**
  ```bash
  cd sw
  make all
  ```

### Manual Command-by-Command Flow
1. **Compile the assembly bootloader:**
   ```cmd
   riscv-none-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib -c src/start.s -o build/start.o
   ```
2. **Compile the main C program:**
   ```cmd
   riscv-none-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib -O1 -c src/main.c -o build/main.o
   ```
3. **Link both files together:**
   ```cmd
   riscv-none-elf-ld -T linker.ld -nostdlib -m elf32lriscv build/start.o build/main.o -o build/firmware.elf
   ```
4. **Convert ELF to HEX:**
   ```cmd
   python elf2hex.py build/firmware.elf build/firmware.hex
   ```

---

## 🔍 How to Verify the Result
After compilation, you can check:
- **`sw/build/firmware.dis`**: The generated assembly disassembly. Open this file to see the exact instruction addresses and machine code.
- **`sw/build/firmware.hex`**: The 32-bit hexadecimal lines loaded by your hardware simulator.
