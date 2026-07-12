---
# From Gates to Games
## A Complete RISC-V Hardware-Software Co-Design

> **RV32I 5-Stage Pipelined CPU - Privileged ISA - Nano-OS Microkernel - Snake Game**

---

# Agenda

| # | Topic |
|---|-------|
| 1 | Architecture Overview |
| 2 | Privileged ISA and Privilege Levels |
| 3 | CSR Unit Architecture |
| 4 | Machine-Level CSRs |
| 5 | Supervisor-Level CSRs |
| 6 | CSR Instructions (Zicsr) |
| 7 | Trap Handling |
| 8 | Trap Return: MRET and SRET |
| 9 | Software Stack Overview |
| 10 | Bootstrap Loader (start.s) |
| 11 | Nano-OS Kernel (main.c) |
| 12 | The Snake Game |
| 13 | Running and Simulation |
| 14 | Integration Testing |
| 15 | Summary |

---

---

# PART I -- Hardware Architecture

---

---

# Slide 1 -- Full System Overview

## From Gates to Games

A complete **hardware-software co-design** implemented from the register-transfer level
all the way up to an interactive terminal application.

```
+-----------------------------------------------------------------------+
|                       Interactive Application                         |
|                 Snake Game (WASD keyboard input)                      |
|                          C -- bare metal                              |
+-----------------------------------------------------------------------+
|                          Nano-OS Kernel                               |
|          Syscalls via ECALL - MMIO UART Driver - Trap handlers        |
|                       C -- no standard library                        |
+-----------------------------------------------------------------------+
|                         Bootstrap Loader                              |
|           Reset Entry - Stack Setup - CSR Init - Trap Vectors         |
|                       RISC-V Assembly (start.s)                       |
+-----------------------------------------------------------------------+
|                        Hardware Platform (RTL)                        |
|      RV32I 5-Stage Pipeline - CSR Unit - Data Memory - MMIO UART      |
|                           SystemVerilog                               |
+-----------------------------------------------------------------------+
```

**Key Principle:** Each layer talks to the one below through well-defined hardware interfaces.

---

# Slide 2 -- 5-Stage Pipeline Datapath

## RV32I Pipelined Core

```
  +--------+   +--------+   +--------+   +--------+   +--------+
  |   IF   |-->|   ID   |-->|   EX   |-->|  MEM   |-->|   WB   |
  |  Fetch |   | Decode |   |Execute |   | Memory |   |Writebk |
  +--------+   +--------+   +--------+   +--------+   +--------+
       |              |           |            |
   IMEM (ROM)     RegFile      32-bit ALU    DMEM + MMIO
                  Ctrl Unit    PC Target     CSR Unit <-- lives here
                  Extend       Forwarding
```

| Stage | Module | Key Responsibility |
|-------|--------|--------------------|
| **IF** | riscv_fetch_stage.sv | PC logic, instruction fetch |
| **ID** | riscv_decode_stage.sv | Decoding, register reads, immediates |
| **EX** | riscv_execute_stage.sv | ALU compute, branch targets |
| **MEM** | riscv_memory_stage.sv | Data memory, CSR reads/writes |
| **WB** | (inline in top) | Result mux -> register file |

> **Full RV32I ISA support:** 37 instructions -- arithmetic, load/store, branches, jumps, system

---

---

# PART II -- Privileged ISA and CSRs

---

---

# Slide 3 -- Why a Privileged ISA?

## The Problem with a Flat Execution Model

Without privilege levels, any software can:
- Modify interrupt vectors -> break trap handling
- Disable machine interrupts -> brick the CPU
- Access all memory -> no isolation between kernel and application

## The Solution: Hardware-Enforced Privilege

The RISC-V Privileged ISA introduces:

| Feature | Purpose |
|---------|---------|
| **Privilege Levels** | Separate machine code from application code |
| **CSR Registers** | Hardware-controlled system configuration |
| **Trap Mechanism** | Deterministic routing to handler on faults/interrupts |
| **MRET / SRET** | Safe privilege restoration on return from trap |

> The CSR unit is the hardware "operating system interface" --
> it is what makes software trusted.

---

# Slide 4 -- Privilege Levels

## Two Active Privilege Modes

```
  +------------------------------+
  |  Machine Mode  (M-mode)      |  <-- Most trusted
  |  priv_mode_q = 2'b11         |      Full hardware access
  |  Boot state, trap handlers   |      Access to ALL CSRs
  +------------------------------+
  |  Supervisor Mode (S-mode)    |  <-- Partially trusted
  |  priv_mode_q = 2'b01         |      Kernel / OS level
  |  Access to S-mode CSRs only  |      Can delegate to U-mode
  +------------------------------+
  |  (User Mode -- U-mode)       |  <-- Untrusted / Applications
  |  priv_mode_q = 2'b00         |      (Return state representation only)
  +------------------------------+
```

### Hardware Enforcement (single combinational line in riscv_csr_unit.sv):

```systemverilog
assign priv_violation = (priv_mode_q < i_csr_unit_csr_addr[9:8]);
```

- **csr_addr[9:8]** encodes the **minimum privilege** required to access each CSR
- If current mode is lower than required -> priv_violation = 1 -> **Illegal Instruction trap**

