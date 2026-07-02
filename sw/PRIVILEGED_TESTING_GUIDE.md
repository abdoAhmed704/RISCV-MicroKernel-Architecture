# RISC-V Privileged & Zicsr ISA Testing Guide

This guide describes how to write, compile, and simulate test programs verifying Zicsr (Control and Status Register) instructions, system calls, exception traps, privilege mode switching, and delegation.

---

## 1. Zicsr & Privileged Instruction Reference

### CSR Register Instructions (Zicsr)
The `rs1` register holds the source value, and `rd` holds the previous value of the CSR. Writing `x0`/`zero` to `rs1` prevents writes, and reading to `x0`/`zero` disables reads (unless writing).

| Assembly Instruction | Pseudocode | Privilege Level Gated? | Description |
|:---|:---|:---|:---|
| `csrrw rd, csr, rs1` | `rd = CSR; CSR = rs1` | Yes (by CSR address) | **CSR Read and Write**: Swaps the register value with the CSR. |
| `csrrs rd, csr, rs1` | `rd = CSR; CSR \|= rs1` | Yes (by CSR address) | **CSR Read and Set**: Reads the CSR and performs bitwise-OR using the mask in `rs1`. |
| `csrrc rd, csr, rs1` | `rd = CSR; CSR &= ~rs1` | Yes (by CSR address) | **CSR Read and Clear**: Reads the CSR and performs bitwise-AND with the inverted mask in `rs1`. |
| `csrrwi rd, csr, uimm` | `rd = CSR; CSR = uimm` | Yes (by CSR address) | **CSR Read and Write Immediate**: Swaps CSR with a 5-bit zero-extended immediate `uimm` (bits 19:15). |
| `csrrsi rd, csr, uimm` | `rd = CSR; CSR \|= uimm` | Yes (by CSR address) | **CSR Read and Set Immediate**: Bitwise-ORs the CSR with a 5-bit immediate. |
| `csrrci rd, csr, uimm` | `rd = CSR; CSR &= ~uimm` | Yes (by CSR address) | **CSR Read and Clear Immediate**: Bitwise-ANDs the CSR with the inverted 5-bit immediate. |

### Privileged Control Instructions

| Assembly Instruction | Hardware Action | Description |
|:---|:---|:---|
| `ecall` | Traps to high privilege. Updates `mepc`/`sepc` with instruction PC and `mcause`/`scause` with cause (`9`/`11`). | **Environment Call**: Requests exception escalation from S-mode/U-mode to M-mode. |
| `ebreak` | Traps to debugger vector. Updates `mepc`/`sepc` with instruction PC and `mcause`/`scause` with cause (`3`). | **Breakpoint**: Enters debug handler mode. |
| `mret` | `priv_mode <= mstatus.MPP`<br>`mstatus.MIE <= mstatus.MPIE`<br>`PC <= mepc` | **Machine Mode Trap Return**: Returns from M-mode exception handler to prior mode and location. |
| `sret` | `priv_mode <= sstatus.SPP`<br>`sstatus.SIE <= sstatus.SPIE`<br>`PC <= sepc` | **Supervisor Mode Trap Return**: Returns from S-mode exception handler to prior mode and location. |

---

## 2. Direct Assembly Testing

You can write bare-metal assembly tests in `.s` files. To do so, set up a stack, execute the instructions, and use registers (`a0`, `a1`) to track test status.

### Assembly Test File (`sw/src/assembly_test.s`)
Create a basic test file like the following:

```assembly
.section .text
.global _start

_start:
    # 1. Initialize Stack
    li sp, 0x00000F00

    # 2. Register Trap Vector Address (Must be 4-byte aligned)
    la t0, test_trap_handler
    csrw mtvec, t0

    # 3. Test csrrw (Read-Write)
    li t1, 0xDEADBEEF
    csrrw a0, mscratch, t1     # Write 0xDEADBEEF to mscratch. a0 gets old value (0)
    csrr  a1, mscratch         # Read mscratch back into a1
    bne a1, t1, fail_csrrw     # Verify roundtrip

    # 4. Test csrrs (Read-Set bits)
    li t2, 0x0000F000
    csrrs a2, mscratch, t2     # a2 = 0xDEADBEEF. mscratch becomes 0xDEABFEEF
    csrr  a3, mscratch
    li t3, 0xDEABFEEF
    bne a3, t3, fail_csrrs

    # 5. Test csrrwi (Immediate Read-Write)
    csrrwi a4, mscratch, 15    # a4 = 0xDEABFEEF. mscratch becomes 15 (0xF)
    csrr   a5, mscratch
    li t4, 15
    bne a5, t4, fail_csri

    # 6. Test ecall
    ecall                      # Jump to trap handler
    
    # 7. Check if trap handler executed successfully
    li t0, 1
    bne s0, t0, fail_ecall     # Handler should set s0 = 1

    # SUCCESS: Return 15 (0xF) in a0
    li a0, 15
    j exit

fail_csrrw: li a0, 1
            j exit
fail_csrrs: li a0, 2
            j exit
fail_csri:  li a0, 3
            j exit
fail_ecall: li a0, 4
            j exit

exit:
    # Loop here forever. You will see the return code in the Questasim register trace (a0).
loop:
    j loop

# M-Mode Trap Handler
.align 4
test_trap_handler:
    # Check if trap was due to ECALL (mcause = 11)
    csrr t5, mcause
    li t6, 11
    bne t5, t6, handler_end

    # Increment mepc by 4 to resume execution AFTER the ecall instruction
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5

    # Set success flag in s0
    li s0, 1

handler_end:
    mret
```

