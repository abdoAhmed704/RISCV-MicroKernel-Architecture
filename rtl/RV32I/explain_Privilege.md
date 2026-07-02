# CSRs & Privilege — From Zero to Your Silicon

> **This document is written specifically for your core.**  
> Every register address, every bit field, every assembly instruction maps directly  
> to your `riscv_csr_unit.sv`.

---

## Table of Contents

1. [The Real Problem CSRs Solve](#1-the-real-problem-csrs-solve)
2. [Why Privilege Levels Exist](#2-why-privilege-levels-exist)
3. [Your Core's Privilege Architecture](#3-your-cores-privilege-architecture)
4. [The CSR Address Space — What You Built](#4-the-csr-address-space--what-you-built)
5. [The 6 CSR Instructions — How Software Talks to Your Core](#5-the-6-csr-instructions--how-software-talks-to-your-core)
6. [The Trap Flow — The Full Hardware Story](#6-the-trap-flow--the-full-hardware-story)
7. [The 5 Scenarios Your Core Must Handle](#7-the-5-scenarios-your-core-must-handle)
8. [Test Assembly Code](#8-test-assembly-code)
9. [Expected Register State After Each Test](#9-expected-register-state-after-each-test)

---

## 1. The Real Problem CSRs Solve

Imagine your CPU is just the RV32I pipeline you already built — no CSRs at all.  
Ask yourself: **how does software know anything about the hardware it's running on?**

- How does a program measure how long something took? It can't — there's no clock counter.
- What happens when an instruction divides by zero? The CPU either freezes or corrupts state — there's no recovery.
- What if a bug causes a program to start writing to address `0x00000000` (your instruction memory)? Nothing stops it — there's no protection.
- How does an operating system get control back from a user program that's stuck in an infinite loop? It can't — there's no preemption mechanism.

**CSRs are the answer to all of these questions.**

CSR stands for **Control and Status Register**. They are a completely separate bank of 4096 registers (12-bit address) that exist alongside your normal register file (x0–x31). They are not for computing — they are the **control panel of the CPU itself**.

Think of them like this:

```
Your normal register file (x0–x31):
  → "Working memory" for computation
  → What every instruction uses for arithmetic and logic

CSR file (0x000–0xFFF):
  → "Control panel" of the CPU
  → Timers, interrupt enable switches, trap vectors, status flags
  → Hardware writes to them automatically on exceptions
  → Software reads/writes them to configure CPU behavior
```

---

## 2. Why Privilege Levels Exist

Here is the fundamental problem with a flat (no-privilege) CPU:

**Any program can do anything.**

If you run two programs at the same time (or an OS + a user program), there is nothing preventing program A from:
- Overwriting program B's memory
- Disabling interrupts forever
- Changing the trap handler to point to garbage
- Reading another program's secrets out of registers

Privilege levels are the hardware mechanism that enforces a **trust boundary**.

```
        ┌─────────────────────────────────────────────┐
        │              M-MODE (Machine)               │  ← MOST TRUSTED
        │   Your hardware bootloader/runtime lives here│
        │   Can access ALL CSRs                        │
        │   Can do ANYTHING                            │
        ├─────────────────────────────────────────────┤
        │            S-MODE (Supervisor)              │  ← PARTIALLY TRUSTED
        │   An OS kernel would run here               │
        │   Can access S-mode CSRs (sstatus, sepc…)  │
        │   CANNOT touch M-mode CSRs (mstatus…)      │
        ├─────────────────────────────────────────────┤
        │              U-MODE (User)                  │  ← UNTRUSTED
        │   User applications run here               │
        │   Cannot access ANY CSRs directly           │
        │   Must ask OS (via ecall) for services      │
        └─────────────────────────────────────────────┘
```

Your core implements **M-mode and S-mode** (`priv_mode_q` is 2 bits: `2'b11` = M, `2'b01` = S).  
You can see this on **line 36** of `riscv_csr_unit.sv`:
```systemverilog
logic [1:0] priv_mode_q; // 2'b11 = M-mode, 2'b01 = S-mode
```

The privilege check is enforced on **line 168**:
```systemverilog
assign priv_violation = (priv_mode_q < i_csr_unit_csr_addr[9:8]);
```

That `csr_addr[9:8]` encodes the minimum privilege level needed to access that CSR.  
For example, `mstatus` = `0x300` → `addr[9:8] = 2'b11` = requires M-mode.  
If you're in S-mode (`2'b01`) and try to read `mstatus`, you get an **Illegal Instruction exception**.

---

## 3. Your Core's Privilege Architecture

Here is exactly what your `riscv_csr_unit.sv` implements:

```
                   ┌──────────────────────────────────────────┐
                   │            riscv_csr_unit.sv              │
                   │                                           │
  Ext Interrupt ──►│ i_csr_unit_mexternal                     │
  S-Ext Interrupt►│ i_csr_unit_sexternal                     │
                   │                                           │
  PC (WB stage) ──►│ i_csr_unit_pc         ┌──────────────┐  │
  Faulting Addr ──►│ i_csr_unit_fault_addr │  CSR File    │  │
  Instruction ────►│ i_csr_unit_instr      │  mscratch    │  │
                   │                        │  mstatus     │  │
  CSR Op ─────────►│ i_csr_unit_op [1:0]   │  mtvec       │  │
  CSR Src ─────────►│ i_csr_unit_src [31:0] │  mepc        │  │
  CSR Addr ────────►│ i_csr_unit_csr_addr   │  mcause      │  │
  CSR WEn ─────────►│ i_csr_unit_csr_wen    │  mie         │  │
                   │                        │  medeleg     │  │
  Exception flags ►│ i_csr_unit_illegal_*   │  mideleg     │  │
                   │ i_csr_unit_ecall       │  stvec       │  │
                   │ i_csr_unit_ebreak      │  sepc,scause │  │
                   │ i_csr_unit_mret_wb     │  mcycle      │  │
                   │ i_csr_unit_sret        │  minstret    │  │
                   │                        └──────────────┘  │
                   │  ┌─────────────────────────────────────┐ │
                   │  │  Trap Logic                          │ │
                   │  │  - Interrupt detection               │ │
                   │  │  - Exception detection               │ │
                   │  │  - Delegation (M→S routing)          │ │
                   │  │  - Privilege mode update             │ │
                   │  └─────────────────────────────────────┘ │
                   │                                           │
  CSR Read Data ◄──│ o_csr_unit_rdata [31:0]                  │
  IRQ Handler PC ◄─│ o_csr_unit_irq_handler [31:0]            │
  Return Address ◄─│ o_csr_unit_rtrn_addr [31:0]              │
  Trap Active ◄────│ o_csr_unit_addr_ctrl                      │
  Pipeline Flush ◄─│ o_csr_unit_if/id/exe/mem_flush            │
                   └──────────────────────────────────────────┘
```

---

## 4. The CSR Address Space — What You Built

These are the CSRs actually implemented in your `riscv_csr_unit.sv`:

### M-Mode CSRs (require `priv_mode_q == 2'b11`)

| Address | Name | Your Variable | Purpose |
|---------|------|---------------|---------|
| `0x300` | `mstatus` | `mstatus_q` | Global interrupt enable + privilege stack |
| `0x301` | `misa` | `misa` (constant) | Reports ISA: RV32IMAC |
| `0x304` | `mie` | `mie_q` | Interrupt Enable register — which IRQs are enabled |
| `0x305` | `mtvec` | `mtvec_q` | Trap Vector — where to jump on exception/interrupt |
| `0x302` | `medeleg` | `medeleg_q` | Exception Delegation to S-mode |
| `0x303` | `mideleg` | `mideleg_q` | Interrupt Delegation to S-mode |
| `0x340` | `mscratch` | `mscratch_q` | General-purpose scratch register for M-mode |
| `0x341` | `mepc` | `mepc_q` | Machine Exception PC — where trap came from |
| `0x342` | `mcause` | `mcause_q` | Trap cause code |
| `0x343` | `mtval` | `mtval_q` | Trap value (bad address or instruction) |
| `0x344` | `mip` | `mip_val` (computed) | Interrupt Pending — read-only snapshot |
| `0xB00` | `mcycle` | `mcycle_q[31:0]` | Cycle counter (low 32) — increments every clock |
| `0xB80` | `mcycleh` | `mcycle_q[63:32]` | Cycle counter (high 32) |
| `0xB02` | `minstret` | `minstret_q[31:0]` | Instruction retire counter (low 32) |
| `0xB82` | `minstreth` | `minstret_q[63:32]` | Instruction retire counter (high 32) |
| `0xF11` | `mvendorid` | `32'h0` | Vendor ID (non-commercial = 0) |
| `0xF14` | `mhartid` | `32'h0` | Hardware Thread ID (you have one core = 0) |

### S-Mode CSRs (require `priv_mode_q >= 2'b01`)

| Address | Name | Your Variable | Purpose |
|---------|------|---------------|---------|
| `0x100` | `sstatus` | `sstatus` (view into mstatus) | S-mode view of status |
| `0x104` | `sie` | `mie_q & mideleg_q` | S-mode interrupt enables |
| `0x105` | `stvec` | `stvec_q` | S-mode trap vector |
| `0x140` | `sscratch` | `sscratch_q` | S-mode scratch register |
| `0x141` | `sepc` | `sepc_q` | S-mode Exception PC |
| `0x142` | `scause` | `scause_q` | S-mode trap cause |
| `0x143` | `stval` | `stval_q` | S-mode trap value |
| `0x14D` | `stimecmp` | `stimecmp[31:0]` | S-mode timer compare |

### Key `mstatus` Bit Map (your implementation)

```
  Bit 31      12   11   8    7    5    3    1    0
  ┌────── ... ──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐
  │  reserved   │MPP│ │SPP│MPIE│ │SPIE│ │MIE│ │SIE│
  └────── ... ──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘
                 ↑       ↑   ↑      ↑      ↑     ↑
                 M Prev  S   MIE    S      M     S
                 Priv    Prev was   Prev   Int   Int
                 Mode    Priv saved Int    En    En
```

- **MIE (bit 3)**: Master switch for M-mode interrupts. Set=enabled, Clear=disabled.
- **MPIE (bit 7)**: Saved copy of MIE before a trap was taken.
- **MPP (bits 12:11)**: Saved copy of the privilege mode before a trap.
- **SIE, SPIE, SPP**: Same concept but for S-mode traps.

---

## 5. The 6 CSR Instructions — How Software Talks to Your Core

The RISC-V ISA gives you exactly 6 instructions to read and write CSRs.  
All 6 share opcode `1110011` (SYSTEM). The `funct3` field selects which one.

| Instruction | funct3 | Operation | Write? | Read? |
|-------------|--------|-----------|--------|-------|
| `CSRRW rd, csr, rs1` | `001` | rd = old CSR; CSR = rs1 | Always | Only if rd != x0 |
| `CSRRS rd, csr, rs1` | `010` | rd = old CSR; CSR \|= rs1 | Only if rs1 != x0 | Always |
| `CSRRC rd, csr, rs1` | `011` | rd = old CSR; CSR &= ~rs1 | Only if rs1 != x0 | Always |
| `CSRRWI rd, csr, uimm` | `101` | rd = old CSR; CSR = uimm | Always | Only if rd != x0 |
| `CSRRSI rd, csr, uimm` | `110` | rd = old CSR; CSR \|= uimm | Only if uimm != 0 | Always |
| `CSRRCI rd, csr, uimm` | `111` | rd = old CSR; CSR &= ~uimm | Only if uimm != 0 | Always |

**Common assembly aliases you'll see everywhere:**

```asm
csrr   t0, mstatus      # = csrrs t0, mstatus, x0  (read only, no write)
csrw   mtvec, t0        # = csrrw x0, mtvec, t0    (write only, no read)
csrwi  mstatus, 8       # = csrrwi x0, mstatus, 8  (write immediate, no read)
csrsi  mstatus, 8       # = csrrsi x0, mstatus, 8  (set bits immediate)
csrci  mstatus, 8       # = csrrci x0, mstatus, 8  (clear bits immediate)
```

In your hardware (`riscv_csr_unit.sv` lines 299–306), the operation mapping is:
```systemverilog
2'b01: csr_wdata = i_csr_unit_src;              // RW:  full replace
2'b10: csr_wdata = o_csr_unit_rdata | src;      // RS:  set bits
2'b11: csr_wdata = o_csr_unit_rdata & (~src);   // RC:  clear bits
```

---

## 6. The Trap Flow — The Full Hardware Story

A **trap** is the unified term for both **exceptions** (synchronous, caused by an instruction) and **interrupts** (asynchronous, caused by external signals).

### What happens the moment a trap is detected in your core:

```
CYCLE N: Instruction in WB stage raises an exception (or interrupt detected)
         ↓
         riscv_csr_unit detects it:
           take_trap = 1
           final_cause = exception/interrupt code
           trap_target_pc = mtvec (or stvec if delegated to S-mode)

CYCLE N: Outputs go HIGH immediately (combinational):
           o_csr_unit_addr_ctrl = 1  → PC mux selects trap_target_pc
           o_csr_unit_if_flush  = 1  → IF stage flushed
           o_csr_unit_id_flush  = 1  → ID stage flushed
           o_csr_unit_exe_flush = 1  → EX stage flushed
           o_csr_unit_mem_flush = 1  → MEM stage flushed

CYCLE N+1 (posedge clk):
           Registers updated (lines 342–358 of riscv_csr_unit.sv):
             mepc_q   ← PC of the faulting instruction
             mcause_q ← cause code
             mtval_q  ← bad address or instruction encoding
             mstatus[MPP]  ← old privilege mode (saved)
             mstatus[MPIE] ← old MIE (saved)
             mstatus[MIE]  ← 0 (interrupts now OFF — we're in trap handler)
             priv_mode_q   ← 2'b11 (now in M-mode)

CYCLE N+1: Pipeline starts fetching from mtvec
           Trap handler runs in M-mode
```

### Return from trap: `mret` instruction

```
Software does: mret
Hardware does (lines 360–364 of riscv_csr_unit.sv):
  priv_mode_q   ← mstatus[MPP]   (restore old privilege)
  mstatus[MIE]  ← mstatus[MPIE]  (restore interrupt enable)
  mstatus[MPIE] ← 1              (set MPIE = 1)
  mstatus[MPP]  ← 0              (clear MPP = 0)
  PC            ← mepc_q         (return to where we were)
```

### Exception cause codes (your `exc_cause` logic, lines 198–218):

| Code | Cause | Your Hardware Signal |
|------|-------|---------------------|
| 0 | Instruction address misaligned | `i_csr_unit_instr_addr_misaligned` |
| 2 | Illegal instruction | `i_csr_unit_illegal_instr_id/exe` or `csr_illegal` |
| 3 | Breakpoint (EBREAK) | `i_csr_unit_ebreak` |
| 5 | Load access fault | `i_csr_unit_lw_access_fault` |
| 7 | Store access fault | `i_csr_unit_sw_access_fault` |
| 9 | Environment call from S-mode | `i_csr_unit_ecall` (when priv==S) |
| 11 | Environment call from M-mode | `i_csr_unit_ecall` (when priv==M) |

### Interrupt cause codes (bit 31 = 1 means interrupt):

| Code | Cause | Your Hardware Signal |
|------|-------|---------------------|
| 0x80000005 | Supervisor timer interrupt | `mtime >= stimecmp && mie_q[5]` |
| 0x80000007 | Machine timer interrupt | `mtime >= mtimecmp && mie_q[7]` |
| 0x80000009 | Supervisor external interrupt | `i_csr_unit_sexternal && mie_q[9]` |
| 0x8000000B | Machine external interrupt | `i_csr_unit_mexternal && mie_q[11]` |

---

## 7. The 5 Scenarios Your Core Must Handle

These are the key scenarios any privileged core must pass:

| # | Scenario | What It Tests |
|---|----------|---------------|
| 1 | **CSR Read/Write** | Can software read and write CSRs correctly? |
| 2 | **ECALL** | Can a program call into the OS/handler? |
| 3 | **EBREAK** | Can a debugger breakpoint work? |
| 4 | **Illegal Instruction** | Does a bad instruction trap instead of corrupt state? |
| 5 | **MRET** | Can the trap handler return to the correct address? |

The timer interrupt and external interrupt scenarios require hardware signals toggling, so they are best tested in simulation by your testbench, not by software alone.

---

## 8. Test Assembly Code

```asm
# =============================================================================
# CSR & PRIVILEGE TEST SUITE
# For: RISCV-MicroKernel-Architecture (riscv_csr_unit.sv)
# Load base address: 0x00000000
# RAM base address:  0x00000100  (same as your previous test)
#
# PROGRESS REGISTER: x31 (same convention as your ALU test)
#   x31 = 1 → Starting
#   x31 = 2 → SCENARIO 1 (CSR R/W) passed
#   x31 = 3 → SCENARIO 2 (ECALL) passed
#   x31 = 4 → SCENARIO 3 (EBREAK) passed
#   x31 = 5 → SCENARIO 4 (Illegal Instruction) passed
#   x31 = 6 → ALL TESTS PASSED
# =============================================================================

.section .text
.global _start
_start:
    addi x31, x0, 1          # Progress tracker = 1 (START)

# =============================================================================
# SCENARIO 1: CSR Read / Write / Bit-Set / Bit-Clear
# Tests: csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci
#        Using mscratch (0x340) — safe to read/write freely
# =============================================================================

    # ── Test 1a: CSRRW — write and read back ────────────────────────────────
    addi  x1, x0, 0x55           # x1 = 0x55 (test pattern)
    csrrw x2, mscratch, x1       # mscratch ← 0x55 ; x2 ← old value (was 0)
    # EXPECT: x2 == 0x00000000 (reset value), mscratch == 0x55

    csrrw x3, mscratch, x0       # mscratch ← 0x00 ; x3 ← old value
    # EXPECT: x3 == 0x00000055 (confirm write worked)

    # ── Test 1b: CSRRS — set specific bits ──────────────────────────────────
    addi  x4, x0, 0x0F           # x4 = 0x0F (mask: set lower 4 bits)
    csrrw x0, mscratch, x0       # clear mscratch first
    csrrs x5, mscratch, x4       # mscratch |= 0x0F ; x5 ← old (0)
    csrr  x6, mscratch            # read mscratch into x6 (uses csrrs x6,csr,x0)
    # EXPECT: x6 == 0x0000000F (lower 4 bits set)

    # ── Test 1c: CSRRC — clear specific bits ────────────────────────────────
    addi  x7, x0, 0x05           # x7 = 0x05 (mask: clear bits 0 and 2)
    csrrc x8, mscratch, x7       # mscratch &= ~0x05 ; x8 ← old (0x0F)
    csrr  x9, mscratch            # read mscratch after clear
    # EXPECT: x8 == 0x0000000F, x9 == 0x0000000A (bits 0,2 cleared from 0xF)

    # ── Test 1d: CSRRWI — write immediate ───────────────────────────────────
    csrrwi x0, mscratch, 31      # mscratch ← 31 (0x1F) using 5-bit uimm
    csrr  x10, mscratch           # read it back
    # EXPECT: x10 == 0x0000001F

    # ── Test 1e: CSRRSI — set bits immediate ────────────────────────────────
    csrrsi x0, mscratch, 0       # uimm=0 → NO WRITE (suppression rule), just read old
    csrrwi x0, mscratch, 0       # clear mscratch
    csrrsi x11, mscratch, 16     # mscratch |= 16 (0x10) ; x11 ← old (0)
    csrr  x12, mscratch
    # EXPECT: x11 == 0, x12 == 0x00000010

    # ── Test 1f: CSRRCI — clear bits immediate ──────────────────────────────
    csrrci x0, mscratch, 16      # mscratch &= ~16 → clears bit 4
    csrr  x13, mscratch
    # EXPECT: x13 == 0x00000000

    # ── Test 1g: Read-only CSRs (mhartid, mvendorid, misa) ──────────────────
    csrr  x14, mhartid            # 0xF14 → always 0 (single hart)
    csrr  x15, mvendorid          # 0xF11 → always 0 (non-commercial)
    csrr  x16, misa               # 0x301 → should be 0x40001100 or similar RV32I encoding
    # EXPECT: x14 == 0, x15 == 0, x16 != 0

    # ── Test 1h: Performance counters — mcycle must be counting ─────────────
    csrr  x17, mcycle             # 0xB00 — read cycle counter (low 32)
    nop                           # burn a cycle (= addi x0, x0, 0)
    nop
    nop
    csrr  x18, mcycle             # read again
    # EXPECT: x18 > x17 (cycle counter is incrementing)

    addi  x31, x31, 1             # Progress tracker = 2 (SCENARIO 1 done)

# =============================================================================
# SCENARIO 2: mtvec Setup + ECALL
# What happens:
#   1. We write the address of "ecall_handler" into mtvec
#   2. We execute "ecall" — this triggers an M-mode exception (cause = 11)
#   3. Hardware automatically:
#       - saves PC into mepc
#       - saves cause 11 into mcause
#       - flushes pipeline
#       - jumps to mtvec (our handler)
#   4. The handler checks mcause, sets x31=3, then mret
#   5. mret restores PC to mepc+4 (we manually set mepc = mepc+4 before mret)
# =============================================================================

    # Point mtvec at our handler (direct mode: mtvec[1:0] = 00)
    la    x20, ecall_handler       # x20 = address of ecall_handler label
    csrw  mtvec, x20              # mtvec ← address of ecall_handler

    # ecall — this will trap to ecall_handler
    # mcause will be 11 (ecall from M-mode, since we start in M-mode)
    ecall                          # <── TRAP HAPPENS HERE, pipeline flushes

    # If the handler correctly returned, execution continues HERE
    # (because the handler did: mepc = mepc+4, then mret)
    # x31 should be 3 at this point (set by handler)
    # Note: the ecall itself does NOT advance x31; the handler does.

# =============================================================================
# SCENARIO 3: EBREAK
# Same flow as ECALL, but mcause = 3 (Breakpoint)
# We reuse the same handler — it checks mcause to know what happened
# =============================================================================

    # mtvec is still pointing at ecall_handler (or we re-point it):
    la    x20, general_handler
    csrw  mtvec, x20

    ebreak                         # <── TRAP HAPPENS HERE (mcause = 3)

    # If handler returned correctly, x31 should now be 4

# =============================================================================
# SCENARIO 4: Illegal Instruction
# We will construct an instruction word that is NOT a valid RV32I opcode.
# The hardware should:
#   - detect it as illegal (illegal_instr signal from decoder)
#   - trap to mtvec with mcause = 2
#   - mtval = the illegal instruction encoding
# =============================================================================

    la    x20, general_handler
    csrw  mtvec, x20

    # We need to execute an illegal instruction.
    # The cleanest way in assembly is to embed a raw bad word with .word:
    .word 0x00000000               # opcode 0x00 = undefined → illegal instruction
                                    # Hardware will trap here with mcause=2

    # If handler returned correctly, x31 should now be 5

# =============================================================================
# SCENARIO 5: MRET and CSR state integrity
# Verify that mret restores: priv mode, MIE, MPIE
# =============================================================================

    # At this point we've been through 3 traps and 3 mrets.
    # Let's verify the CSR state is clean.

    # Read mstatus and verify MIE is restored (MPIE→MIE on each mret)
    csrr  x19, mstatus             # read current mstatus
    # After each mret: MIE ← MPIE (which was original MIE before the trap)
    # Since MIE was 0 before any trap (we never set it), MIE should still be 0
    # and MPIE should be 1 (mret sets MPIE=1).
    # mstatus[7] = MPIE should = 1 (set by last mret)
    # mstatus[3] = MIE  should = 0 (original value before traps)

    # Read mepc — should contain the PC of the last ecall/ebreak/.word
    csrr  x20, mepc                # x20 = where last trap came from

    # Read mcause — should contain 2 (last trap was illegal instruction)
    csrr  x21, mcause              # x21 = 2

    addi  x31, x31, 1             # Progress tracker = 6 (ALL PASSED)

done:
    beq   x0, x0, done            # Infinite loop — halts here

# =============================================================================
# TRAP HANDLERS
# =============================================================================

# ── ecall_handler ─────────────────────────────────────────────────────────────
# Called when:  ecall executed in M-mode (mcause = 11)
# What it does: sets x31 = 3, adjusts mepc to skip the ecall, returns
# =============================================================================
ecall_handler:
    # Save working registers using mscratch as scratch space
    # In a real OS you'd save to a stack. Here we use x28/x29 directly.

    csrr  x28, mcause              # x28 = trap cause
    csrr  x29, mepc                # x29 = PC of the ecall instruction

    # Verify cause is 11 (ecall from M-mode)
    addi  x30, x0, 11
    bne   x28, x30, ecall_handler_fail

    # Advance x31 = 3
    addi  x31, x0, 3

    # Move mepc past the ecall instruction (ecall is 4 bytes)
    addi  x29, x29, 4
    csrw  mepc, x29                # mepc ← PC + 4

    mret                           # return to PC+4, restore privilege & MIE

ecall_handler_fail:
    addi  x31, x0, 0xDEAD         # FAIL: wrong cause code
    beq   x0, x0, ecall_handler_fail

# ── general_handler ───────────────────────────────────────────────────────────
# Called for: ebreak (mcause=3) and illegal instruction (mcause=2)
# Dispatches based on mcause, advances x31, skips the faulting instruction
# =============================================================================
general_handler:
    csrr  x28, mcause              # x28 = cause
    csrr  x29, mepc                # x29 = faulting PC

    # Check for ebreak (cause = 3)
    addi  x30, x0, 3
    beq   x28, x30, handle_ebreak

    # Check for illegal instruction (cause = 2)
    addi  x30, x0, 2
    beq   x28, x30, handle_illegal

    # Unknown trap — hang
    beq   x0, x0, general_handler

handle_ebreak:
    addi  x31, x0, 4              # SCENARIO 3 passed
    addi  x29, x29, 4             # skip ebreak instruction
    csrw  mepc, x29
    mret

handle_illegal:
    addi  x31, x0, 5              # SCENARIO 4 passed
    addi  x29, x29, 4             # skip the illegal .word instruction
    csrw  mepc, x29
    mret
```

---

## 9. Expected Register State After Each Test

### After Scenario 1 (CSR R/W):
| Register | Value | Why |
|----------|-------|-----|
| x1 | `0x55` | Test pattern |
| x2 | `0x00` | Old mscratch before first write |
| x3 | `0x55` | Confirmed CSRRW wrote 0x55 |
| x5 | `0x00` | Old mscratch before CSRRS |
| x6 | `0x0F` | After CSRRS: lower 4 bits set |
| x8 | `0x0F` | Old value before CSRRC |
| x9 | `0x0A` | After CSRRC: bits 0,2 cleared |
| x10 | `0x1F` | CSRRWI wrote 31 (= 0x1F) |
| x11 | `0x00` | Old mscratch before CSRRSI |
| x12 | `0x10` | After CSRRSI: bit 4 set |
| x13 | `0x00` | After CSRRCI: bit 4 cleared |
| x14 | `0x00` | mhartid = 0 (single hart) |
| x15 | `0x00` | mvendorid = 0 (non-commercial) |
| x16 | non-zero | misa encodes RV32IMAC |
| x18 > x17 | — | mcycle is counting |
| **x31** | **2** | Scenario 1 complete |

### After Scenario 2 (ECALL):
| Register | Value | Why |
|----------|-------|-----|
| x28 | `11` | mcause from ecall handler |
| x29 | `mepc+4` | Adjusted return address |
| **x31** | **3** | Set by ecall_handler |

CSR state after ECALL+MRET:
| CSR | Value | Why |
|-----|-------|-----|
| `mepc` | PC of ecall | Hardware saved it on trap |
| `mcause` | 11 | Ecall from M-mode |
| `mstatus[MPIE]` | 1 | mret sets MPIE=1 |
| `mstatus[MIE]` | 0 | Was 0 before trap, MIE=MPIE on mret |
| `mstatus[MPP]` | 0 | mret clears MPP |

### After Scenario 3 (EBREAK):
| Register | Value | Why |
|----------|-------|-----|
| x28 | `3` | mcause from ebreak |
| **x31** | **4** | Set by general_handler ebreak path |

### After Scenario 4 (Illegal Instruction):
| Register | Value | Why |
|----------|-------|-----|
| x28 | `2` | mcause = illegal instruction |
| **x31** | **5** | Set by general_handler illegal path |

### After Scenario 5 (Final):
| Register | Value | Why |
|----------|-------|-----|
| x19 | `mstatus snapshot` | Check bit[7]=MPIE=1, bit[3]=MIE=0 |
| x20 | `PC of .word 0x00000000` | Where last trap came from |
| x21 | `2` | Last mcause = illegal instruction |
| **x31** | **6** | ALL TESTS PASSED ✅ |

---

## Quick Reference — Instruction Encoding

| Instruction | Opcode | funct3 | rs1 meaning | Immediate |
|-------------|--------|--------|-------------|-----------|
| `csrrw rd, csr, rs1` | 1110011 | 001 | register value | — |
| `csrrs rd, csr, rs1` | 1110011 | 010 | bit-set mask | — |
| `csrrc rd, csr, rs1` | 1110011 | 011 | bit-clear mask | — |
| `csrrwi rd, csr, uimm` | 1110011 | 101 | — | 5-bit zero-ext |
| `csrrsi rd, csr, uimm` | 1110011 | 110 | — | 5-bit zero-ext |
| `csrrci rd, csr, uimm` | 1110011 | 111 | — | 5-bit zero-ext |
| `ecall` | 1110011 | 000 | — | `[31:20]=0x000` |
| `ebreak` | 1110011 | 000 | — | `[31:20]=0x001` |
| `mret` | 1110011 | 000 | — | `[31:20]=0x302` |
| `sret` | 1110011 | 000 | — | `[31:20]=0x102` |