> S-mode code reading mstatus (addr 0x300, bits [9:8] = 11) while in S-mode? **Trapped.**

---

# Slide 5 -- CSR Unit Block Diagram

## riscv_csr_unit.sv -- Positioned in the MEM Stage

```
               +---------------------------------------------------+
               |                    CSR Unit                       |
               |                                                   |
  ID  -------->| illegal_instr_id              o_csr_unit_mux1    |----> IF (PC Override)
  EX  -------->| instr_addr_misaligned  o_csr_unit_irq_handler   |----> IF (Handler Addr)
  EX  -------->| csr_addr / csr_op / src  o_csr_unit_rtrn_addr  |----> IF (Return Addr)
  MEM -------->| lw_access_fault / sw     o_csr_unit_rdata       |----> WB (CSR Read)
  MEM -------->| ecall / ebreak / mret    o_csr_unit_*_flush     |----> ID/EX/MEM Flush
               |                                                   |
               |  REGISTERS: mstatus, mtvec, mepc, mcause, mtval  |
               |             stvec, sepc, scause, stval, mie...   |
               |  COUNTERS:  mcycle[63:0], minstret[63:0]         |
               +---------------------------------------------------+
```

**The CSR unit has two jobs:**
1. **Storage** -- Maintain the architectural CSR register values
2. **Control** -- Generate PC redirects and pipeline flushes on traps

---

---

# PART III -- Machine-Level CSRs

---

---

# Slide 6 -- M-Mode CSR Address Space

## Complete Machine-Level Register Map

| Address | Register | R/W | Function |
|---------|----------|-----|----------|
| 0x300 | mstatus  | R/W | Global interrupt enable, privilege stacks |
| 0x301 | misa     | R-O | ISA report: 32'h40001105 (RV32IMA) |
| 0x302 | medeleg  | R/W | Exception delegation to S-mode |
| 0x303 | mideleg  | R/W | Interrupt delegation to S-mode |
| 0x304 | mie      | R/W | Individual interrupt enable gates |
| 0x305 | mtvec    | R/W | Trap handler base address + mode |
| 0x340 | mscratch | R/W | Context save during trap entry |
| 0x341 | mepc     | R/W | PC of the faulting instruction |
| 0x342 | mcause   | R/W | Trap cause code (IRQ bit + code) |
| 0x343 | mtval    | R/W | Bad address or faulting opcode |
| 0x344 | mip      | R-O | Interrupt pending status |
| 0xB00 | mcycle   | R/W | Cycle counter low 32-bits |
| 0xB80 | mcycleh  | R/W | Cycle counter high 32-bits |
| 0xB02 | minstret | R/W | Retired instructions low 32-bits |
| 0xF14 | mhartid  | R-O | Hardware thread ID (hardwired to 0) |

---

# Slide 7 -- mstatus: The Control Register

## Machine Status Register Bitfield

```
 31          13  12  11  10   9   8   7   6   5   4   3   2   1   0
+-----------+-------+---+---+----+---+----+---+----+---+---+----+
|  Reserved |  MPP  | 0 |SPP|MPIE| 0 |SPIE| 0 |MIE | 0 |SIE| 0  |
+-----------+-------+---+---+----+---+----+---+----+---+---+----+
```

| Field | Bits | Description |
|-------|------|-------------|
| **MIE**  | [3]    | Machine Global Interrupt Enable. Auto-cleared on trap entry. |
| **SIE**  | [1]    | Supervisor Global Interrupt Enable. |
| **MPIE** | [7]    | Previous MIE value, saved when entering M-mode trap. |
| **SPIE** | [5]    | Previous SIE value, saved when entering S-mode trap. |
| **MPP**  | [12:11] | Previous privilege mode before M-mode trap (11=M, 01=S, 00=U). |
| **SPP**  | [8]    | Previous privilege mode before S-mode trap (1=S, 0=U). |

### Hardware Trap Entry (automatic, single cycle):
```
mepc    <- PC of faulting instruction
mcause  <- exception / interrupt cause code
MIE     <- 0        (interrupts disabled while in handler)
MPIE    <- MIE      (save previous interrupt enable state)
MPP     <- priv_mode_q  (save previous privilege level)
priv_mode_q <- 2b11 (switch to Machine Mode)
PC      <- mtvec    (redirect fetch to handler address)
Pipeline FLUSHED    (clear in-flight instructions)
```

---

# Slide 8 -- mtvec and mie / mip Registers

## Machine Trap Vector Base Address Register

```
 31                                            2   1   0
+-----------------------------------------------+-------+
|               BASE [31:2]                     | MODE  |
+-----------------------------------------------+-------+
```

| MODE | Value | Behavior |
|------|-------|----------|
| **Direct**   | 2'b00 | ALL traps jump to BASE address |
| **Vectored** | 2'b01 | Exceptions to BASE, Interrupts to BASE + (cause x 4) |

### Interrupt Enable / Pending Registers (mie / mip):

```
 Bit:    11    10    9     8     7     6     5     4     0
       +----+-----+----+-----+----+-----+----+-----+------+
       |MEIP|  0  |SEIP|  0  |MTIP|  0  |STIP|  0  |  0   |
       +----+-----+----+-----+----+-----+----+-----+------+
         M-Ext    S-Ext    M-Timer   S-Timer
```