---

## 3. Inline Assembly C Testing

Using C lets you check complex structures and states with high-level logic, while using `asm volatile` block segments for privileged routines.

### Inline C Test File (`sw/src/main.c`)
```c
volatile int trap_success = 0;

void my_handler(void);

int main() {
    // 1. Basic Zicsr write/read check
    unsigned int test_val = 0x55AAAA55;
    unsigned int read_val = 0;
    
    // Write value into machine scratch register
    asm volatile ("csrw mscratch, %0" :: "r"(test_val));
    // Read it back
    asm volatile ("csrr %0, mscratch" : "=r"(read_val));
    
    if (read_val != test_val) {
        return 1; // Code 1: basic CSR RW failure
    }

    // 2. Set bits using mask
    unsigned int mask = 0x000000FF; // set low byte
    asm volatile ("csrrs zero, mscratch, %0" :: "r"(mask));
    asm volatile ("csrr %0, mscratch" : "=r"(read_val));
    
    if (read_val != (test_val | mask)) {
        return 2; // Code 2: CSR set bits failed
    }

    // 3. Register M-mode handler and trigger an exception
    asm volatile ("csrw mtvec, %0" :: "r"((unsigned int)my_handler & ~0x3));
    
    trap_success = 0;
    asm volatile ("ecall"); // triggers trap
    
    if (trap_success != 1) {
        return 3; // Code 3: Trap execution failed
    }

    // Success code 15
    return 15;
}
```

---

## 4. How to Compile

### Toolchain Prerequisites
You are using the RISC-V GCC compiler toolchain configured for bare-metal targets:
*   Compiler flag `-march=rv32i_zicsr` is mandatory to instruct the assembler/compiler to recognize CSR instructions (e.g., `csrrw`, `mret`).
*   Compiler flag `-mabi=ilp32` sets standard 32-bit integer register passing.

### Step-by-Step Build Script Execution

The PowerShell script `build.ps1` automates compiling and linking your code.

1.  **For pure Assembly testing:**
    Open `sw/build.ps1` and modify the linking command to only compile the assembly test:
    ```powershell
    & $CC -march=rv32i_zicsr -mabi=ilp32 -ffreestanding -nostdlib -c src/assembly_test.s -o build/assembly_test.o
    & $LD -T linker.ld -nostdlib -m elf32lriscv build/assembly_test.o -o build/firmware.elf
    ```
2.  **For C/Assembly testing (our current setup):**
    Run the build script directly in PowerShell:
    ```powershell
    cd sw
    powershell -ExecutionPolicy Bypass -File .\build.ps1
    ```
    This generates:
    *   `build/firmware.elf`: Linker binary target.
    *   `build/firmware.hex`: 32-bit instruction memory block formatting file.
    *   `build/firmware.dis`: Read-friendly assembly disassembly layout.

---

## 5. How to Simulate in QuestaSim

### Running simulation
Navigate to the RTL simulation directory and invoke compiler/simulators:

```powershell
cd rtl/RV32I
# 1. Compile all CPU RTL modules and testbenches
vlog riscv_*.sv

# 2. Run simulation in command-line mode
vsim -c -voptargs=+acc work.riscv_top_tb -do "run -all; quit"
```

### Analyzing Register Changes
During execution, look at the testbench console logging output (printed by `riscv_top_tb.sv`):
*   `Mode`: Shows privilege level (`11` = M-mode, `01` = S-mode).
*   `mepc` / `sepc`: Displays saved return PCs after trap events.
*   `mcause` / `scause`: Shows reason codes for exceptions/interrupts.
*   `result`: Tracks return values written back to registers (such as register `x10`/`a0`).

Once the trace finishes, checking `RdW=10 Res=0000000f` confirms that `main()` returned `15` and successfully completed testing.
