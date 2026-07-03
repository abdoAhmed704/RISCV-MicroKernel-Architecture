# RISC-V CSR Unit Reference Manual

Project: `RISCV-MicroKernel-Architecture`  
Core: RV32I 5-stage pipelined core  
CSR RTL: `rtl/RV32I/riscv_csr_unit.sv`  
Pipeline integration: `rtl/RV32I/riscv_top_pipeline.sv`

> This is an architecture reference for the custom CSR subsystem. It is written to let you implement, debug, and extend the CSR unit without repeatedly opening the RTL.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [CSR Unit Architecture](#2-csr-unit-architecture)
3. [Privilege Modes](#3-privilege-modes)
4. [CSR Register Reference](#4-csr-register-reference)
5. [Bitfield Reference](#5-bitfield-reference)
6. [CSR Instructions](#6-csr-instructions)
7. [Interrupt System](#7-interrupt-system)
8. [Exception System](#8-exception-system)
9. [Trap Handling](#9-trap-handling)
10. [Counters and Timers](#10-counters-and-timers)
11. [Complete Trap Timelines](#11-complete-trap-timelines)
12. [Pipeline Interaction](#12-pipeline-interaction)
13. [Complete Signal Reference](#13-complete-signal-reference)
14. [State Transition Diagrams](#14-state-transition-diagrams)
15. [Typical Execution Examples](#15-typical-execution-examples)
16. [Debugging Guide](#16-debugging-guide)
17. [CSR Cheat Sheet](#17-csr-cheat-sheet)
18. [Common Interview Questions](#18-common-interview-questions)

---

## 1. Introduction

### What CSR Means

CSR means Control and Status Register. A CSR is a special architectural register used to control the processor itself or report processor state. CSRs are separate from the integer register file `x0` through `x31`.

Integer registers answer: "What data is my program computing?"  
CSRs answer: "What is the processor doing, what privilege level is active, where should traps go, which interrupts are enabled, and what caused the last trap?"

### Why CSRs Exist

A real processor needs more than arithmetic and memory instructions. It must be able to:

| Need | CSR Mechanism |
|---|---|
| Enter an operating-system or firmware handler | `mtvec`, `stvec` |
| Remember where a trap happened | `mepc`, `sepc` |
| Remember why a trap happened | `mcause`, `scause` |
| Disable interrupts while handling traps | `mstatus.MIE`, `mstatus.SIE` |
| Return from traps safely | `mret`, `sret`, `MPP`, `SPP`, `MPIE`, `SPIE` |
| Enable selected interrupts | `mie`, `sie` |
| Detect pending interrupts | `mip`, `sip` |
| Delegate traps from M-mode to S-mode | `medeleg`, `mideleg` |
| Count cycles and retired instructions | `mcycle`, `minstret` |
| Provide timer interrupts | `mtime`, `mtimecmp`, `stimecmp` |

Without CSRs, the core could execute arithmetic, branches, loads, and stores, but it would have no architectural way to recover from faults, call into firmware, handle interrupts, or build an operating system boundary.

### Relationship with the RISC-V Privileged Architecture

The RISC-V unprivileged ISA defines normal instructions such as `add`, `lw`, `jal`, and `beq`. The privileged architecture defines:

- Privilege modes: Machine, Supervisor, User.
- Trap entry and trap return behavior.
- CSR addresses and privilege rules.
- Interrupt and exception cause codes.
- Delegation from M-mode to S-mode.
- Timer/counter behavior.

This CSR unit implements an educational but meaningful subset of the privileged architecture for a 32-bit RISC-V core. It focuses on Machine and Supervisor behavior, trap redirection, CSR access, and interrupt/timer support.

### Implementation Scope

Implemented privilege modes:

| Mode | Encoding | Implemented? | Notes |
|---|---:|---|---|
| User | `00` | Partial state value only | Can be restored by `mret`/`sret` if software programs stack bits that way, but no full U-mode CSR model exists. |
| Supervisor | `01` | Yes | S-mode trap CSRs and delegated traps are supported. |
| Reserved | `10` | No | Should not be used. |
| Machine | `11` | Yes | Reset mode and highest privilege mode. |

Important educational simplifications:

- `satp` reads as zero and address translation is not implemented.
- `mvendorid`, `marchid`, `mimpid`, and `mhartid` read as zero.
- `mip` and `sip` are computed snapshots, not writable storage registers.
- `mtime`, `mtimecmp`, and `stimecmp` are implemented inside the CSR unit, whereas real platforms often expose timers through memory-mapped CLINT/ACLINT devices.
- `sie` and `sip` exist as S-mode views through `mie/mideleg` and `mip/mideleg`.
- The CSR file is not a generic 4096-entry memory; it is an explicit decode of implemented CSRs.

---

## 2. CSR Unit Architecture

### Architectural Role

The CSR unit is the privileged-control center of the core. It performs four major jobs:

1. CSR read/write execution for Zicsr instructions.
2. Privilege permission and illegal CSR access checking.
3. Interrupt and exception detection, prioritization, and delegation.
4. Trap entry/return redirection and pipeline flushing.

### High-Level Diagram

```text
                           +--------------------------------------+
                           |          riscv_csr_unit              |
                           |                                      |
 External IRQs             |  +------------+      +------------+  |
 mexternal --------------->|  | Interrupt  |----->| Trap       |  |
 sexternal --------------->|  | Detector   |      | Arbiter    |  |
                           |  +------------+      +-----+------+  |
 Pipeline exception flags  |                           |         |
 illegal/ecall/ebreak ---->|  +------------+           |         |
 misalign/load/store ----->|  | Exception  |-----------+         |
                           |  | Decoder    |                     |
 CSR instruction inputs    |  +------------+                     |
 addr/op/src/wen --------->|                                      |
                           |  +------------+      +------------+  |
                           |  | CSR Read   |<---->| CSR State  |  |
                           |  | Mux        |      | Registers  |  |
                           |  +------------+      +------------+  |
                           |        |                    ^        |
                           |        v                    |        |
                           |  o_csr_unit_rdata      CSR writes    |
                           |                                      |
                           |  +--------------------------------+  |
                           |  | Trap target and return router  |  |
                           |  +--------------------------------+  |
                           |        |        |        |           |
                           +--------+--------+--------+-----------+
                                    |        |        |
                              handler PC  return PC  flush/redirect
```

### Pipeline Placement

CSR operations are resolved in the Memory stage. Decode identifies SYSTEM/CSR instructions, Execute prepares operands, and the CSR unit reads/writes or traps in the M stage.

```text
IF -> ID -> EX -> MEM/CSR -> WB
            |       |
            |       +-- CSR read data captured for writeback
            |       +-- trap decision made
            |       +-- trap CSRs updated on clock edge
            |
            +-- CSR source is selected:
                register form: RD1E
                immediate form: zero-extended uimm[4:0]
```

### Internal Blocks

| Block | Purpose | Key Signals |
|---|---|---|
| Privilege tracker | Stores current mode | `priv_mode_q` |
| CSR storage | Holds writable CSR state | `mstatus_q`, `mie_q`, `mtvec_q`, etc. |
| Constant CSR model | Provides read-only architectural IDs | `misa`, vendor/arch/imp/hart IDs |
| S-mode views | Builds `sstatus`, `sie`, `sip` from machine state | `sstatus`, `mie_q & mideleg_q`, `mip_val & mideleg_q` |
| Interrupt detector | Gates pending IRQs with enables and global bits | `meip_active`, `mtip_active`, `seip_active`, `stip_active` |
| Delegation router | Chooses M-mode or S-mode trap target | `medeleg_q`, `mideleg_q`, `trap_to_s` |
| CSR legality checker | Detects invalid address, privilege violation, read-only writes | `csr_illegal` |
| Exception decoder | Chooses cause and trap value | `exc_cause`, `exc_tval` |
| Trap target generator | Computes `mtvec/stvec` direct or vectored address | `trap_target_pc` |
| CSR read mux | Produces `o_csr_unit_rdata` | CSR address decoder |
| CSR write datapath | Implements write/set/clear operations | `csr_wdata` |
| Sequential update block | Performs reset, counters, traps, returns, CSR writes | `always_ff` |

### Input Summary

| Input | Width | Producer | Purpose |
|---|---:|---|---|
| `i_csr_unit_clk` | 1 | Top-level `clk` | Clock for CSR state. |
| `i_csr_unit_rst_n` | 1 | Top-level `rst_n` | Active-low async reset. |
| `i_csr_unit_mexternal` | 1 | External controller | Machine external interrupt request. |
| `i_csr_unit_sexternal` | 1 | External controller | Supervisor external interrupt request. |
| `i_csr_unit_mem_wen` | 1 | M-stage store control | Present but not functionally used by CSR unit. |
| `i_csr_unit_pc` | 32 | `PCM` | PC of instruction in Memory stage. Saved to `mepc/sepc`. |
| `i_csr_unit_fault_addr` | 32 | `ALUResultM` | Bad target/load/store address for `mtval/stval`. |
| `i_csr_unit_instr` | 32 | `instrM` | Instruction word for illegal-instruction `tval` and `minstret`. |
| `i_csr_unit_csr_wen` | 1 | `csr_wenM` | CSR write enable after Zicsr suppression rules. |
| `i_csr_unit_op` | 2 | `csr_opM` | CSR op: `01` write, `10` set, `11` clear. |
| `i_csr_unit_src` | 32 | `csr_srcM` | CSR write operand. |
| `i_csr_unit_csr_addr` | 12 | `csr_addrM` | CSR address from instruction bits `[31:20]`. |
| `i_csr_unit_illegal_instr_id` | 1 | Decode path, pipelined | Illegal instruction detected by decoder. |
| `i_csr_unit_illegal_instr_exe` | 1 | Tied low | Reserved for execute-stage illegal detection. |
| `i_csr_unit_instr_addr_misaligned` | 1 | Execute path, pipelined | Taken branch/jump target not word-aligned. |
| `i_csr_unit_lw_access_fault` | 1 | Memory stage | Load address invalid or misaligned. |
| `i_csr_unit_sw_access_fault` | 1 | Memory stage | Store address invalid or misaligned. |
| `i_csr_unit_mret_wb` | 1 | SYSTEM decode, pipelined | MRET instruction in M stage. |
| `i_csr_unit_ecall` | 1 | SYSTEM decode, pipelined | ECALL instruction in M stage. |
| `i_csr_unit_ebreak` | 1 | SYSTEM decode, pipelined | EBREAK instruction in M stage. |
| `i_csr_unit_sret` | 1 | SYSTEM decode, pipelined | SRET instruction in M stage. |

### Output Summary

| Output | Width | Consumer | Purpose |
|---|---:|---|---|
| `o_csr_unit_ack` | 1 | Top-level `irq_ack` | Pulses when an interrupt is accepted. |
| `o_csr_unit_rdata` | 32 | WB mux via `CSRRDataW` | Old CSR value returned by CSR instruction. |
| `o_csr_unit_irq_handler` | 32 | Fetch PC mux | Trap handler target address. |
| `o_csr_unit_rtrn_addr` | 32 | Fetch PC mux | Return PC from `mepc` or `sepc`. |
| `o_csr_unit_addr_ctrl` | 1 | Fetch target select | `1`: handler PC. `0`: return PC during return. |
| `o_csr_unit_mux1` | 1 | Fetch redirect select | Forces PC redirect for traps and returns. |
| `o_csr_unit_if_flush` | 1 | Currently redundant | High on trap/return. |
| `o_csr_unit_id_flush` | 1 | Fetch pipeline register clear | Flushes Decode stage. |
| `o_csr_unit_exe_flush` | 1 | Decode/Execute clears | Flushes Execute and Memory path. |
| `o_csr_unit_mem_flush` | 1 | Memory/WB clear and CSR read latch clear | Flushes Writeback path. |

---

## 3. Privilege Modes

### Machine Mode

Machine mode is the highest privilege level. The core resets into M-mode:

```text
priv_mode_q <= 2'b11
```

M-mode can access all implemented CSRs, configure delegation, install trap vectors, enable interrupts, and recover from traps.

Typical M-mode responsibilities:

- Boot firmware.
- Initialize `mtvec`.
- Initialize `mstatus`, `mie`, `medeleg`, `mideleg`.
- Provide trap handlers.
- Optionally delegate selected traps to S-mode.
- Return from traps with `mret`.

### Supervisor Mode

Supervisor mode is lower than M-mode and intended for an operating-system kernel. In this implementation, S-mode exists architecturally and can receive delegated traps through `stvec`, `sepc`, `scause`, and `stval`.

S-mode can access S-mode CSRs such as `sstatus`, `stvec`, `sscratch`, `sepc`, `scause`, `stval`, `stimecmp`, `sie`, and `sip`, but cannot access M-mode CSRs unless the address privilege check allows it.

### User Mode

User mode is represented by the privilege encoding `2'b00`, and `mret/sret` can restore to it if software places that value in `MPP` or `SPP`. However, this core does not implement a full user environment or virtual memory protection. Treat U-mode support as incomplete.

### Privilege Check

RISC-V CSR addresses encode minimum privilege in address bits `[9:8]`:

| `csr_addr[9:8]` | Minimum privilege |
|---:|---|
| `00` | User |
| `01` | Supervisor |
| `10` | Hypervisor/reserved in many profiles |
| `11` | Machine |

The unit checks:

```systemverilog
priv_violation = (priv_mode_q < i_csr_unit_csr_addr[9:8]);
```

If the current mode is too low, the CSR access becomes an illegal instruction trap.

### Privilege Stack

The privileged architecture saves previous privilege and interrupt-enable state on trap entry:

Machine trap entry:

```text
mstatus.MPP  <- old privilege mode
mstatus.MPIE <- old mstatus.MIE
mstatus.MIE  <- 0
priv_mode_q  <- Machine
```

Supervisor trap entry:

```text
mstatus.SPP  <- old privilege mode bit 0
mstatus.SPIE <- old mstatus.SIE
mstatus.SIE  <- 0
priv_mode_q  <- Supervisor
```

Trap return:

```text
MRET:
  priv_mode_q     <- mstatus.MPP
  mstatus.MIE     <- mstatus.MPIE
  mstatus.MPIE    <- 1
  mstatus.MPP     <- 00
  next PC         <- mepc

SRET:
  priv_mode_q     <- {1'b0, mstatus.SPP}
  mstatus.SIE     <- mstatus.SPIE
  mstatus.SPIE    <- 1
  mstatus.SPP     <- 0
  next PC         <- sepc
```

### MPP and SPP

| Field | Bits | Meaning |
|---|---:|---|
| `MPP` | `mstatus[12:11]` | Previous privilege before an M-mode trap. |
| `SPP` | `mstatus[8]` | Previous privilege before an S-mode trap: `0` lower than S, `1` S-mode. |

Common mistake: expecting `mret` to return to `mepc + 4`. Hardware returns to exactly `mepc`. Trap handlers must increment `mepc` manually for traps such as `ecall`, `ebreak`, and illegal instruction when the intended behavior is to skip the trapping instruction.

---

## 4. CSR Register Reference

### Address Map

| CSR | Address | Access in this core | Backing storage/view |
|---|---:|---|---|
| `sstatus` | `0x100` | S/M read-write view | selected fields in `mstatus_q` |
| `sie` | `0x104` | S/M read-write view | `mie_q & mideleg_q` |
| `stvec` | `0x105` | S/M read-write | `stvec_q` |
| `sscratch` | `0x140` | S/M read-write | `sscratch_q` |
| `sepc` | `0x141` | S/M read-write | `sepc_q` |
| `scause` | `0x142` | S/M read-write | `scause_q` |
| `stval` | `0x143` | S/M read-write | `stval_q` |
| `sip` | `0x144` | S/M read-only snapshot | `mip_val & mideleg_q` |
| `stimecmp` | `0x14D/0x15D` | S/M read-write | `stimecmp[31:0]`, `[63:32]` |
| `satp` | `0x180` | S/M read-only zero | constant `0` |
| `mstatus` | `0x300` | M read-write selected bits | `mstatus_q` |
| `misa` | `0x301` | M read-only | constant |
| `medeleg` | `0x302` | M read-write | `medeleg_q` |
| `mideleg` | `0x303` | M read-write masked | `mideleg_q & 0x222` |
| `mie` | `0x304` | M read-write masked | `mie_q & 0xAAA` |
| `mtvec` | `0x305` | M read-write | `mtvec_q` |
| `mscratch` | `0x340` | M read-write | `mscratch_q` |
| `mepc` | `0x341` | M read-write aligned | `mepc_q` |
| `mcause` | `0x342` | M read-write | `mcause_q` |
| `mtval` | `0x343` | M read-write | `mtval_q` |
| `mip` | `0x344` | M read-only snapshot | `mip_val` |
| `mcycle` | `0xB00/0xB80` | M read-write | `mcycle_q` |
| `minstret` | `0xB02/0xB82` | M read-write | `minstret_q` |
| `cycle` | `0xC00/0xC80` | Read-only address range | aliases `mcycle_q` |
| `instret` | `0xC02/0xC82` | Read-only address range | aliases `minstret_q` |
| `mvendorid` | `0xF11` | M read-only | constant `0` |
| `marchid` | `0xF12` | M read-only | constant `0` |
| `mimpid` | `0xF13` | M read-only | constant `0` |
| `mhartid` | `0xF14` | M read-only | constant `0` |
| `mtimecmp` | `0x30D/0x31D` | M read-write | `mtimecmp[31:0]`, `[63:32]` |

### `mstatus` - Machine Status Register

| Item | Value |
|---|---|
| Address | `0x300` |
| Full name | Machine Status |
| Name meaning | Machine-mode global status and trap stack |
| Reset value | `0x00000000` |
| Writable? | Selected fields only |
| Hardware writes | On M/S trap entry and MRET/SRET |
| Software writes | To enable interrupts and program previous-mode bits |
| Readers | Trap handlers, OS/firmware, CSR tests |

Purpose: `mstatus` controls global interrupt enables and stores previous privilege/interrupt state for trap return.

Implemented writable fields:

| Field | Bits | Meaning |
|---|---:|---|
| `SIE` | `1` | Supervisor global interrupt enable |
| `MIE` | `3` | Machine global interrupt enable |
| `SPIE` | `5` | Previous SIE saved on S trap entry |
| `MPIE` | `7` | Previous MIE saved on M trap entry |
| `SPP` | `8` | Previous privilege for S trap |
| `MPP` | `12:11` | Previous privilege for M trap |

Example:

```asm
li   t0, 0x8
csrs mstatus, t0       # Set MIE
```

Common mistakes:

- Setting `mie.MTIE` but forgetting `mstatus.MIE`.
- Expecting `MIE` to stay set inside a trap handler. Trap entry clears it.
- Forgetting that `mret` restores `MIE` from `MPIE`.

### `sstatus` - Supervisor Status Register

| Item | Value |
|---|---|
| Address | `0x100` |
| Full name | Supervisor Status |
| Name meaning | S-mode visible subset of `mstatus` |
| Reset value | `0x00000000` |
| Writable? | Selected S fields only |
| Hardware writes | Via same `mstatus_q` fields on S trap/SRET |
| Software writes | S-mode enables interrupts and controls S trap stack |
| Readers | S-mode trap handlers |

`sstatus` is not separate storage. It is a view:

```text
sstatus.SIE  = mstatus.SIE
sstatus.SPIE = mstatus.SPIE
sstatus.SPP  = mstatus.SPP
```

Common mistake: debugging `sstatus` without checking `mstatus`. In this implementation, `sstatus` changes are `mstatus_q` field changes.

### `misa` - Machine ISA Register

| Item | Value |
|---|---|
| Address | `0x301` |
| Full name | Machine ISA |
| Reset value | Constant |
| Writable? | No |
| Purpose | Reports supported ISA extensions and XLEN |

The RTL constant sets `MXL = 01` for RV32 and advertises a fixed extension bitmap. Treat it as an identity/reporting register, not a feature-control register.

Common mistake: trying to write `misa`. Since `0x301` is in the read-write CSR address range but the RTL does not implement writes to it, writes are ignored rather than changing ISA behavior.

### `mie` - Machine Interrupt Enable

| Item | Value |
|---|---|
| Address | `0x304` |
| Full name | Machine Interrupt Enable |
| Reset value | `0x00000000` |
| Writable? | Yes, masked to `0x00000AAA` |
| Hardware writes | Reset only |
| Software writes | Enables individual interrupt sources |

Implemented interrupt enable bits:

| Bit | Name | Interrupt |
|---:|---|---|
| 1 | `SSIE` | Supervisor software interrupt, addressable but no source implemented |
| 3 | `MSIE` | Machine software interrupt, addressable but no source implemented |
| 5 | `STIE` | Supervisor timer interrupt |
| 7 | `MTIE` | Machine timer interrupt |
| 9 | `SEIE` | Supervisor external interrupt |
| 11 | `MEIE` | Machine external interrupt |

RTL accepts writes only to bits in `0xAAA`. Active interrupt logic uses bits `5`, `7`, `9`, and `11`.

Example:

```asm
li   t0, (1 << 7)      # MTIE
csrs mie, t0
li   t0, (1 << 3)      # MIE
csrs mstatus, t0
```

### `mip` - Machine Interrupt Pending

| Item | Value |
|---|---|
| Address | `0x344` |
| Full name | Machine Interrupt Pending |
| Reset value | Dynamic, normally zero before events |
| Writable? | No in this RTL |
| Hardware writes | No storage; computed every cycle |

Pending bits are computed as:

| Bit | Name | Source |
|---:|---|---|
| 5 | `STIP` | `mtime >= stimecmp` |
| 7 | `MTIP` | `mtime >= mtimecmp` |
| 9 | `SEIP` | `i_csr_unit_sexternal` |
| 11 | `MEIP` | `i_csr_unit_mexternal` |

Why pending and enable are separate:

- Pending means the event exists.
- Enable means the core is allowed to service it.
- Global enable means the privilege level currently allows interrupts.

This separation lets software observe a pending event while keeping it masked.

### `mtvec` - Machine Trap Vector

| Item | Value |
|---|---|
| Address | `0x305` |
| Full name | Machine Trap Vector |
| Reset value | `0x00000000` |
| Writable? | Yes |
| Hardware writes | Reset only |
| Software writes | Installs M-mode trap handler |

Layout:

```text
31                          2 1 0
+----------------------------+---+
| BASE[31:2]                 |MODE|
+----------------------------+---+
```

| MODE | Meaning |
|---:|---|
| `00` | Direct: all traps go to `BASE` |
| `01` | Vectored: interrupts go to `BASE + 4*cause`, exceptions go to `BASE` |
| Other | Not meaningfully implemented; behaves like direct except low bits are masked for target |

The target address always masks low bits:

```text
base = {mtvec[31:2], 2'b00}
```

### `stvec` - Supervisor Trap Vector

Same layout as `mtvec`, but used for traps delegated to S-mode.

| Item | Value |
|---|---|
| Address | `0x105` |
| Reset value | `0x00000000` |
| Writable? | Yes |
| Purpose | S-mode trap handler base/mode |

### `medeleg` - Machine Exception Delegation

| Item | Value |
|---|---|
| Address | `0x302` |
| Reset value | `0x00000000` |
| Writable? | Yes |
| Purpose | Selects which exceptions may route to S-mode |

If `medeleg[cause]` is `1` and the current privilege is below M-mode, an exception traps to S-mode instead of M-mode.

Important rule in this RTL:

```text
exc_delegated = exc_active && medeleg[exc_cause] && (priv_mode_q < M)
```

An exception occurring while already in M-mode is not delegated to S-mode.

### `mideleg` - Machine Interrupt Delegation

| Item | Value |
|---|---|
| Address | `0x303` |
| Reset value | `0x00000000` |
| Writable? | Yes, masked to `0x00000222` |
| Purpose | Selects which interrupts may route to S-mode |

Writable delegation bits are `1`, `5`, and `9` by mask, although active interrupt logic also checks delegation bit `7` and `11`. Because writes are masked to `0x222`, normal software cannot set `mideleg[7]` or `mideleg[11]` through this RTL.

> Warning: If you expect machine timer or machine external interrupts to delegate to S-mode, review the mask. The detector checks `mideleg[7]` and `mideleg[11]`, but the write mask prevents those bits from being written.

### `mscratch` and `sscratch`

| CSR | Address | Reset | Writable | Purpose |
|---|---:|---:|---|---|
| `mscratch` | `0x340` | `0` | Yes | M-mode scratch storage |
| `sscratch` | `0x140` | `0` | Yes | S-mode scratch storage |

Scratch CSRs are software-owned. Hardware does not interpret them. Trap handlers commonly use scratch registers to store a stack pointer, hart-local pointer, or temporary context pointer.

Example:

```asm
csrrw sp, mscratch, sp  # Swap user sp with machine scratch
```

### `mepc` and `sepc`

| CSR | Address | Reset | Writable | Purpose |
|---|---:|---:|---|---|
| `mepc` | `0x341` | `0` | Yes, aligned | M-mode trap return PC |
| `sepc` | `0x141` | `0` | Yes, aligned | S-mode trap return PC |

Hardware writes:

- `mepc <- i_csr_unit_pc` on M-mode trap entry.
- `sepc <- i_csr_unit_pc` on S-mode trap entry.

Software writes are word-aligned:

```text
mepc <= {csr_wdata[31:2], 2'b00}
sepc <= {csr_wdata[31:2], 2'b00}
```

Common mistake: not incrementing `mepc/sepc` in the trap handler for synchronous traps that should resume after the faulting instruction.

### `mcause` and `scause`

| CSR | Address | Reset | Writable | Purpose |
|---|---:|---:|---|---|
| `mcause` | `0x342` | `0` | Yes | M-mode trap reason |
| `scause` | `0x142` | `0` | Yes | S-mode trap reason |

Layout:

```text
31 30                         0
+--+---------------------------+
|I | Exception/interrupt code  |
+--+---------------------------+
```

`I = 1` means interrupt. `I = 0` means exception.

Examples:

| Value | Meaning |
|---:|---|
| `0x00000002` | Illegal instruction |
| `0x00000003` | Breakpoint |
| `0x0000000B` | ECALL from M-mode |
| `0x80000007` | Machine timer interrupt |
| `0x8000000B` | Machine external interrupt |

### `mtval` and `stval`

| CSR | Address | Reset | Writable | Purpose |
|---|---:|---:|---|---|
| `mtval` | `0x343` | `0` | Yes | M-mode trap value |
| `stval` | `0x143` | `0` | Yes | S-mode trap value |

Hardware writes:

| Trap | `tval` value |
|---|---|
| Illegal instruction / CSR illegal | instruction word |
| Instruction address misaligned | bad target address |
| Load access fault | bad load address |
| Store access fault | bad store address |
| ECALL | `0` |
| EBREAK | current PC |
| Interrupt | `0` |

### Counters: `mcycle`, `cycle`, `minstret`, `instret`

| CSR | Address | Purpose |
|---|---:|---|
| `mcycle` | `0xB00` | Low 32 bits of cycle counter |
| `mcycleh` | `0xB80` | High 32 bits of cycle counter |
| `minstret` | `0xB02` | Low 32 bits of retired-instruction counter |
| `minstreth` | `0xB82` | High 32 bits |
| `cycle` | `0xC00` | Read-only low alias of `mcycle` |
| `cycleh` | `0xC80` | Read-only high alias |
| `instret` | `0xC02` | Read-only low alias of `minstret` |
| `instreth` | `0xC82` | Read-only high alias |

`mcycle` increments every clock after reset. `mtime` also increments every clock. `minstret` increments when `i_csr_unit_instr != 0` and no trap or return is being taken.

### Timers: `mtime`, `mtimecmp`, `stimecmp`

| Register | CSR address | Reset | Purpose |
|---|---:|---:|---|
| `mtime` | Internal only | `0` | Free-running 64-bit time counter |
| `mtimecmp` | `0x30D/0x31D` | `0xFFFF_FFFF_FFFF_FFFF` | Machine timer compare |
| `stimecmp` | `0x14D/0x15D` | `0xFFFF_FFFF_FFFF_FFFF` | Supervisor timer compare |

Timer pending conditions:

```text
MTIP = (mtime >= mtimecmp)
STIP = (mtime >= stimecmp)
```

Timer active conditions also require enables:

```text
MTI active = MTIP && mie.MTIE
STI active = STIP && mie.STIE
```

### ID CSRs

| CSR | Address | Value | Meaning |
|---|---:|---:|---|
| `mvendorid` | `0xF11` | `0` | Non-commercial or unspecified vendor |
| `marchid` | `0xF12` | `0` | Architecture ID unspecified |
| `mimpid` | `0xF13` | `0` | Implementation ID unspecified |
| `mhartid` | `0xF14` | `0` | Single hart ID zero |

### `satp` - Supervisor Address Translation and Protection

| Item | Value |
|---|---|
| Address | `0x180` |
| Reset/read value | `0` |
| Writable? | No functional write |
| Purpose in full RISC-V | Controls virtual memory |
| Purpose here | Declares no translation support |

`satp = 0` means bare physical addressing. This core does not implement page tables, ASIDs, or address translation.

---

## 5. Bitfield Reference

### `mstatus`

```text
31        13 12 11 10 9 8 7 6 5 4 3 2 1 0
+-----------+-----+----+-+-+---+-+-+---+-+-+
| Reserved  | MPP |Res |SPP|MPIE|R|SPIE|R|MIE|R|SIE|R|
+-----------+-----+----+-+-+---+-+-+---+-+-+
```

| Bit(s) | Name | Values | Why it exists |
|---:|---|---|---|
| 1 | `SIE` | `0` disabled, `1` enabled | Global S-mode interrupt gate. |
| 3 | `MIE` | `0` disabled, `1` enabled | Global M-mode interrupt gate. |
| 5 | `SPIE` | saved `SIE` | Lets `sret` restore previous S interrupt state. |
| 7 | `MPIE` | saved `MIE` | Lets `mret` restore previous M interrupt state. |
| 8 | `SPP` | `0` lower mode, `1` S | Lets `sret` restore previous privilege. |
| 12:11 | `MPP` | `00` U, `01` S, `11` M | Lets `mret` restore previous privilege. |

### `sstatus`

```text
31        9 8 7 6 5 4 3 2 1 0
+----------+-+-+-+---+-+-+-+---+
| Reserved |SPP|R|SPIE|R R R|SIE|R|
+----------+-+-+-+---+-+-+-+---+
```

`sstatus` is a projection of `mstatus`. Writing it changes `mstatus[8]`, `mstatus[5]`, and `mstatus[1]`.

### `mie` and `mip`

```text
31                  12 11 10 9 8 7 6 5 4 3 2 1 0
+--------------------+---+--+---+-+---+-+---+-+---+
| Reserved           |ME |R |SE |R|MT |R|ST |R|MS |R|SS|R|
+--------------------+---+--+---+-+---+-+---+-+---+
```

| Bit | `mie` meaning | `mip` meaning |
|---:|---|---|
| 1 | SSIE enable | SSIP pending, not actively sourced here |
| 3 | MSIE enable | MSIP pending, not actively sourced here |
| 5 | STIE enable | STIP = `mtime >= stimecmp` |
| 7 | MTIE enable | MTIP = `mtime >= mtimecmp` |
| 9 | SEIE enable | SEIP = `sexternal` |
| 11 | MEIE enable | MEIP = `mexternal` |

### `mtvec` and `stvec`

```text
31                                      2 1 0
+----------------------------------------+---+
| BASE[31:2]                             |MODE|
+----------------------------------------+---+
```

| Mode | Meaning | Target |
|---:|---|---|
| `00` | Direct | `BASE` |
| `01` | Vectored interrupt | `BASE + 4*cause` for interrupts only |

### `mcause` and `scause`

```text
31 30                                  0
+--+------------------------------------+
|I | CODE                               |
+--+------------------------------------+
```

| `I` | Meaning |
|---:|---|
| `0` | Exception |
| `1` | Interrupt |

### `medeleg` and `mideleg`

Each bit corresponds to a cause code. If a bit is set, and the trap is otherwise eligible, the trap can be routed to S-mode.

```text
bit N == 1 means cause N is delegated to S-mode
```

Common examples:

| Bit | `medeleg` cause | `mideleg` interrupt |
|---:|---|---|
| 3 | Breakpoint | Machine software in full ISA naming |
| 5 | Load access fault | Supervisor timer |
| 7 | Store access fault | Machine timer |
| 9 | ECALL from S-mode | Supervisor external |
| 11 | ECALL from M-mode | Machine external |

### `mepc` and `sepc`

```text
31                                      2 1 0
+----------------------------------------+---+
| Return PC[31:2]                        |00 |
+----------------------------------------+---+
```

Low two bits are forced to zero on software writes.

### `mtimecmp` and `stimecmp`

64-bit split-register layout:

```text
mtimecmp low  : CSR 0x30D = bits [31:0]
mtimecmp high : CSR 0x31D = bits [63:32]
stimecmp low  : CSR 0x14D = bits [31:0]
stimecmp high : CSR 0x15D = bits [63:32]
```

When programming a 64-bit compare register on RV32, write carefully to avoid a temporary compare value that is already less than `mtime`.

---

## 6. CSR Instructions

All CSR instructions use opcode `1110011`. Bits `[31:20]` hold the CSR address. Bits `[14:12]` select the CSR operation.

### Encoding

```text
31        20 19   15 14  12 11    7 6      0
+-----------+-------+------+--------+--------+
| csr[11:0] | rs1/u |funct3| rd     |1110011 |
+-----------+-------+------+--------+--------+
```

| Instruction | `funct3` | RTL `i_csr_unit_op` | Operation |
|---|---:|---:|---|
| `CSRRW` | `001` | `01` | `rd = old; csr = rs1` |
| `CSRRS` | `010` | `10` | `rd = old; csr = old | rs1` |
| `CSRRC` | `011` | `11` | `rd = old; csr = old & ~rs1` |
| `CSRRWI` | `101` | `01` | `rd = old; csr = zext(uimm)` |
| `CSRRSI` | `110` | `10` | `rd = old; csr = old | zext(uimm)` |
| `CSRRCI` | `111` | `11` | `rd = old; csr = old & ~zext(uimm)` |

### Write Suppression Rules

Implemented in Decode:

| Instruction | Write occurs when |
|---|---|
| `CSRRW`, `CSRRWI` | Always |
| `CSRRS`, `CSRRC` | `rs1 != x0` |
| `CSRRSI`, `CSRRCI` | `uimm != 0` |

Read data is available through `o_csr_unit_rdata` and is written back when `ResultSrc = 2'b11`.

### Pipeline Behavior

```text
ID:
  Decode SYSTEM opcode
  Extract csr_addr = instr[31:20]
  Extract op = instr[13:12]
  Detect immediate form from instr[14]
  Apply write-suppression rule

EX:
  Select CSR source:
    register form  -> forwarded RD1E
    immediate form -> {27'b0, uimm[4:0]}

MEM:
  CSR unit checks legality
  CSR unit reads old value
  CSR unit computes write data
  CSR storage updates on clock edge

WB:
  Old CSR value writes to rd through ResultSrcW = 2'b11
```

### Examples

```asm
csrr  t0, mstatus       # alias for csrrs t0, mstatus, x0
csrw  mtvec, t0         # alias for csrrw x0, mtvec, t0
csrs  mie, t0           # set interrupt enable bits
csrc  mie, t0           # clear interrupt enable bits
csrwi mscratch, 31      # write immediate 31
```

Common mistakes:

- `csrrs rd, csr, x0` reads only; it does not set anything.
- `csrrci rd, csr, 0` reads only; it does not clear anything.
- Writing a read-only CSR address range (`csr[11:10] == 2'b11`) with `csr_wen=1` traps as illegal.

---

## 7. Interrupt System

### Interrupt Flow

```text
Raw source
  |
  v
Pending condition (mip/sip)
  |
  v
Individual enable bit in mie/sie
  |
  v
Global enable bit in mstatus/sstatus
  |
  v
Delegation check
  |
  +--> M-mode trap via mtvec
  |
  +--> S-mode trap via stvec
```

### Implemented Interrupts

| Cause value | Name | Pending source | Enable bit | Delegation bit |
|---:|---|---|---|---|
| `0x80000005` | Supervisor timer | `mtime >= stimecmp` | `mie[5]` | `mideleg[5]` |
| `0x80000007` | Machine timer | `mtime >= mtimecmp` | `mie[7]` | `mideleg[7]` checked |
| `0x80000009` | Supervisor external | `sexternal` | `mie[9]` | `mideleg[9]` |
| `0x8000000B` | Machine external | `mexternal` | `mie[11]` | `mideleg[11]` checked |

### Global Enable

Machine interrupts are globally enabled when:

```text
priv_mode < M  OR  (priv_mode == M AND mstatus.MIE == 1)
```

Supervisor interrupts are globally enabled when:

```text
priv_mode < S  OR  (priv_mode == S AND mstatus.SIE == 1)
```

In this core, S-mode interrupts are only considered when current privilege is below M-mode.

### Priority

Machine-routed interrupt priority:

1. Machine external (`MEIP`)
2. Machine timer (`MTIP`)
3. Supervisor external (`SEIP`)
4. Supervisor timer (`STIP`)

Supervisor-routed interrupt priority:

1. Delegated machine external
2. Delegated machine timer
3. Delegated supervisor external
4. Delegated supervisor timer

If both exception and interrupt are active, `take_trap = take_interrupt || exc_active`, and final cause selects interrupt first:

```text
final_cause = take_interrupt ? int_cause : exc_cause
```

### Why Pending and Enable Are Separate

Pending bits are facts about the world. Enable bits are policy. This allows useful cases:

- Timer is pending, but the OS keeps it masked during a critical section.
- External IRQ line is high, but firmware has not enabled it yet.
- A trap handler sees what is pending before deciding what to service.

---

## 8. Exception System

### Exception Priority

The CSR unit checks exceptions in this order:

1. Illegal instruction or illegal CSR access.
2. Instruction address misaligned.
3. ECALL.
4. EBREAK.
5. Store access fault.
6. Load access fault.

### Implemented Exceptions

| Cause | Name | Generated by | `tval` |
|---:|---|---|---|
| 0 | Instruction address misaligned | Taken branch/jump target not word-aligned | Bad target address |
| 2 | Illegal instruction | Decoder illegal, CSR invalid, privilege violation, read-only write | Instruction word |
| 3 | Breakpoint | `ebreak` | Current PC |
| 5 | Load access fault | Load address out of bounds or misaligned | Bad load address |
| 7 | Store access fault | Store address out of bounds or misaligned | Bad store address |
| 9 | ECALL from S-mode | `ecall` while not M-mode | `0` |
| 11 | ECALL from M-mode | `ecall` while M-mode | `0` |

### CSR Illegal Access

CSR illegal access becomes cause `2`, illegal instruction.

Reasons:

| Reason | RTL condition |
|---|---|
| Invalid CSR address | Address not in implemented decode list |
| Privilege violation | `priv_mode_q < csr_addr[9:8]` |
| Read-only CSR write | `csr_addr[11:10] == 2'b11 && csr_wen` |

### Pipeline Behavior

All exceptions are consumed by the CSR unit in the Memory stage. When an exception is taken:

- Trap CSRs update on the next clock edge.
- Fetch is redirected to `mtvec` or `stvec`.
- Pipeline stages are flushed.
- The faulting instruction does not retire.
- `minstret` does not increment for that cycle.

---

## 9. Trap Handling

### Trap Entry Step-by-Step

```text
1. Instruction or interrupt reaches CSR decision point.
2. CSR unit determines:
     - take_interrupt
     - exc_active
     - final_cause
     - trap_to_s
3. Trap target is calculated:
     - mtvec/stvec direct or vectored
4. Redirect outputs assert:
     - o_csr_unit_mux1 = 1
     - o_csr_unit_addr_ctrl = 1
     - flush outputs = 1
5. On clock edge:
     - epc, cause, tval update
     - previous privilege/IE stack updates
     - current privilege changes
6. Fetch begins at handler target.
```

### Trap Entry Flowchart

```text
             +--------------------------+
             | Interrupt or exception?  |
             +------------+-------------+
                          |
                          v
             +--------------------------+
             | Choose final cause       |
             +------------+-------------+
                          |
                          v
             +--------------------------+
             | Delegated to S-mode?     |
             +------+-------------------+
                    | yes           no
                    v               v
             +-------------+   +-------------+
             | use stvec   |   | use mtvec   |
             | save sepc   |   | save mepc   |
             | save scause |   | save mcause |
             | update SIE  |   | update MIE  |
             +------+------+   +------+------+
                    |                 |
                    +--------+--------+
                             v
             +--------------------------+
             | Flush pipeline, redirect |
             +--------------------------+
```

### Direct Mode

If `tvec.MODE != 01`, or the trap is an exception:

```text
target = {tvec[31:2], 2'b00}
```

### Vectored Mode

If `tvec.MODE == 01` and the trap is an interrupt:

```text
target = {tvec[31:2], 2'b00} + 4 * cause
```

The cause used is the low cause number, not including the interrupt MSB.

### Return with MRET

```text
mret in M stage:
  o_csr_unit_mux1      = 1
  o_csr_unit_addr_ctrl = 0
  o_csr_unit_rtrn_addr = mepc
  flush outputs        = 1

on clock:
  priv_mode_q          = MPP
  MIE                  = MPIE
  MPIE                 = 1
  MPP                  = 0
```

### Return with SRET

```text
sret in M stage:
  o_csr_unit_mux1      = 1
  o_csr_unit_addr_ctrl = 0
  o_csr_unit_rtrn_addr = sepc
  flush outputs        = 1

on clock:
  priv_mode_q          = {0, SPP}
  SIE                  = SPIE
  SPIE                 = 1
  SPP                  = 0
```

### Pipeline Flushing

Every trap and return asserts all CSR flush outputs. This prevents wrong-path instructions already in the pipeline from committing after the PC redirect.

---

## 10. Counters and Timers

### `mcycle`

`mcycle_q` is a 64-bit counter. It increments every clock cycle after reset.

Use it to measure:

- Time between two code regions.
- Whether the core is alive.
- Relative performance in simulation.

### `minstret`

`minstret_q` increments when:

```text
i_csr_unit_instr != 0
AND no trap is taken
AND not MRET
AND not SRET
```

This approximates retired instructions but is tied to the M-stage instruction visibility and flush behavior.

### `mtime`

`mtime` increments every clock. It is internal to the CSR unit and is not exposed as a readable CSR in this implementation.

### Timer Interrupts

Machine timer interrupt:

```text
mtime >= mtimecmp
mie.MTIE = 1
mstatus.MIE = 1 if currently in M-mode
```

Supervisor timer interrupt:

```text
mtime >= stimecmp
mie.STIE = 1
mstatus.SIE = 1 if currently in S-mode
delegation allows S routing when appropriate
```

### Real Hardware vs This Core

In many RISC-V systems, `mtime` and `mtimecmp` are memory-mapped timer registers outside the hart. In this core, they are internal CSR-unit registers for simpler simulation and educational integration.

---

## 11. Complete Trap Timelines

### Illegal Instruction

```text
Cycle N-3: IF fetches illegal instruction.
Cycle N-2: ID marks illegal_instr_id_D.
Cycle N-1: EX carries illegal_instr_id_E.
Cycle N:   MEM presents illegal_instr_id_M to CSR unit.
           CSR sets exc_cause = 2, exc_tval = instrM.
           Redirect to mtvec/stvec, flush pipeline.
Cycle N+1: mepc/sepc = PCM, mcause/scause = 2, mtval/stval = instrM.
           Handler fetch begins.
```

### ECALL

```text
Cycle N:   ECALL reaches MEM.
           Cause = 11 if priv_mode_q == M, otherwise 9.
           tval = 0.
           epc = PC of ECALL.
Cycle N+1: Handler starts.
Handler:   Reads cause, increments epc by 4 if it wants to skip ECALL.
Return:    mret/sret returns to programmed epc.
```

### EBREAK

```text
Cycle N:   EBREAK reaches MEM.
           Cause = 3.
           tval = current PC.
           epc = PC of EBREAK.
Cycle N+1: Handler/debug path starts.
```

### Machine Timer Interrupt

```text
Before N:  mtime increments each cycle.
Cycle N:   mtime >= mtimecmp, mie.MTIE = 1, global M interrupts enabled.
           Interrupt cause = 0x80000007.
           tval = 0.
           mepc = current PCM.
           MIE saved to MPIE, MIE cleared.
Cycle N+1: Fetch from mtvec direct or mtvec + 4*7 in vectored mode.
```

### External Interrupt

```text
Cycle N:   mexternal or sexternal is high.
           Corresponding mie bit is set.
           Global interrupt enable permits service.
           Delegation decides mtvec/stvec route.
           irq_ack pulses high.
Cycle N+1: Handler begins and external controller may deassert request.
```

### CSR Illegal Access

```text
Cycle N:   CSR instruction reaches MEM.
           CSR unit checks address, privilege, read-only write.
           If illegal, cause = 2 and tval = instruction word.
           CSR storage is not written.
Cycle N+1: Handler begins at trap vector.
```

---

## 12. Pipeline Interaction

### Why Flushes Are Required

The core is pipelined. When a trap is discovered in MEM, younger instructions may already be in IF, ID, and EX. Those younger instructions belong to the interrupted path and must not commit.

Flush goals:

- Prevent wrong-path register writes.
- Prevent wrong-path memory writes.
- Prevent stale CSR read data from reaching writeback.
- Start fetching from the handler or return PC immediately.

### PC Selection

The top-level PC redirect logic is:

```text
PCTargetE_to_fetch =
  o_csr_unit_mux1
    ? (o_csr_unit_addr_ctrl ? o_csr_unit_irq_handler : o_csr_unit_rtrn_addr)
    : PCTargetE

PCSrcE_to_fetch = PCSrcE || o_csr_unit_mux1
```

Interpretation:

| `o_csr_unit_mux1` | `o_csr_unit_addr_ctrl` | PC target |
|---:|---:|---|
| 0 | X | Normal branch/jump target or PC+4 |
| 1 | 1 | Trap handler `mtvec/stvec` |
| 1 | 0 | Return address `mepc/sepc` |

### Hazards

CSR instructions write their read result in WB, like ALU/load results. The normal forwarding and hazard machinery should be considered when a following instruction consumes the destination register.

Trap/return redirect overrides stalls:

```text
enable_pc = !StallF || o_csr_unit_mux1
```

This ensures a trap or return can redirect the PC even if a data hazard would otherwise stall fetch.

---

## 13. Complete Signal Reference

### CSR Unit Inputs

| Signal | Direction | Width | Producer | Consumer | Purpose | Example |
|---|---|---:|---|---|---|---|
| `i_csr_unit_clk` | input | 1 | Top | CSR FFs | State clock | Counter increments |
| `i_csr_unit_rst_n` | input | 1 | Top | CSR FFs | Async reset | Boot to M-mode |
| `i_csr_unit_mexternal` | input | 1 | External system | IRQ detector | Machine external pending | PLIC request |
| `i_csr_unit_sexternal` | input | 1 | External system | IRQ detector | Supervisor external pending | S-level IRQ |
| `i_csr_unit_mem_wen` | input | 1 | Memory pipeline | Currently unused | Store write indication | Future fault gating |
| `i_csr_unit_pc` | input | 32 | `PCM` | Trap entry | Faulting/interrupted PC | Saved to `mepc` |
| `i_csr_unit_fault_addr` | input | 32 | `ALUResultM` | Exception decoder | Bad memory/target address | Saved to `mtval` |
| `i_csr_unit_instr` | input | 32 | `instrM` | Exception/counter | Faulting instruction | Illegal `tval` |
| `i_csr_unit_csr_wen` | input | 1 | Decode/EX/MEM | CSR write gate | Enables CSR update | `csrw mtvec,t0` |
| `i_csr_unit_op` | input | 2 | Decode/EX/MEM | CSR write datapath | RW/RS/RC operation | `2'b10` for set |
| `i_csr_unit_src` | input | 32 | Execute stage | CSR write datapath | Write mask/data | `0x80` |
| `i_csr_unit_csr_addr` | input | 12 | Decode/EX/MEM | CSR decoders | Target CSR address | `12'h305` |
| `i_csr_unit_illegal_instr_id` | input | 1 | Decode path | Exception decoder | Illegal instruction | Bad opcode |
| `i_csr_unit_illegal_instr_exe` | input | 1 | Tied low | Exception decoder | Reserved illegal source | Future use |
| `i_csr_unit_instr_addr_misaligned` | input | 1 | Execute path | Exception decoder | Misaligned target | Jump to `0x...02` |
| `i_csr_unit_lw_access_fault` | input | 1 | Memory stage | Exception decoder | Load fault | Misaligned/out-of-range |
| `i_csr_unit_sw_access_fault` | input | 1 | Memory stage | Exception decoder | Store fault | Misaligned/out-of-range |
| `i_csr_unit_mret_wb` | input | 1 | SYSTEM decode path | Return logic | MRET active | Return via `mepc` |
| `i_csr_unit_ecall` | input | 1 | SYSTEM decode path | Exception decoder | ECALL active | Cause 11 or 9 |
| `i_csr_unit_ebreak` | input | 1 | SYSTEM decode path | Exception decoder | EBREAK active | Cause 3 |
| `i_csr_unit_sret` | input | 1 | SYSTEM decode path | Return logic | SRET active | Return via `sepc` |

### CSR Unit Outputs

| Signal | Direction | Width | Producer | Consumer | Purpose | Example |
|---|---|---:|---|---|---|---|
| `o_csr_unit_ack` | output | 1 | CSR IRQ logic | Top `irq_ack` | Interrupt accepted pulse | Clear external request |
| `o_csr_unit_rdata` | output | 32 | CSR read mux | `CSRRDataW` latch | Old CSR value | `csrr t0,mcause` |
| `o_csr_unit_irq_handler` | output | 32 | Trap target logic | Fetch PC mux | Handler PC | `mtvec` base |
| `o_csr_unit_rtrn_addr` | output | 32 | Return router | Fetch PC mux | Return PC | `mepc` on MRET |
| `o_csr_unit_addr_ctrl` | output | 1 | Trap logic | Fetch PC mux | Select handler vs return | `1` on trap |
| `o_csr_unit_mux1` | output | 1 | Trap/return logic | Fetch PC mux | Override normal PC | Trap or return |
| `o_csr_unit_if_flush` | output | 1 | Redirect logic | Redundant | Flush indication | Same as mux1 |
| `o_csr_unit_id_flush` | output | 1 | Redirect logic | Fetch stage CLR | Clear IF/ID | Trap flush |
| `o_csr_unit_exe_flush` | output | 1 | Redirect logic | Decode/Execute CLR | Clear ID/EX and EX/MEM | Trap flush |
| `o_csr_unit_mem_flush` | output | 1 | Redirect logic | Memory/WB CLR | Clear WB path | Trap flush |

---

## 14. State Transition Diagrams

### Privilege Transitions

```text
Reset
  |
  v
+---------+
| M-mode  |
+----+----+
     | delegated trap from lower mode
     v
+---------+        trap not delegated / M trap
| S-mode  | --------------------------------+
+----+----+                                 |
     | sret                                v
     v                               +---------+
 lower/S previous mode <-------------| M-mode  |
                                     +----+----+
                                          |
                                          | mret
                                          v
                                     MPP-selected mode
```

### Trap Entry

```text
Normal execution
  |
  v
Trap condition detected
  |
  v
Cause/tval selected
  |
  v
Delegation?
  | yes                         no
  v                             v
Save sepc/scause/stval          Save mepc/mcause/mtval
Update SPP/SPIE/SIE             Update MPP/MPIE/MIE
priv = S                        priv = M
  |                             |
  +-------------+---------------+
                v
        Fetch from stvec/mtvec
```

### Interrupt Handling

```text
pending source -> enable bit -> global enable -> delegation -> vector target
```

### Exception Handling

```text
faulting instruction -> priority encoder -> cause/tval -> delegation -> trap CSRs -> vector target
```

---

## 15. Typical Execution Examples

### CSRRW

```asm
li    x1, 0x55
csrrw x2, mscratch, x1
```

Expected behavior:

```text
x2 receives old mscratch
mscratch receives 0x55
No trap if running in M-mode
```

### ECALL

```asm
la   t0, handler
csrw mtvec, t0
ecall

handler:
  csrr t1, mcause
  csrr t2, mepc
  addi t2, t2, 4
  csrw mepc, t2
  mret
```

Expected state on trap:

```text
mcause = 11 in M-mode
mepc   = PC of ecall
mtval  = 0
```

### EBREAK

```asm
ebreak
```

Expected:

```text
mcause/scause = 3
mtval/stval   = PC of ebreak
```

### Timer Interrupt

```asm
# Program mtimecmp low/high to a future time
li   t0, 1000
csrw 0x30D, t0
li   t0, 0
csrw 0x31D, t0

li   t0, (1 << 7)
csrs mie, t0
li   t0, (1 << 3)
csrs mstatus, t0
```

When `mtime >= mtimecmp`, the core takes cause `0x80000007`.

### Machine External Interrupt

```text
mexternal = 1
mie.MEIE = 1
mstatus.MIE = 1
mideleg.MEIE = 0
```

Trap target is `mtvec`, cause is `0x8000000B`, and `irq_ack` pulses.

### Supervisor Interrupt

```text
sexternal = 1
mie.SEIE = 1
mideleg.SEIE = 1
current privilege below M-mode
sstatus.SIE = 1 if currently S-mode
```

Trap target is `stvec`, cause is `0x80000009`.

### Illegal CSR Access

```asm
csrw mvendorid, t0
```

If `csr_wen` is asserted, this is a write to a read-only CSR address range and traps as illegal instruction:

```text
mcause = 2
mtval  = instruction word
```

### Store Fault

```asm
sw t0, 2(t1)          # misaligned word store if address low bits are not 00
```

Expected:

```text
cause = 7
tval  = bad store address
```

### Load Fault

```asm
lw t0, 2(t1)          # misaligned word load
```

Expected:

```text
cause = 5
tval  = bad load address
```

---

## 16. Debugging Guide

### What to Inspect First

For any trap bug, inspect in this order:

1. `o_csr_unit_mux1`: Did the CSR unit request a redirect?
2. `o_csr_unit_addr_ctrl`: Was it a trap (`1`) or return (`0`)?
3. `o_csr_unit_irq_handler`: Is the handler PC correct?
4. `mepc/sepc`: Was the correct faulting PC saved?
5. `mcause/scause`: Is the cause code expected?
6. `mtval/stval`: Does it contain the expected instruction/address?
7. `mstatus`: Did `MIE/SIE`, `MPIE/SPIE`, and `MPP/SPP` update correctly?

### Wrong Trap Target

Check:

- Is `mtvec/stvec` initialized?
- Are low bits `[1:0]` accidentally setting vectored mode?
- For vectored mode, is the trap an interrupt? Exceptions still go to base.
- Is the trap delegated unexpectedly?

### Wrong Privilege

Check:

- `priv_mode_q` before trap.
- `medeleg/mideleg` bits.
- `mstatus.MPP` or `mstatus.SPP` after trap entry.
- Whether `mret/sret` restored from the expected stack field.

### Missing Interrupt

Check all four gates:

```text
pending source exists?
individual mie bit set?
global mstatus bit set?
delegation/current privilege permits route?
```

For timer interrupts, also check:

- `mtimecmp/stimecmp` are programmed below or equal to `mtime`.
- High/low halves were written in a safe order.
- The compare register did not reset to all ones.

### Wrong `mcause`

Check priority. Illegal instruction/CSR illegal wins before misaligned, ECALL, EBREAK, store fault, and load fault.

### CSR Write Did Not Happen

Check:

- `csr_wenM` is high.
- Write-suppression rule did not suppress `CSRRS/CSRRC` with `rs1=x0`.
- Address is valid.
- Current privilege is high enough.
- CSR is not read-only.
- The field is actually writable in this RTL. For example, `mstatus` writes only selected bits.

### Common RTL Mistakes

| Symptom | Likely cause |
|---|---|
| Trap loops forever on ECALL | Handler did not add 4 to `mepc`. |
| Timer interrupt never fires | `mstatus.MIE` or `mie.MTIE` is clear. |
| S-mode handler never runs | Delegation bit not set or current mode is M. |
| CSR read returns zero | `csr_op` is `00`, address invalid, or access illegal. |
| Illegal CSR does not trap | `csr_instr_active`/`csr_op` not carried into M stage. |
| Store fault still writes memory | Store write enable not gated by fault/flush. This core gates it. |
| `mret` returns to zero | `mepc` was never written or was flushed/reset. |

---

## 17. CSR Cheat Sheet

| Register | Address | Purpose | Who writes it | Who reads it | Modified by hardware | Important bits | Reset |
|---|---:|---|---|---|---|---|---:|
| `mstatus` | `0x300` | M status/priv stack | M software | Firmware/handlers | Trap, MRET, SRET | MIE, MPIE, MPP, SIE, SPIE, SPP | `0` |
| `sstatus` | `0x100` | S view of status | S/M software | S handlers | Trap, SRET through `mstatus` | SIE, SPIE, SPP | `0` |
| `misa` | `0x301` | ISA report | Hardware constant | Software | No | MXL, extensions | constant |
| `mie` | `0x304` | Interrupt enables | M software | IRQ logic/software | Reset | bits 5,7,9,11 | `0` |
| `mip` | `0x344` | Interrupt pending | Hardware computed | Software/IRQ logic | Dynamic | bits 5,7,9,11 | dynamic |
| `mtvec` | `0x305` | M trap vector | M software | Trap router | Reset | BASE, MODE | `0` |
| `stvec` | `0x105` | S trap vector | S/M software | Trap router | Reset | BASE, MODE | `0` |
| `medeleg` | `0x302` | Exception delegation | M software | Trap router | Reset | cause bits | `0` |
| `mideleg` | `0x303` | Interrupt delegation | M software | Trap router | Reset | IRQ cause bits | `0` |
| `mscratch` | `0x340` | M scratch | M software | M software | Reset | all bits | `0` |
| `sscratch` | `0x140` | S scratch | S/M software | S software | Reset | all bits | `0` |
| `mepc` | `0x341` | M return PC | M software | MRET/handlers | M trap | aligned PC | `0` |
| `sepc` | `0x141` | S return PC | S/M software | SRET/handlers | S trap | aligned PC | `0` |
| `mcause` | `0x342` | M trap cause | M software | Handlers | M trap | interrupt bit, code | `0` |
| `scause` | `0x142` | S trap cause | S/M software | Handlers | S trap | interrupt bit, code | `0` |
| `mtval` | `0x343` | M trap value | M software | Handlers | M trap | bad instr/address | `0` |
| `stval` | `0x143` | S trap value | S/M software | Handlers | S trap | bad instr/address | `0` |
| `mcycle` | `0xB00/B80` | Cycle count | M software | Software | Every clock | 64-bit split | `0` |
| `minstret` | `0xB02/B82` | Retired instructions | M software | Software | Valid commits | 64-bit split | `0` |
| `mtime` | internal | Timer count | Hardware | Timer compare | Every clock | 64-bit | `0` |
| `mtimecmp` | `0x30D/31D` | M timer compare | M software | Timer logic | Reset | 64-bit split | all ones |
| `stimecmp` | `0x14D/15D` | S timer compare | S/M software | Timer logic | Reset | 64-bit split | all ones |
| `mvendorid` | `0xF11` | Vendor ID | constant | Software | No | all zero | `0` |
| `marchid` | `0xF12` | Arch ID | constant | Software | No | all zero | `0` |
| `mimpid` | `0xF13` | Impl ID | constant | Software | No | all zero | `0` |
| `mhartid` | `0xF14` | Hart ID | constant | Software | No | all zero | `0` |
| `satp` | `0x180` | Address translation | constant zero | Software | No | mode=bare | `0` |

---

## 18. Common Interview Questions

### What is a CSR?

A CSR is a Control and Status Register: a special architectural register used to configure processor behavior or report processor state. In RISC-V, CSRs control trap vectors, interrupt enables, privilege state, counters, and machine identity.

### Why are CSRs separate from integer registers?

Integer registers hold program data. CSRs hold privileged architectural state. Separating them lets the ISA enforce access permissions and define special side effects such as trap entry and interrupt masking.

### What happens on trap entry?

The core saves the faulting/interrupted PC into `mepc` or `sepc`, saves the cause into `mcause` or `scause`, writes `mtval/stval`, saves previous privilege and interrupt-enable bits in `mstatus`, disables the relevant global interrupt enable, changes privilege mode, flushes the pipeline, and redirects fetch to `mtvec` or `stvec`.

### What is the difference between an interrupt and an exception?

An exception is synchronous and caused by the current instruction, such as illegal instruction or load fault. An interrupt is asynchronous and caused by an external or timer event. Both are traps and use similar entry machinery.

### Why does `mcause[31]` exist?

It distinguishes interrupts from exceptions. If bit 31 is set in RV32, the trap is an interrupt. The lower bits hold the cause code.

### Why does trap entry clear `MIE` or `SIE`?

To prevent uncontrolled nested interrupts while the trap handler is saving state. The previous enable is saved into `MPIE` or `SPIE` so return instructions can restore it.

### What does `mret` restore?

`mret` restores privilege from `mstatus.MPP`, restores `MIE` from `MPIE`, sets `MPIE` to 1, clears `MPP`, and redirects the PC to `mepc`.

### What is delegation?

Delegation lets M-mode choose which traps from lower privilege levels are handled directly by S-mode. Exceptions use `medeleg`; interrupts use `mideleg`.

### Why might an interrupt be pending but not taken?

Its individual enable bit may be clear, the global enable bit may be clear, the core may be in a privilege mode that masks it, or delegation/current privilege may prevent that route from being active.

### What is the difference between `mtvec` direct and vectored modes?

In direct mode, all traps go to the base address. In vectored mode, interrupts go to `BASE + 4*cause`, while exceptions still go to `BASE`.

### Why does an illegal CSR access raise illegal instruction?

RISC-V defines invalid CSR access, insufficient privilege, and illegal writes to read-only CSR addresses as illegal instruction exceptions. This prevents unprivileged or incorrect software from silently modifying privileged state.

### Why must an ECALL handler increment `mepc`?

Trap entry saves the PC of the trapping instruction, not the next instruction. If the handler returns without changing `mepc`, the same ECALL executes again and traps forever.

### What is `mtval` for?

`mtval` gives extra trap information. For illegal instruction, it contains the instruction word. For memory and address faults, it contains the bad address. For interrupts, it is zero.

### How do you enable a machine timer interrupt?

Program `mtimecmp` to a future value, set `mie.MTIE`, set `mstatus.MIE`, and install a valid `mtvec` handler.

### What is the most common CSR debug checklist?

Check handler vector, cause, epc, tval, global enable, individual enable, pending bit, delegation bit, privilege mode, and pipeline flush/redirect signals.