- **MTIP**: Set automatically when mcycle >= mtimecmp (hardware timer compare)
- **MEIP**: Driven by external interrupt input pin `i_csr_unit_mexternal`
- Each bit in **mie** enables the corresponding source in **mip**

---

---

# PART IV -- Supervisor-Level CSRs

---

---

# Slide 9 -- S-Mode CSR Address Space

## Supervisor Register Map

| Address | Register | Mapping | Function |
|---------|----------|---------|----------|
| 0x100 | sstatus  | Virtual window into mstatus_q | Supervisor Status |
| 0x104 | sie      | mie_q AND mideleg_q | Supervisor Interrupt Enable |
| 0x105 | stvec    | Dedicated stvec_q register | Supervisor Trap Vector |
| 0x140 | sscratch | Dedicated sscratch_q register | Supervisor Scratch |
| 0x141 | sepc     | Dedicated sepc_q (word-aligned) | Supervisor Exception PC |
| 0x142 | scause   | Dedicated scause_q register | Supervisor Trap Cause |
| 0x143 | stval    | Dedicated stval_q register | Supervisor Trap Value |
| 0x144 | sip      | mip_val AND mideleg_q | Supervisor Interrupt Pending |
| 0x180 | satp     | Hardwired to 32'h0 | Address Translation (no MMU) |

---

# Slide 10 -- Virtualized Register Mapping

## sstatus is NOT a Separate Physical Register

To avoid status inconsistencies, sstatus is a **windowed view** into mstatus:

### Read Path (combinational assignment):
```systemverilog
assign sstatus = {
    23'b0,
    mstatus_q[8],   // SPP  -- Supervisor Previous Privilege
    2'b0,
    mstatus_q[5],   // SPIE -- Supervisor Previous Interrupt Enable
    3'b0,
    mstatus_q[1],   // SIE  -- Supervisor Interrupt Enable
    1'b0
};
```

### Write Path (only S-mode delegated fields are touched):
```systemverilog
12'h100: begin  // sstatus write path
    mstatus_q[8] <= csr_wdata[8];   // SPP
    mstatus_q[5] <= csr_wdata[5];   // SPIE
    mstatus_q[1] <= csr_wdata[1];   // SIE
end
```

### sie and sip -- delegation-filtered views of mie and mip:
```systemverilog
12'h104: o_csr_unit_rdata = mie_q   & mideleg_q;   // sie read
12'h144: o_csr_unit_rdata = mip_val & mideleg_q;   // sip read
```

> S-mode can only see and configure interrupts that M-mode has **explicitly delegated**
> via the mideleg register.

---

---

# PART V -- CSR Instructions

---

---

# Slide 11 -- Zicsr Instruction Set

## Six System Instructions (opcode = 7'b1110011 SYSTEM)

| Instruction | funct3 | Source | Write Operation | Read Operation |
|-------------|--------|--------|-----------------|----------------|
| CSRRW  rd, csr, rs1  | 001 | Register | CSR = rs1 | rd = old_CSR |
| CSRRS  rd, csr, rs1  | 010 | Register | CSR = CSR OR rs1 | rd = old_CSR |
| CSRRC  rd, csr, rs1  | 011 | Register | CSR = CSR AND NOT rs1 | rd = old_CSR |
| CSRRWI rd, csr, uimm | 101 | 5-bit Imm | CSR = uimm | rd = old_CSR |
| CSRRSI rd, csr, uimm | 110 | 5-bit Imm | CSR = CSR OR uimm | rd = old_CSR |
| CSRRCI rd, csr, uimm | 111 | 5-bit Imm | CSR = CSR AND NOT uimm | rd = old_CSR |

### Write Data Generation Logic (hardware):
```systemverilog
always_comb begin
    case (i_csr_unit_op)
        2'b01: csr_wdata = i_csr_unit_src;                        // RW: direct write
        2'b10: csr_wdata = o_csr_unit_rdata | i_csr_unit_src;    // RS: set bits
        2'b11: csr_wdata = o_csr_unit_rdata & (~i_csr_unit_src); // RC: clear bits
    endcase
end
```

### Write Suppression Rules:
- CSRRS/CSRRC with **rs1 = x0** -> **read-only** (no write side-effect triggered)
- CSRRSI/CSRRCI with **uimm = 0** -> **read-only**
- CSRRW with **rd = x0** -> write occurs but CSR read side-effect is suppressed

---

# Slide 12 -- Pipeline Walkthrough: csrrw x2, mscratch, x1

## Tracing Machine Word 32'h34009173 Through All Five Stages

```
Cycle 1 | FETCH
        |  PCF = 0x00000008
        |  IMEM outputs: 32'h34009173
        |  Pipeline latches: instrD <= 32'h34009173, PCD <= 0x8

Cycle 2 | DECODE
        |  Parsed: opcode=1110011 (SYSTEM), funct3=001 (CSRRW)
        |  Fields: rd=x2, rs1=x1, csr_addr=0x340 (mscratch)
        |  RegFile reads x1 -> RD1 = 0x00000055
        |  Control: RegWriteD=1, ResultSrcD=2'b11, csr_wenD=1, csr_opD=01

Cycle 3 | EXECUTE
        |  ALU is bypassed for all CSR operations
        |  Pipeline latches: csr_srcM <= RD1E = 0x00000055

Cycle 4 | MEMORY  (CSR unit is instantiated here)
        |  CSR unit decodes address 0x340 -> mscratch_q register
        |  READ:  o_csr_unit_rdata = 0x00000000  (old mscratch value)
        |  WRITE: mscratch_q will be updated to 0x00000055 on next posedge
        |  Pipeline latches: CSRRDataW <= 0x00000000

Cycle 5 | WRITEBACK
        |  ResultSrcW = 2'b11 -> selects CSRRDataW input
        |  Register file: x2 <= 0x00000000  (old mscratch committed)
```

> **Result:** x2 receives the old mscratch value. mscratch receives x1's value.
> Atomic register swap completed in exactly 5 pipeline cycles.

---

---

# PART VI -- Trap Handling

---

---

# Slide 13 -- Exception and Interrupt Cause Table

## Implemented Traps in riscv_csr_unit.sv

| IRQ bit | Code | Cause Name | Activation Condition |
|---------|------|------------|----------------------|
| 0 | 0  | Instruction Address Misaligned | Branch/jump target not 4-byte aligned |
| 0 | 2  | **Illegal Instruction** | Bad opcode OR privilege violation |
| 0 | 3  | Breakpoint | ebreak instruction executed |
| 0 | 5  | Load Access Fault | Address >= 16384 or misaligned load |
| 0 | 7  | Store Access Fault | Address >= 16384 or misaligned store |
| 0 | 9  | E-Call from S-mode | ecall executing in S-mode |
| 0 | 11 | **E-Call from M-mode** | ecall executing in M-mode |
| 1 | 5  | Supervisor Timer Interrupt | mtime >= stimecmp AND SIE enabled |
| 1 | 7  | **Machine Timer Interrupt** | mtime >= mtimecmp AND MIE enabled |
| 1 | 9  | Supervisor External Interrupt | External pin AND delegated to S-mode |
| 1 | 11 | Machine External Interrupt | i_csr_unit_mexternal AND mie[11] |

### Priority Ordering (highest to lowest):
```
1st -- Illegal Instruction / CSR Privilege Violations
2nd -- Instruction Address Misalignment
3rd -- ECALL / EBREAK
4th -- Load / Store Access Faults
5th -- Asynchronous Interrupts (only when MIE or SIE = 1)
```

---

# Slide 14 -- Trap Entry: Hardware Sequence

## What Happens in ONE Clock Cycle When take_trap = 1

```
STEP 1 -- CHECK DELEGATION
    if (medeleg[cause] AND priv_mode_q != M_MODE):
        route to S-mode handler (use stvec, update sepc/scause/stval)
    else:
        route to M-mode handler (use mtvec, update mepc/mcause/mtval)

STEP 2 -- SAVE PROGRAM STATE
    [M-mode path]             [S-mode path]
    mepc   <- PCM              sepc   <- PCM
    mcause <- cause code       scause <- cause code
    mtval  <- bad address      stval  <- bad address

STEP 3 -- UPDATE STATUS STACK
    [M-mode path]                     [S-mode path]
    mstatus[MPP]  <- priv_mode_q       mstatus[SPP]  <- priv_mode_q[0]
    mstatus[MPIE] <- mstatus[MIE]      mstatus[SPIE] <- mstatus[SIE]
    mstatus[MIE]  <- 0                 mstatus[SIE]  <- 0
    priv_mode_q   <- 2'b11             priv_mode_q   <- 2'b01

STEP 4 -- REDIRECT PROGRAM COUNTER
    o_csr_unit_mux1      = 1   (assert PC override)
    o_csr_unit_addr_ctrl = 1   (select handler address output)
    PC <- mtvec (or stvec) with MODE bit applied

STEP 5 -- FLUSH PIPELINE
    id_flush = exe_flush = mem_flush = 1
    Kills all in-flight instructions to prevent register corruption
```

---

# Slide 15 -- Trap Return: MRET and SRET

## Restoring State After the Trap Handler Completes

### MRET -- Return from Machine-Mode Handler:
```
priv_mode_q       <- mstatus[MPP]      restore previous privilege level
mstatus[MIE]      <- mstatus[MPIE]     restore previous interrupt enable
mstatus[MPIE]     <- 1                 reset MPIE to default 1
mstatus[MPP]      <- 2'b00             clear MPP field
PC                <- mepc              resume from saved return address
pipeline          <- FLUSH             clear speculative instructions
```

### SRET -- Return from Supervisor-Mode Handler:
```
priv_mode_q       <- {1'b0, mstatus[SPP]}   restore S or U mode
mstatus[SIE]      <- mstatus[SPIE]           restore S-mode interrupt enable
mstatus[SPIE]     <- 1                       reset SPIE to 1
mstatus[SPP]      <- 0                       clear SPP field
PC                <- sepc                    resume from saved S-mode address
pipeline          <- FLUSH                   clear speculative instructions
```

### The Complete Trap Lifecycle:
```
Normal Execution
      |
      v  (exception fires or interrupt arrives)
  TRAP ENTRY: mepc/sepc saved, PC -> handler, MIE=0, pipeline flushed
      |
      v  (handler runs, reads mcause, uses mscratch, resolves fault)
  MRET / SRET: privilege restored, MIE restored, PC <- mepc/sepc
      |
      v
Normal Execution resumes seamlessly
```

---

---

# PART VII -- Software OS

---

---

# Slide 16 -- Software Stack Architecture

## Four Layers, One System

```
Layer 4 +---------------------------------------------------------+
        |               SNAKE GAME (main.c)                       |
        |  Game logic - Collision detection - Board rendering      |
        |  Input: MMIO UART at 0x3FF0, food placement algorithm   |
        +---------------------------+-----------------------------+
                                    | calls
Layer 3 +---------------------------v-----------------------------+
        |              NANO-OS KERNEL (main.c)                    |
        |   mtvec/stvec init - sys_putc/sys_getc via MMIO         |
        |   Trap dispatch - M-mode and S-mode handler stubs       |
        +---------------------------+-----------------------------+
                                    | delegates to
Layer 2 +---------------------------v-----------------------------+
        |            BOOTSTRAP LOADER (start.s)                   |
        |  Reset entry -> SP setup -> CSR init -> call main       |
        |  m_trap_handler / s_trap_handler assembly routines      |
        +---------------------------+-----------------------------+
                                    | runs on
Layer 1 +---------------------------v-----------------------------+
        |           HARDWARE PLATFORM (RTL)                       |
        |  RV32I Pipeline - CSR Unit - IMEM - DMEM - UART MMIO   |
        +---------------------------------------------------------+
```

**Design Philosophy:** No Linux. No libc. No operating system.
Everything built from scratch on raw hardware.

---

# Slide 17 -- Bootstrap Loader: start.s

## The Very First Code That Executes at Reset

```asm
_start:
    li   sp, 0x00000F00    # Set stack pointer to top of RAM (0xF00)
    call main              # Jump into the C kernel
loop:
    j    loop              # Spin forever if main ever returns
```

### M-Mode Trap Handler Assembly (registered via csrw mtvec):

```asm
.align 4
m_trap_handler:
    mv   t5, a0              # Save a0 to scratch register t5
    csrr a0, mcause          # Read the machine cause register
    li   t6, 11
    beq  a0, t6, m_syscall_handler  # cause == 11? -> M-mode ECALL dispatch
    srli a0, a0, 31          # Shift out IRQ bit [31]
    bnez a0, m_int_handler   # If IRQ bit set -> interrupt, handle separately

    # Synchronous exception: advance mepc past the faulting instruction
    csrr a0, mepc
    lhu  t6, 0(a0)           # Read 16-bit instruction word at mepc
    andi t6, t6, 3           # Isolate lowest 2 bits
    li   a7, 3
    beq  t6, a7, m_32bit     # Bits == 11 -> 32-bit instruction, skip 4
    addi a0, a0, 2           # Else: compressed (16-bit), skip 2
    j    m_set_epc
m_32bit:
    addi a0, a0, 4
m_set_epc:
    csrw mepc, a0            # Write updated return address
    mret                     # Return from trap
```

---

# Slide 18 -- UART Syscall Dispatch

## System Calls Routed Through M-Mode ECALL Handler

```asm
m_syscall_handler:
    li   t6, 1
    beq  a7, t6, m_sys_putc    # a7 == 1 -> sys_putc: write one character
    li   t6, 2
    beq  a7, t6, m_sys_getc    # a7 == 2 -> sys_getc: read one character
    li   t5, 0
    j    m_sys_done             # Unknown syscall: return 0

m_sys_putc:
    li   t6, 0x00003FF0        # Load MMIO UART register address
    sb   t5, 0(t6)             # Store byte -> transmit character to console
    li   t5, 0
    j    m_sys_done

m_sys_getc:
    li   t6, 0x00003FF0        # Load MMIO UART register address
    lbu  t5, 0(t6)             # Load byte -> receive last keystroke

m_sys_done:
    csrr a0, mepc
    addi a0, a0, 4             # Advance past the ecall instruction (4 bytes)
    csrw mepc, a0
    mv   a0, t5                # Return value in a0
    mret
```

> **Memory-Mapped I/O:** The UART at 0x3FF0 is a single byte register.
> Writing transmits a character. Reading returns the last key pressed.
> Both operations map to the same address -- multiplexed by access direction.

---

# Slide 19 -- Nano-OS Kernel: Key Subsystems

## What main.c Provides to the Application Layer

### 1. Hardware CSR Initialization
```c
int main(void) {
    // Register trap handler addresses with hardware CSR unit
    asm volatile("csrw mtvec, %0" :: "r"((unsigned int)m_trap_handler & ~0x3u));
    asm volatile("csrw stvec, %0" :: "r"((unsigned int)s_trap_handler & ~0x3u));
    screen_clear();
    game_init();
    // ... main game loop
}
```

### 2. Direct MMIO I/O Drivers (zero syscall overhead)
```c
#define UART_ADDR ((volatile unsigned char *)0x00003FF0)

static void sys_putc(unsigned char ch) { *UART_ADDR = ch; }
static unsigned char sys_getc(void)    { return *UART_ADDR; }
```

### 3. Console Rendering via ANSI Escape Sequences
```c
static void screen_clear(void) {
    sys_putc(27); sys_putc('['); sys_putc('2'); sys_putc('J'); // ESC[2J clear screen
    sys_putc(27); sys_putc('['); sys_putc('H');                // ESC[H  cursor to home
}
static void screen_home(void) {
    sys_putc(27); sys_putc('['); sys_putc('H');  // ESC[H cursor top-left (no flicker)
}
```

### 4. Runtime Platform Detection
```c
#define PLATFORM_ADDR ((volatile unsigned int *)0x00003FFC)
if (*PLATFORM_ADDR == 0x454D554C) {  // ASCII "EMUL" magic constant
    limit = 200000u;                  // Web emulator: longer delay loop needed
}
```

---

---

# PART VIII -- The Snake Game

---

---

# Slide 20 -- Game Architecture

## A Real-Time Game Running on Bare-Metal RTL Hardware

```
+-----------------------------------------+
|           GAME DATA STRUCTURES          |
|                                         |
|  snake_x[64], snake_y[64] -- body pos   |
|  snake_len                -- body size  |
|  dir   (0=UP 1=DN 2=LT 3=RT)           |
|  food_x, food_y           -- food pos   |
|  tick_count               -- frame cnt  |
|  game_over                -- dead flag  |
+--------------+--------------------------+
               |
       +-------v------------------------------+
       |           MAIN GAME LOOP             |
       |  handle_input()  <- reads UART WASD  |
       |  game_step()     <- moves, collides  |
       |  clock_task()    <- increments tick  |
       |  render_board()  <- draws via UART   |
       |  delay()         <- speed governor   |
       +--------------------------------------+
```

**Board:** 20 x 10 cells  |  **Head:** @  |  **Body:** o  |  **Food:** *  |  **Border:** #

---

# Slide 21 -- Game Logic

## Core Functions in main.c

### Input Handling (reverse-direction prevention included):
```c
static void handle_input(void) {
    unsigned char ch = sys_getc();
    if (ch >= 'a' && ch <= 'z') ch = ch - 'a' + 'A';  // normalize to uppercase

    if (ch == 'W' && dir != 1) dir = 0;  // UP    (blocked if moving DOWN)
    if (ch == 'S' && dir != 0) dir = 1;  // DOWN  (blocked if moving UP)
    if (ch == 'A' && dir != 3) dir = 2;  // LEFT  (blocked if moving RIGHT)
    if (ch == 'D' && dir != 2) dir = 3;  // RIGHT (blocked if moving LEFT)
    if (ch == 'Q') game_init();           // Q key -> reset everything
}
```

### Collision Detection and Movement:
```c
static void game_step(void) {
    if (game_over) return;                               // frozen when dead

    // Wall collision
    if (dir == 0 && new_y == 0)       { game_over = 1; return; }  // top wall
    if (dir == 1 && new_y >= BOARD_H) { game_over = 1; return; }  // bottom wall
    if (dir == 2 && new_x == 0)       { game_over = 1; return; }  // left wall
    if (dir == 3 && new_x >= BOARD_W) { game_over = 1; return; }  // right wall

    // Self-collision
    for (i = 0; i < snake_len; i++)
        if (snake_x[i] == new_x && snake_y[i] == new_y) { game_over = 1; return; }

    // Shift body then place new head
    for (i = snake_len-1; i > 0; i--) { snake_x[i]=snake_x[i-1]; snake_y[i]=snake_y[i-1]; }
    snake_x[0] = new_x; snake_y[0] = new_y;
}
```

---

# Slide 22 -- Game Rendering

## Drawing the Board Entirely Through UART Byte Writes

```
RISC-V Snake OS
WASD move, Q reset
T=14 L=04                   <- tick count (hex) and snake length (hex)
######################      <- top border row
#                    #
#                    #
#              *     #      <- food (*) at column 14, row 3
#              @o    #      <- head (@) followed by body (o)
#              oo    #
#                    #
#                    #
#                    #
#                    #
######################      <- bottom border row
```

### Rendering Implementation Details:
- `screen_home()` moves cursor to top-left without clearing -> **no flicker**
- Print title, score header, then scan each row from y=0 to y=BOARD_H-1
- For each cell: check `cell_has_snake(x, y)` -> print @, o, *, or space
- Borders: loop printing # characters

### Game Over Behavior:
```c
// Main loop structure -- rendering STOPS when game_over is set
while (1) {
    handle_input();
    if (!game_over) {
        game_step();        // update game state
        clock_task();       // increment tick_count
        render_board();     // redraw board
    }
    delay();
}
// Game over board is rendered exactly once then frozen.
// "GAME OVER - Q reset" line appended to the frozen last frame.
```

---

# Slide 23 -- Food Placement Algorithm

## Pseudo-Random Placement Without a Hardware RNG

On bare metal without a random number generator, food uses
a **deterministic prime-stepping algorithm**:

```c
static void place_food(void) {
    unsigned char tries = 0, ok = 0;

    while (!ok && tries < 40) {
        ok = 1;
        food_x += 7;                              // step X by prime 7
        if (food_x >= BOARD_W) food_x -= BOARD_W;  // wrap around 20-wide board
        food_y += 3;                              // step Y by prime 3
        if (food_y >= BOARD_H) food_y -= BOARD_H;  // wrap around 10-tall board

        // Reject position if it overlaps any snake segment
        for (i = 0; i < snake_len; i++)
            if (snake_x[i] == food_x && snake_y[i] == food_y) ok = 0;

        tries++;
    }
}
```

**Why prime steps 7 and 3?**
- 7 has no common factor with BOARD_W=20 -> visits ALL 20 columns before repeating
- 3 has no common factor with BOARD_H=10 -> visits ALL 10 rows before repeating
- Result: food cycles through all 200 possible cells before looping
- Appears random to the player while needing NO multiply, divide, or modulo

---

---

# PART IX -- Simulation and Testing

---

---

# Slide 24 -- Running the System

## Two Ways to Experience the Game

### Method A: Web Emulator (Recommended -- Real-Time Speed ~3.5 MHz)
```
Step 1  Build firmware:
        cd sw
        .\build.bat

Step 2  Open the emulator:
        Open sw/snake.html in any web browser

Step 3  Load the binary:
        Click [LOAD FIRMWARE.HEX] -> navigate to sw/build/firmware.hex

Step 4  Play the game:
        Use WASD keys (or arrow keys) to control the snake
        Press R to restart
```

### Method B: RTL Simulation (Cycle-Accurate Hardware Gate Simulation)
```
Terminal 1 -- Keyboard feeder (keep this window focused while playing):
    cd sw
    python play_game.py

Terminal 2 -- Hardware simulation (renders board in console):
    .\run_xsim_snake.bat
```

### Build and Run Command Reference:

| Target | Command | Output |
|--------|---------|--------|
| Snake firmware | cd sw && .\build.bat | sw/build/firmware.hex |
| ISA test suite | cd sw && .\build_test.bat | sw/build/firmware.hex (test) |
| Snake RTL sim | .\run_xsim_snake.bat | Live console game board |
| ISA test RTL sim | .\run_xsim.bat | Register dump + PASS/FAIL verdict |

---

# Slide 25 -- ISA Integration Test

## Custom ALU Verification Suite (riscv_test.s)

```asm
_start:
    li  x1,  10              ; x1 = 10
    li  x2,  -5              ; x2 = -5  (0xFFFFFFFB)

    add x3, x1, x2           ; x3 = 10 + (-5)  =   5    (ADD check)
    sub x4, x1, x2           ; x4 = 10 - (-5)  =  15    (SUB check)
    and x5, x1, x2           ; x5 = 10 AND(-5) =  10    (AND check)
    or  x6, x1, x2           ; x6 = 10 OR (-5) =  -5    (OR  check)
    sll x7, x1, x3           ; x7 = 10 << 5    = 320    (SLL check)
    sra x8, x2, x3           ; x8 = (-5) >> 5  =  -1    (SRA arithmetic shift)

check_add:   li x30, 5;   bne x3, x30, fail   ; 5 == 5?   pass or fail
check_sub:   li x30, 15;  bne x4, x30, fail   ; 15 == 15? pass or fail
check_and:   li x30, 10;  bne x5, x30, fail   ; 10 == 10? pass or fail
check_or:    li x30, -5;  bne x6, x30, fail   ; -5 == -5? pass or fail
check_sll:   li x30, 320; bne x7, x30, fail   ; 320==320? pass or fail
check_sra:   li x30, -1;  bne x8, x30, fail   ; -1 == -1? pass or fail

success:
    li x31, 0xFEEDDEED       ; Magic success sentinel value
    j  done                  ; Loop forever -- simulation reads registers

fail:
    li x30, 0xDEAD0000
    or x31, x31, x30         ; x31 = 0xDEAD00NN  (NN = failing check number)
done:
    j  done
```

---

# Slide 26 -- Testbench Expected Values

## riscv_top_tb.sv Verification Register Dump

```
================ TEST RESULTS =================
x01 = 0x0000000a  (Expected: 0x0000000a)   -- x1  = 10 (input operand)
x02 = 0xfffffffb  (Expected: 0xfffffffb)   -- x2  = -5 (input operand)
x03 = 0x00000005  (Expected: 0x00000005)   -- x3  = ADD result  (5)
x04 = 0x0000000f  (Expected: 0x0000000f)   -- x4  = SUB result  (15)
x05 = 0x0000000a  (Expected: 0x0000000a)   -- x5  = AND result  (10)
x06 = 0xfffffffb  (Expected: 0xfffffffb)   -- x6  = OR  result  (-5)
x07 = 0x00000140  (Expected: 0x00000140)   -- x7  = SLL result  (320 = 0x140)
x08 = 0xffffffff  (Expected: 0xffffffff)   -- x8  = SRA result  (-1)
...
x30 = 0xffffffff  (Expected: 0xffffffff)   -- x30 = last check value
x31 = 0xfeeddeed  (Expected: 0xfeeddeed)   -- x31 = SUCCESS SENTINEL
===============================================

>>> SUCCESS: ALL RV32I PROCESSOR INSTRUCTIONS PASSED! <<<
```

### Testbench Mechanism:
1. Clock runs for MAX_SIM_CYCLES cycles (parameterized)
2. All 32 register values dumped with expected value labels
3. x31 checked against 32'hFEEDDEED -> prints SUCCESS or FAIL message
4. Failure shows x31 = 0xDEAD00NN to identify the failing check

---

# Slide 27 -- Hardware Bug: Tagged BTB Fix

## Branch Target Buffer -- A Critical Hardware Bug Found and Fixed

### The Original Bug (Tagless BTB):

```systemverilog
// BEFORE: Index-only lookup -- no tag validation at all
// Any two instructions mapping to the same index collide silently
btb_targets[pc[9:2]] <= target;    // store target by index
btb_valid[pc[9:2]]   <= 1'b1;      // mark as valid
// On lookup: if valid[index] -> predict taken to targets[index]
// PROBLEM: address 0x4B0 and 0x2B0 both map to index 0x2C !!!
```

**Symptom in Snake game:** Address 0x4B0 (print space routine) writes index 0x2C
with target 0x3F8. Address 0x2B0 (game-over branch) reads the same index
and jumps to 0x3F8 (wrong target) -> pipeline enters endless reboot loop.

### The Fix (Tagged BTB):

```systemverilog
// AFTER: Store upper PC bits as tag, validate on every lookup
logic [21:0] btb_tags  [0:255];   // tag = PC[31:10], 22 upper bits
logic        btb_valid [0:255];   // valid bit per entry

// Lookup: only predict if tag matches exactly
assign btb_hit = btb_valid[pc[9:2]] && (btb_tags[pc[9:2]] == pc[31:10]);

// Update: store tag alongside the branch target
btb_tags [pc[9:2]] <= pc[31:10];  // save tag
btb_valid[pc[9:2]] <= 1'b1;       // mark entry as valid
```

> **Impact:** Tag validation completely eliminates branch prediction aliasing.
> The Snake game now executes correctly: game-over is detected cleanly,
> the board freezes on the last frame, and Q resets cleanly.

---

---

# PART X -- Summary

---

---

# Slide 28 -- What We Built

## From Gates to Games -- Complete Achievement Summary

| Layer | What Was Implemented | Technology Used |
|-------|---------------------|----------------|
| **Hardware CPU** | 5-stage RV32I pipeline, forwarding, hazard detection | SystemVerilog |
| **Branch Prediction** | 2-bit saturating BHT counter + Tagged BTB (256 entries) | SystemVerilog |
| **Privileged ISA** | M-mode + S-mode privilege, 26 CSR registers | SystemVerilog |
| **Trap Handling** | 11 trap causes, exceptions + interrupts, MRET/SRET | SystemVerilog |
| **Bootstrap** | Reset vector, stack pointer, trap vector setup | RISC-V Assembly |
| **Nano-OS Kernel** | Trap dispatch, MMIO UART drivers, syscall interface | C (bare metal) |
| **Snake Game** | Real-time board game, collision detection, scoring | C (bare metal) |
| **ISA Test Suite** | ALU integration verification, register assertions | SystemVerilog + ASM |
| **Web Emulator** | JavaScript RV32I ISA emulator with live register UI | HTML / JavaScript |

---

# Slide 29 -- Key Technical Metrics

## Numbers and Measurements

```
ISA Coverage        37 RV32I Base Integer Instructions fully implemented
Pipeline Depth       5 stages: IF -> ID -> EX -> MEM -> WB
CSR Registers       26 implemented (M-mode + S-mode combined)
Trap Causes         11 total (7 synchronous exceptions + 4 asynchronous)
Cycle Counters      64-bit mcycle + 64-bit minstret performance counters
BTB                256 entries, 22-bit tag, 2-bit saturation counter per entry
Board Game          20 x 10 grid, up to 64-segment snake body
UART MMIO           0x3FF0 -- single byte address, TX/RX direction multiplexed
Firmware Size       approx 460 instruction words compiled (firmware.hex)
Memory Layout       Harvard architecture: IMEM ROM + DMEM 16KB data RAM
```

---

# Slide 30 -- Thank You

## RISC-V MicroKernel Architecture

```
          +--------------------------------------------+
          |             RISC-V Snake OS                |
          |        Running on Real RTL Hardware        |
          |                                            |
          |   ######################                   |
          |   #                    #                   |
          |   #        *           #   <- food (*)     |
          |   #       @oo          #   <- head (@)     |
          |   #                    #   <- body (o)     |
          |   ######################                   |
          |                                            |
          |   T=1F L=05  -- LIVE CYCLE-ACCURATE SIM   |
          +--------------------------------------------+
```

### Key Source Files:
```
rtl/RV32I/riscv_csr_unit.sv       <- Privileged ISA hardware implementation
rtl/RV32I/riscv_top_pipeline.sv   <- 5-stage pipeline datapath wrapper
sw/src/main.c                     <- Snake Game logic + Nano-OS Kernel
sw/src/start.s                    <- Bootstrap Loader + Trap Handler routines
sw/src/riscv_test.s               <- ISA Integration Test Suite
chapter_6_privileged_isa.md       <- Full Privileged ISA Reference Document
```

> **"From the first logic gate to a playable game --
> every layer designed, verified, and working."**

---

*End of Presentation -- From Gates to Games*
