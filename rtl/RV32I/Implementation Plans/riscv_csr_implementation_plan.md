# RISC-V Zicsr Implementation Plan
## Complete Engineering Guide for the RISCV-MicroKernel-Architecture 5-Stage Pipelined RV32I Core

---

## Table of Contents

1. [Design Philosophy and Incremental Strategy](#philosophy)
2. [Phase 0 — Audit and Preparation](#phase0)
3. [Phase 1 — CSR File Infrastructure + CSRRW/CSRRS/CSRRC](#phase1)
4. [Phase 2 — Immediate Variants + Suppression Rules](#phase2)
5. [Phase 3 — Read-Only CSRs and Illegal-Address Detection](#phase3)
6. [Phase 4 — Performance Counters (mcycle / minstret)](#phase4)
7. [Phase 5 — Minimal M-Mode CSRs (mstatus, mtvec, mscratch, mepc, mcause, mtval)](#phase5)
8. [CSR Address Map Reference](#csrmap)
9. [Forwarding and Hazard Reference](#hazard)

---

## 1. Design Philosophy and Incremental Strategy {#philosophy}

### Why incremental?

Building the entire CSR subsystem in one pass is the fastest route to a core you cannot debug.
Each phase below produces a *testable artifact* — a core that compiles, simulates, and passes
a defined set of assertions before you move forward. Never add new logic on top of untested logic.

### Constraint summary

- Every phase adds exactly one category of behaviour.
- Each phase ends with a verification checkpoint. Do not proceed until it passes.
- M-mode CSRs are introduced only when an instruction or counter explicitly requires them.
- No S-mode, U-mode, or privilege-level register until Phase 5 and beyond.
- The CSR file is a dedicated module. It is never merged into `riscv_register_file.sv`.

### Architecture overview (final target of all five phases)

```
         ┌──────────────────────────────────────────────────────────────────┐
         │                    riscv_top_pipeline.sv                         │
         │                                                                  │
         │  riscv_fetch_stage  →  riscv_decode_stage  →  riscv_execute_stage│
         │         ↓                      ↓                      ↓          │
         │  [IF/ID latched]        [ID/EX latched]       riscv_csr_file.sv  │
         │                         csr_addr, csr_op            ↓            │
         │                         csr_imm_sel, csr_uimm   CSRRDataE ──────►│
         │                                                  (→ EX/MEM       │
         │                                                   → MEM/WB       │
         │                                                   → WB mux ──►rd)│
         │  riscv_memory_stage  ←──────────────────────────────────────────│
         │         ↓                                                         │
         │  WB mux_3_1 (ResultSrcW):                                         │
         │    00 → ALUResultW,  01 → ReadDataW,  10 → PCPlus4W              │
         │    NEW: 11 → CSRRDataW  (CSR read result)                         │
         └──────────────────────────────────────────────────────────────────┘
```

**Key design facts about this core:**
- Pipeline registers are implemented as **flat individual signals** passed between stage modules (not packed structs). New CSR fields must be added as new ports and wires in `riscv_top_pipeline.sv` and propagated through the relevant stage modules.
- The WB mux is `riscv_mux_3_1` driven by `ResultSrcW[1:0]`. Currently: `00`=`ALUResultW`, `01`=`ReadDataW`, `10`=`PCPlus4W`. CSR adds a 4th source — the mux must be extended to `riscv_mux_4_1` or encoded with `ResultSrcW = 2'b11` for `CSRRDataW`.
- Forwarded rs1 for EX is `mux_R1_out` (output of `riscv_mux_3_1 mux_alu_1`).
- The control unit (`riscv_control_unit.sv`) already stubs `is_system_instr` for opcode `7'b1110011` — CSR decode will build on top of this.
- `riscv_extend.sv` must NOT be used for CSR uimm — uimm is zero-extended only and the extend unit does sign-extension.

---

## 2. Phase 0 — Audit and Preparation {#phase0}

### 2.1 Goal

Understand exactly what the current core has so you know what every subsequent phase is adding.
Produce a gap list. Do not write any new RTL yet.

### 2.2 What to audit

**Instruction encoding space**
The existing decode logic in `riscv_control_unit.sv` handles opcodes:
`0110011` (R), `0010011` (OP-IMM), `0000011` (LOAD), `0100011` (STORE),
`1100011` (BRANCH), `1101111` (JAL), `1100111` (JALR), `0110111` (LUI), `0010111` (AUIPC).
The opcode `1110011` (SYSTEM) already has a stub case that sets `is_system_instr = 1'b1`
but has no further decode. All six CSR instructions live in this opcode.

**Pipeline register checklist**
Your flat pipeline signals (verified from the source files):
- `riscv_fetch_stage` → `riscv_decode_stage`: `instrD`, `PCPlus4D`, `PCD`
- ID/EX (latched inside `riscv_decode_stage`, output as `*E` ports):
  `PCE`, `PCPlus4E`, `RegWriteE`, `ResultSrcE[1:0]`, `MemWriteE`, `jumpE`,
  `Branch_takenE[2:0]`, `BranchE`, `ALUControlE[2:0]`, `ALUSrcE`,
  `RD1E`, `RD2E`, `ImmExtE`, `RdE[4:0]`, `Rs1E[4:0]`, `Rs2E[4:0]`,
  `funct3E[2:0]`, `ImmPassE[1:0]`, `inst_typeE`, `jalr_pcE`
- EX/MEM (latched inside `riscv_execute_stage`, output as `*M` ports):
  `RegWriteM`, `ResultSrcM[1:0]`, `MemWriteM`, `ALUResultM`, `WriteDataM`,
  `RdM[4:0]`, `PCPlus4M`, `funct3M[2:0]`
- MEM/WB (latched inside `riscv_memory_stage`, output as `*W` ports):
  `RegWriteW`, `ResultSrcW[1:0]`, `RdW[4:0]`, `ALUResultW`, `ReadDataW`, `PCPlus4W`

**WB mux**
Currently `riscv_mux_3_1 mux_w(.A(ALUResultW), .B(ReadDataW), .C(PCPlus4W), .Sel(ResultSrcW), .out(result))`.
CSR adds a 4th writeback source. You will replace this with a `riscv_mux_4_1` or change
encoding so that `ResultSrcW = 2'b11` selects `CSRRDataW`.

**Hazard unit inputs/outputs** (from `riscv_hazard_unit.sv`):
- Inputs: `Rs1E`, `Rs2E`, `RdM`, `RdW`, `RegWriteM`, `RegWriteW`, `ResultSrcE_0`, `RdE`, `Rs1D`, `Rs2D`, `PCSrcE`
- Outputs: `FlushE`, `StallD`, `StallF`, `ForwardAE[1:0]`, `ForwardBE[1:0]`, `FlushD`
- `lwStall = ResultSrcE_0 & ((Rs1D == RdE) | (Rs2D == RdE))`
- `StallF = lwStall`, `StallD = lwStall`
- You will add: `csr_pipeline_stall` ORed into `StallF` and `StallD`

**`is_system_instr` signal**
Already decoded in `riscv_control_unit.sv` (line 107) and already passed through
`riscv_decode_stage.sv`? **Check this.** If not yet wired through to EX, you will need to
add it as a new port. Currently it appears unused beyond decode — Phase 1 will give it purpose.

### 2.3 New files to create

```
rtl/RV32I/
├── riscv_csr_file.sv        ← Phase 1: the CSR register file
├── riscv_csr_defines.svh    ← Phase 0: address constants and opcode macros
├── riscv_csr_execute.sv     ← Phase 1: read-modify-write logic
└── riscv_mux_4_1.sv         ← Phase 1: 4-to-1 mux to replace WB mux_3_1
```

### 2.4 Defines file (create now)

```systemverilog
// riscv_csr_defines.svh
`ifndef RISCV_CSR_DEFINES_SVH
`define RISCV_CSR_DEFINES_SVH

// ── CSR Addresses ────────────────────────────────────────────────────────────
// Machine-mode information (read-only)
`define CSR_MVENDORID   12'hF11
`define CSR_MARCHID     12'hF12
`define CSR_MIMPID      12'hF13
`define CSR_MHARTID     12'hF14
`define CSR_MCONFIGPTR  12'hF15

// Machine-mode setup
`define CSR_MSTATUS     12'h300
`define CSR_MISA        12'h301
`define CSR_MIE         12'h304
`define CSR_MTVEC       12'h305

// Machine-mode trap handling
`define CSR_MSCRATCH    12'h340
`define CSR_MEPC        12'h341
`define CSR_MCAUSE      12'h342
`define CSR_MTVAL       12'h343
`define CSR_MIP         12'h344

// Machine-mode counters (writeable)
`define CSR_MCYCLE      12'hB00
`define CSR_MINSTRET    12'hB02
`define CSR_MCYCLEH     12'hB80
`define CSR_MINSTRETH   12'hB82

// User-mode counter mirrors (read-only)
`define CSR_CYCLE       12'hC00
`define CSR_INSTRET     12'hC02
`define CSR_CYCLEH      12'hC80
`define CSR_INSTRETH    12'hC82

// ── CSR Operation Codes (from funct3) ────────────────────────────────────────
`define CSR_OP_RW   3'b001   // CSRRW
`define CSR_OP_RS   3'b010   // CSRRS
`define CSR_OP_RC   3'b011   // CSRRC
`define CSR_OP_RWI  3'b101   // CSRRWI
`define CSR_OP_RSI  3'b110   // CSRRSI
`define CSR_OP_RCI  3'b111   // CSRRCI

// ── Instruction Decode Helpers ────────────────────────────────────────────────
`define OPCODE_SYSTEM   7'b1110011

// ── mstatus field positions ───────────────────────────────────────────────────
`define MSTATUS_MIE_BIT  3
`define MSTATUS_MPIE_BIT 7

// ── mcause MSB (interrupt flag) ───────────────────────────────────────────────
`define MCAUSE_INT_BIT   31

// ── ResultSrc encoding (WB mux select) ───────────────────────────────────────
// Extended from 2'b00..10 to include 2'b11 for CSR read data
`define RESULTSRC_ALU   2'b00
`define RESULTSRC_MEM   2'b01
`define RESULTSRC_PC4   2'b10
`define RESULTSRC_CSR   2'b11

`endif // RISCV_CSR_DEFINES_SVH
```

---

## 3. Phase 1 — CSR File Infrastructure + CSRRW/CSRRS/CSRRC {#phase1}

### 3.1 Goal

Add the CSR file module, the execute-stage read-modify-write logic, and decode support for the
three register-source CSR instructions (CSRRW, CSRRS, CSRRC). After this phase, code can read
and write the scratch register `mscratch` (0x340) and arbitrary test registers.

### 3.2 Why this phase

These three instructions share identical encoding structure, differing only in funct3[1:0].
Implementing them first lets you build and validate the full datapath — new execute path,
new writeback source, new pipeline register fields — before adding the complexity of
immediate operands and suppression rules in Phase 2.

### 3.3 Spec reference

RISC-V Unprivileged Spec, Chapter 6, Section 6.1, pages 47–48.
Specifically: CSRRW behaviour (read old, write rs1), CSRRS (set bits), CSRRC (clear bits).
For mscratch: Privileged Spec Vol II, Section 3.1.7.

### 3.4 New hardware blocks

#### 3.4.1 `riscv_csr_file.sv`

This module is instantiated directly in `riscv_top_pipeline.sv`, not inside any stage module.
Its read port (combinational `CSRRDataE`) is driven by the `csr_addrE` wire, which carries
`instrD[31:20]` latched through the ID/EX boundary.

```systemverilog
`include "riscv_csr_defines.svh"

module riscv_csr_file (
    input  logic        clk,
    input  logic        rst_n,

    // ── Software access port (driven from EX stage signals in riscv_top_pipeline) ──
    input  logic [11:0] csr_addrE,     // CSR address: instrD[31:20] latched to EX
    input  logic [31:0] csr_wdataE,    // new value computed by riscv_csr_execute
    input  logic        csr_weE,       // write enable (gated by suppression logic)
    output logic [31:0] CSRRDataE,     // old value before write → propagated to rd via WB
    output logic        csr_illegal,   // 1 = undefined address → illegal instruction

    // ── Hardware update ports (Phase 4/5 connect these; tie to 0 for Phases 1–3) ──
    input  logic        trap_we,
    input  logic [31:0] trap_mepc,
    input  logic [31:0] trap_mcause,
    input  logic [31:0] trap_mtval,
    input  logic        mret_we,       // pulsed on MRET (Phase 5)
    input  logic        instret_inc,   // pulsed from WB stage valid (Phase 4)

    // ── CSR outputs visible to control/trap logic ──────────────────────────────
    output logic [31:0] mstatus_out,
    output logic [31:0] mtvec_out,
    output logic [31:0] mepc_out,
    output logic [31:0] mcause_out
);

    // ── CSR storage registers ─────────────────────────────────────────────────
    logic [31:0] mscratch_q;
    logic [31:0] mstatus_q;
    logic [31:0] misa_q;
    logic [31:0] mtvec_q;
    logic [31:0] mepc_q;
    logic [31:0] mcause_q;
    logic [31:0] mtval_q;
    logic [31:0] mie_q;
    logic [63:0] mcycle_q;         // 64-bit; split over two CSR addresses
    logic [63:0] minstret_q;       // 64-bit; split over two CSR addresses

    // ── Combinational read multiplexer ────────────────────────────────────────
    always_comb begin
        CSRRDataE   = 32'h0;
        csr_illegal = 1'b0;
        unique case (csr_addrE)
            `CSR_MHARTID  : CSRRDataE = 32'h0;           // single hart, always 0
            `CSR_MVENDORID: CSRRDataE = 32'h0;           // non-commercial
            `CSR_MARCHID  : CSRRDataE = 32'h0;
            `CSR_MIMPID   : CSRRDataE = 32'h0;
            `CSR_MISA     : CSRRDataE = misa_q;
            `CSR_MSTATUS  : CSRRDataE = mstatus_q;
            `CSR_MIE      : CSRRDataE = mie_q;
            `CSR_MTVEC    : CSRRDataE = mtvec_q;
            `CSR_MSCRATCH : CSRRDataE = mscratch_q;
            `CSR_MEPC     : CSRRDataE = mepc_q;
            `CSR_MCAUSE   : CSRRDataE = mcause_q;
            `CSR_MTVAL    : CSRRDataE = mtval_q;
            `CSR_MCYCLE   : CSRRDataE = mcycle_q[31:0];
            `CSR_MCYCLEH  : CSRRDataE = mcycle_q[63:32];
            `CSR_MINSTRET : CSRRDataE = minstret_q[31:0];
            `CSR_MINSTRETH: CSRRDataE = minstret_q[63:32];
            // User-mode read-only mirrors
            `CSR_CYCLE    : CSRRDataE = mcycle_q[31:0];
            `CSR_CYCLEH   : CSRRDataE = mcycle_q[63:32];
            `CSR_INSTRET  : CSRRDataE = minstret_q[31:0];
            `CSR_INSTRETH : CSRRDataE = minstret_q[63:32];
            default: begin
                CSRRDataE   = 32'h0;
                csr_illegal = 1'b1;
            end
        endcase
    end

    // ── Sequential write logic ────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mscratch_q <= 32'h0;
            mstatus_q  <= 32'h0;
            misa_q     <= 32'h40001100;  // MXL=1(RV32), I-bit set
            mtvec_q    <= 32'h0;
            mepc_q     <= 32'h0;
            mcause_q   <= 32'h0;
            mtval_q    <= 32'h0;
            mie_q      <= 32'h0;
            mcycle_q   <= 64'h0;
            minstret_q <= 64'h0;
        end else begin
            // ── Hardware: cycle counter always increments ─────────────────────
            mcycle_q <= mcycle_q + 64'h1;

            // ── Hardware: trap entry (Phase 5 will wire these properly) ───────
            if (trap_we) begin
                mepc_q   <= trap_mepc;
                mcause_q <= trap_mcause;
                mtval_q  <= trap_mtval;
            end

            // ── Hardware: instret increment from WB (Phase 4) ─────────────────
            if (instret_inc)
                minstret_q <= minstret_q + 64'h1;

            // ── Software: CSR write from pipeline ─────────────────────────────
            if (csr_weE) begin
                unique case (csr_addrE)
                    `CSR_MSCRATCH : mscratch_q <= csr_wdataE;
                    `CSR_MSTATUS  : mstatus_q  <= csr_wdataE & 32'h0000_0008; // Phase 1: MIE only
                    `CSR_MIE      : mie_q      <= csr_wdataE & 32'h0000_0888;
                    `CSR_MTVEC    : mtvec_q    <= {csr_wdataE[31:2], 1'b0, csr_wdataE[0]};
                    `CSR_MEPC     : mepc_q     <= {csr_wdataE[31:2], 2'b00}; // 4-byte aligned
                    `CSR_MCAUSE   : mcause_q   <= csr_wdataE;
                    `CSR_MTVAL    : mtval_q    <= csr_wdataE;
                    `CSR_MCYCLE   : mcycle_q[31:0]    <= csr_wdataE;
                    `CSR_MCYCLEH  : mcycle_q[63:32]   <= csr_wdataE;
                    `CSR_MINSTRET : minstret_q[31:0]  <= csr_wdataE;
                    `CSR_MINSTRETH: minstret_q[63:32] <= csr_wdataE;
                    default: ; // writes to undefined or read-only CSRs are silently ignored
                endcase
            end
        end
    end

    // ── Output assignments ────────────────────────────────────────────────────
    assign mstatus_out = mstatus_q;
    assign mtvec_out   = mtvec_q;
    assign mepc_out    = mepc_q;
    assign mcause_out  = mcause_q;

endmodule
```

**WARL mask for mstatus (RV32I M-mode only):**
- bit 3  = MIE  (writeable)
- bit 7  = MPIE (writeable)
- bits 12:11 = MPP (Phase 5)
Phase 1: use mask `32'h0000_0008` (MIE only). Phase 5: expand to `32'h0000_1888`.

#### 3.4.2 `riscv_csr_execute.sv`

This module is instantiated in `riscv_top_pipeline.sv` (EX stage level). It receives
`mux_R1_out` (the forwarded rs1 value) and computes the new CSR value from the old value.

```systemverilog
`include "riscv_csr_defines.svh"

module riscv_csr_execute (
    input  logic [31:0] CSRRDataE,     // old value read from CSR file (combinational)
    input  logic [31:0] mux_R1_out,    // forwarded rs1 value from riscv_mux_3_1 mux_alu_1
    input  logic [2:0]  funct3E,       // funct3 field = CSR operation
    input  logic        csr_imm_selE,  // 1 = use uimm[4:0] (from funct3E[2])
    input  logic [4:0]  csr_uimm E,   // zero-extended 5-bit immediate (= instrD[19:15] latched)

    output logic [31:0] csr_wdataE,    // new value to write into CSR
    output logic        do_csr_read,   // 1 if instruction reads CSR
    output logic        do_csr_write   // 1 if instruction writes CSR
);

    logic [31:0] operand;

    // Select operand: register (forwarded rs1) or zero-extended immediate
    assign operand = csr_imm_selE ? {27'b0, csr_uimm E} : mux_R1_out;

    // Compute new value
    always_comb begin
        unique case (funct3E[1:0])
            2'b01: csr_wdataE = operand;                    // RW:  replace
            2'b10: csr_wdataE = CSRRDataE | operand;        // RS:  set bits
            2'b11: csr_wdataE = CSRRDataE & (~operand);     // RC:  clear bits
            default: csr_wdataE = 32'h0;
        endcase
    end

    // Phase 1: always read and write (suppression added in Phase 2)
    assign do_csr_read  = 1'b1;
    assign do_csr_write = 1'b1;

endmodule
```

#### 3.4.3 `riscv_mux_4_1.sv`

The current WB mux is `riscv_mux_3_1` (3-input). CSR adds a 4th writeback source.
Create a 4-input version:

```systemverilog
module riscv_mux_4_1 (
    input  logic [31:0] A,    // 2'b00 → ALUResultW
    input  logic [31:0] B,    // 2'b01 → ReadDataW
    input  logic [31:0] C,    // 2'b10 → PCPlus4W
    input  logic [31:0] D,    // 2'b11 → CSRRDataW
    input  logic [1:0]  Sel,
    output logic [31:0] out
);
    always_comb begin
        unique case (Sel)
            2'b00: out = A;
            2'b01: out = B;
            2'b10: out = C;
            2'b11: out = D;
        endcase
    end
endmodule
```

### 3.5 Existing modules to modify

#### 3.5.1 `riscv_control_unit.sv`

The SYSTEM opcode case already sets `is_system_instr = 1'b1`. Extend it to also decode
the CSR-specific control signals. New outputs to add to the module port list:

```systemverilog
// Add to module outputs:
output logic       csr_instr,     // 1 = this is a CSR instruction (funct3 != 000)
output logic [2:0] csr_op,        // funct3 → CSR operation code
output logic       csr_imm_sel,   // funct3[2]: 1 = immediate form (CSRRWI/CSRRSI/CSRRCI)
output logic [4:0] csr_uimm,      // rs1 field used as 5-bit zero-extended immediate
output logic       ecall_instr,   // (Phase 5) ECALL detect
output logic       ebreak_instr,  // (Phase 5) EBREAK detect
output logic       mret_instr     // (Phase 5) MRET detect
```

Inside the `7'b1110011` (SYSTEM) case:

```systemverilog
7'b1110011: begin // SYSTEM Instructions (ECALL, EBREAK, MRET, CSRs)
    is_system_instr = 1'b1;
    // CSR instructions: funct3 != 000
    csr_instr   = (funct3 != 3'b000);
    csr_op      = funct3;
    csr_imm_sel = funct3[2];       // bit 2 set → immediate form
    csr_uimm    = instrD[19:15];   // rs1 field doubles as uimm[4:0]
    // When it is a CSR instruction, it will write to rd → RegWrite
    RegWrite    = (funct3 != 3'b000);
    // ResultSrc = 2'b11 → WB mux selects CSRRDataW (new encoding)
    ResultSrc   = (funct3 != 3'b000) ? 2'b11 : 2'bxx;
    // Phase 5 additions (stub for now):
    ecall_instr  = (funct3 == 3'b000) && (instrD[31:20] == 12'h000);
    ebreak_instr = (funct3 == 3'b000) && (instrD[31:20] == 12'h001);
    mret_instr   = (funct3 == 3'b000) && (instrD[31:20] == 12'h302);
end
```

> **Note:** `instrD` is available in `riscv_decode_stage.sv` where `riscv_control_unit` is
> instantiated. The control unit currently receives `instrD[6:0]` as `opcode`,
> `instrD[14:12]` as `funct3`, and `instrD[30]` as `funct7_5`. To pass `csr_uimm`,
> either add `rs1_addr` as a new input to `riscv_control_unit` (`instrD[19:15]`), or
> compute it in `riscv_decode_stage.sv` after the control unit instantiation.

**Grand default additions** (add to the defaults block at the top of `always_comb`):

```systemverilog
csr_instr    = 1'b0;
csr_op       = 3'b000;
csr_imm_sel  = 1'b0;
csr_uimm     = 5'b0;
ecall_instr  = 1'b0;
ebreak_instr = 1'b0;
mret_instr   = 1'b0;
```

#### 3.5.2 `riscv_decode_stage.sv`

Add new internal wires and new output ports for the CSR signals latched through the ID/EX register:

**New internal decode-time wires:**

```systemverilog
logic       csr_instrD;
logic [2:0] csr_opD;
logic       csr_imm_selD;
logic [4:0] csr_uimm D;  // = instrD[19:15] (same bits as Rs1D)
logic       is_system_instrD;
```

**New outputs (add to module port list):**

```systemverilog
output logic       csr_instrE,
output logic [2:0] csr_opE,
output logic       csr_imm_selE,
output logic [4:0] csr_uimmE,
output logic [11:0] csr_addrE,    // instrD[31:20] latched to EX
output logic       is_system_instrE
```

**Connect `riscv_control_unit` instantiation — new ports:**

```systemverilog
riscv_control_unit cu (
    .opcode(instrD[6:0]),
    .funct3(instrD[14:12]),
    .funct7_5(funct7_5),
    // existing outputs ...
    .ResultSrc(ResultSrcD),
    .ALUControl(ALUControlD),
    .ALUSrc(ALUSrcD),
    .ImmSrc(ImmSrcD),
    .RegWrite(RegWriteD),
    .MemWrite(MemWriteD),
    .jump(jumpD),
    .Branch(BranchD),
    .Branch_taken(Branch_taken),
    .ImmPass(ImmPassD),
    .inst_type(inst_type),
    .jalr_pc(jalr_pc),
    .is_system_instr(is_system_instrD),
    // NEW CSR outputs:
    .csr_instr(csr_instrD),
    .csr_op(csr_opD),
    .csr_imm_sel(csr_imm_selD)
    // csr_uimm is instrD[19:15] = Rs1D, assign directly below
);

// csr_uimm is the same bits as Rs1D — no extra CU port needed:
assign csr_uimmD = instrD[19:15];  // zero-extended in csr_execute, not here
```

**ID/EX pipeline register — add to the `always @(posedge clk or negedge rst_n)` block:**

```systemverilog
// In the reset branch (!rst_n || CLR):
csr_instrE     <= 1'b0;
csr_opE        <= 3'b0;
csr_imm_selE   <= 1'b0;
csr_uimmE      <= 5'b0;
csr_addrE      <= 12'b0;
is_system_instrE <= 1'b0;

// In the normal (else) branch:
csr_instrE     <= csr_instrD;
csr_opE        <= csr_opD;
csr_imm_selE   <= csr_imm_selD;
csr_uimmE      <= csr_uimmD;
csr_addrE      <= instrD[31:20];   // latch raw CSR address (NOT sign-extended)
is_system_instrE <= is_system_instrD;
```

#### 3.5.3 `riscv_execute_stage.sv`

Add new input ports for the CSR signals arriving from decode, and new output ports for the
CSR data that must be propagated through EX/MEM:

**New input ports:**

```systemverilog
input  logic        csr_instrE,
input  logic [11:0] csr_addrE,    // passed straight through to csr_file (wired at top level)
input  logic        csr_weE,      // final gated write enable (computed in riscv_top_pipeline)
input  logic [31:0] CSRRDataE     // read data from riscv_csr_file (computed at top level)
```

**New output ports (EX/MEM pipeline register):**

```systemverilog
output logic        csr_instrM,
output logic [31:0] CSRRDataM     // old CSR value → propagated to WB
```

**Add to EX/MEM pipeline register reset:**

```systemverilog
csr_instrM  <= 1'b0;
CSRRDataM   <= 32'h0;
```

**Add to EX/MEM pipeline register normal update:**

```systemverilog
csr_instrM  <= csr_instrE;
CSRRDataM   <= CSRRDataE;
```

#### 3.5.4 `riscv_memory_stage.sv`

Add new input ports for the CSR data from EX/MEM, and new output ports for MEM/WB:

**New input ports:**

```systemverilog
input  logic        csr_instrM,
input  logic [31:0] CSRRDataM
```

**New output ports:**

```systemverilog
output logic        csr_instrW,
output logic [31:0] CSRRDataW
```

**Add to MEM/WB reset:**

```systemverilog
csr_instrW  <= 1'b0;
CSRRDataW   <= 32'h0;
```

**Add to MEM/WB normal update:**

```systemverilog
csr_instrW  <= csr_instrM;
CSRRDataW   <= CSRRDataM;
```

#### 3.5.5 `riscv_top_pipeline.sv` — WB mux and new wiring

**New wires to declare:**

```systemverilog
// CSR signals through the pipeline
logic        csr_instrE, csr_instrM, csr_instrW;
logic [11:0] csr_addrE;
logic [2:0]  csr_opE;
logic        csr_imm_selE;
logic [4:0]  csr_uimmE;
logic [31:0] CSRRDataE;     // combinational read from CSR file
logic [31:0] CSRRDataM;     // latched in EX/MEM
logic [31:0] CSRRDataW;     // latched in MEM/WB

logic [31:0] csr_wdataE;    // computed by riscv_csr_execute
logic        csr_weE;       // gated write enable
logic        csr_illegal;   // undefined address flag from CSR file
logic        do_csr_read;   // suppression: this CSR op reads
logic        do_csr_write;  // suppression: this CSR op writes

// is_system_instr passthrough (if not already wired)
logic        is_system_instrE;
```

**Instantiate `riscv_csr_file`:**

```systemverilog
riscv_csr_file csr_file (
    .clk          (clk),
    .rst_n        (rst_n),
    .csr_addrE    (csr_addrE),
    .csr_wdataE   (csr_wdataE),
    .csr_weE      (csr_weE),
    .CSRRDataE    (CSRRDataE),
    .csr_illegal  (csr_illegal),
    // Tie off Phase 4/5 ports until those phases:
    .trap_we      (1'b0),
    .trap_mepc    (32'h0),
    .trap_mcause  (32'h0),
    .trap_mtval   (32'h0),
    .mret_we      (1'b0),
    .instret_inc  (1'b0),
    // CSR value outputs (used from Phase 5):
    .mstatus_out  (),
    .mtvec_out    (),
    .mepc_out     (),
    .mcause_out   ()
);
```

**Instantiate `riscv_csr_execute`:**

```systemverilog
riscv_csr_execute csr_exec (
    .CSRRDataE    (CSRRDataE),      // from CSR file read port
    .mux_R1_out   (mux_R1_out),     // forwarded rs1 from existing mux_alu_1
    .funct3E      (funct3E),
    .csr_imm_selE (csr_imm_selE),
    .csr_uimmE    (csr_uimmE),
    .csr_wdataE   (csr_wdataE),
    .do_csr_read  (do_csr_read),
    .do_csr_write (do_csr_write)
);

// Write enable: CSR instruction AND write not suppressed AND address legal
assign csr_weE = csr_instrE & do_csr_write & ~csr_illegal;
```

**Update the WB mux** — replace `riscv_mux_3_1 mux_w` with `riscv_mux_4_1`:

```systemverilog
// OLD (remove):
// riscv_mux_3_1 mux_w(.A(ALUResultW), .B(ReadDataW), .C(PCPlus4W), .Sel(ResultSrcW), .out(result));

// NEW:
riscv_mux_4_1 mux_w(
    .A   (ALUResultW),   // ResultSrcW = 2'b00
    .B   (ReadDataW),    // ResultSrcW = 2'b01
    .C   (PCPlus4W),     // ResultSrcW = 2'b10
    .D   (CSRRDataW),    // ResultSrcW = 2'b11  ← NEW: CSR read result
    .Sel (ResultSrcW),
    .out (result)
);
```

**Update `riscv_decode_stage` instantiation** with new CSR ports:

```systemverilog
riscv_decode_stage decode_stage_inst(
    .clk(clk), .rst_n(rst_n), .instrD(instrD), .PCPlus4D(PCPlus4D), .PCD(PCD),
    .RegWriteW(RegWriteW), .ResultW(result),
    .RdW(RdW), .PCE(PCE), .PCPlus4E(PCPlus4E), .RegWriteE(RegWriteE),
    .ResultSrcE(ResultSrcE), .MemWriteE(MemWriteE),
    .jumpE(jumpE), .Branch_takenE(Branch_takenE), .BranchE(BranchE),
    .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE), .RD1E(RD1E),
    .RD2E(RD2E), .ImmExtE(ImmExtE), .RdE(RdE),
    .CLR(FlushE),
    .Rs1E(Rs1E), .Rs2E(Rs2E), .Rs1D(Rs1D), .Rs2D(Rs2D),
    .funct3E(funct3E), .ImmPassE(ImmPassE), .inst_typeE(inst_typeE),
    .jalr_pcE(jalr_pcE),
    // NEW CSR ports:
    .csr_instrE    (csr_instrE),
    .csr_opE       (csr_opE),
    .csr_imm_selE  (csr_imm_selE),
    .csr_uimmE     (csr_uimmE),
    .csr_addrE     (csr_addrE),
    .is_system_instrE(is_system_instrE)
);
```

**Update `riscv_execute_stage` instantiation:**

```systemverilog
riscv_execute_stage execute_stage_inst(
    // existing ports ...
    .clk(clk), .rst_n(rst_n), .PCE(PCE), .PCPlus4E(PCPlus4E),
    .RegWriteE(RegWriteE), .ResultSrcE(ResultSrcE), .MemWriteE(MemWriteE),
    .jumpE(jumpE), .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE),
    .inst_typeE(inst_typeE), .funct3E(funct3E), .ImmPassE(ImmPassE),
    .jalr_pcE(jalr_pcE), .RD1E(mux_R1_out), .RD2E(mux_R2_out),
    .ImmExtE(ImmExtE), .RdE(RdE),
    .RegWriteM(RegWriteM), .ResultSrcM(ResultSrcM), .MemWriteM(MemWriteM),
    .ALUResultM(ALUResultM), .WriteDataM(WriteDataM), .RdM(RdM),
    .PCTargetE_new(PCTargetE), .PCPlus4M(PCPlus4M),
    .ZeroE(ZeroE), .funct3M(funct3M),
    // NEW CSR ports:
    .csr_instrE  (csr_instrE),
    .csr_addrE   (csr_addrE),
    .csr_weE     (csr_weE),
    .CSRRDataE   (CSRRDataE),
    .csr_instrM  (csr_instrM),
    .CSRRDataM   (CSRRDataM)
);
```

**Update `riscv_memory_stage` instantiation:**

```systemverilog
riscv_memory_stage memory_stage_inst(
    // existing ports ...
    .clk(clk), .rst_n(rst_n), .RegWriteM(RegWriteM), .ResultSrcM(ResultSrcM),
    .MemWriteM(MemWriteM), .ALUResultM(ALUResultM), .WriteDataM(WriteDataM),
    .RdM(RdM), .PCPlus4M(PCPlus4M), .funct3M(funct3M),
    .RegWriteW(RegWriteW), .ResultSrcW(ResultSrcW), .RdW(RdW),
    .ALUResultW(ALUResultW), .ReadDataW(ReadDataW), .PCPlus4W(PCPlus4W),
    // NEW CSR ports:
    .csr_instrM  (csr_instrM),
    .CSRRDataM   (CSRRDataM),
    .csr_instrW  (csr_instrW),
    .CSRRDataW   (CSRRDataW)
);
```

**Update `riscv_hazard_unit` instantiation** (add CSR stall — see Phase 1 stall strategy):

```systemverilog
riscv_hazard_unit hu(
    .Rs1E(Rs1E), .Rs2E(Rs2E), .RdM(RdM), .RdW(RdW),
    .RegWriteM(RegWriteM), .RegWriteW(RegWriteW),
    .ResultSrcE_0(ResultSrcE[0]),
    .RdE(RdE), .Rs1D(Rs1D), .Rs2D(Rs2D), .PCSrcE(PCSrcE),
    .FlushE(FlushE), .StallD(StallD), .StallF(StallF),
    .ForwardAE(ForwardAE), .ForwardBE(ForwardBE), .FlushD(FlushD),
    // NEW: CSR stall inputs
    .csr_instrE(csr_instrE),
    .csr_instrM(csr_instrM),
    .csr_instrW(csr_instrW),
    .csr_instrD(csr_instrD_top)  // wire instrD[6:0]==SYSTEM & funct3!=000 at top level
);
```

### 3.6 Datapath summary

```
instrD (from fetch):
  instrD[6:0]   → riscv_control_unit: opcode → csr_instrD, csr_opD, csr_imm_selD
  instrD[31:20] → ID/EX latch → csr_addrE → riscv_csr_file read port
  instrD[19:15] → csr_uimmD (= Rs1D, same bits — zero-extend in csr_execute)
  instrD[14:12] → funct3D → funct3E

EX stage (wired in riscv_top_pipeline):
  csr_addrE → riscv_csr_file.csr_addrE → CSRRDataE (combinational read)
  {mux_R1_out, CSRRDataE, funct3E, csr_imm_selE, csr_uimmE}
      → riscv_csr_execute → csr_wdataE, do_csr_write, do_csr_read
  csr_instrE & do_csr_write & ~csr_illegal → csr_weE → riscv_csr_file.csr_weE
  CSRRDataE → latched into EX/MEM register as CSRRDataM

WB stage:
  MEM/WB.CSRRDataW → riscv_mux_4_1 mux_w (Sel=2'b11) → result
  result → riscv_register_file.WD3 (when RegWriteW=1 and RdW≠x0)
```

> **Critical:** `CSRRDataE` is the value *before* the write. It must be latched at the
> EX/MEM boundary and carried through to WB unchanged. Never route `csr_wdataE` into the
> writeback path.

### 3.7 Pipeline changes — stall strategy

**Recommended for Phase 1: full serialisation.**

When a CSR instruction is in the pipeline, stall IF and ID while EX/MEM/WB drain:

```systemverilog
// In riscv_hazard_unit.sv — add new inputs and logic:

// New inputs:
input logic csr_instrD,   // CSR instr is currently in ID (decode stage)
input logic csr_instrE,   // CSR instr is currently in EX
input logic csr_instrM,   // CSR instr is currently in MEM
input logic csr_instrW,   // CSR instr is currently in WB

// New internal logic:
logic downstream_csr;
logic csr_pipeline_stall;

assign downstream_csr       = csr_instrE | csr_instrM | csr_instrW;
assign csr_pipeline_stall   = csr_instrD & downstream_csr;

// Update existing stall assignments:
// OLD: assign StallF = lwStall;  assign StallD = lwStall;
// NEW:
assign StallF = lwStall | csr_pipeline_stall;
assign StallD = lwStall | csr_pipeline_stall;
// FlushE = lwStall | PCSrcE   ← UNCHANGED (never flush on CSR stall)
```

At `riscv_top_pipeline.sv` top level, compute `csr_instrD` (the decode-stage CSR flag):

```systemverilog
// Decode-stage CSR flag (combinational from instrD):
logic csr_instrD_top;
assign csr_instrD_top = (instrD[6:0] == 7'b1110011) && (instrD[14:12] != 3'b000);
```

Pass `csr_instrD_top` into `riscv_hazard_unit` as the `csr_instrD` port.

### 3.8 Assembly examples

#### Example 1: CSRRW — basic register write and read

```asm
# Objective: write 0xDEADBEEF into mscratch, read it back into t0
# CSR address 0x340 = mscratch

li   t1, 0xDEADBEEF        # t1 = 0xDEADBEEF

# Before: mscratch = 0x00000000, t0 = undefined, t1 = 0xDEADBEEF
csrrw t0, mscratch, t1     # t0 = OLD mscratch (0), mscratch = t1 (0xDEADBEEF)
# After:  mscratch = 0xDEADBEEF, t0 = 0x00000000

csrr  t0, mscratch         # pseudoinstruction: CSRRS t0, mscratch, x0
# After:  mscratch = 0xDEADBEEF (unchanged), t0 = 0xDEADBEEF
```

**Cycle-by-cycle for `csrrw t0, mscratch, t1`:**

| Cycle | IF          | ID             | EX                                        | MEM              | WB               |
|-------|-------------|----------------|-------------------------------------------|------------------|------------------|
| 1     | csrrw fetch | —              | —                                         | —                | —                |
| 2     | (stall)     | csrrw decode   | —                                         | —                | —                |
| 3     | (stall)     | csrrw (stall)  | csrrw: read mscratch=0, write 0xDEADBEEF  | —                | —                |
| 4     | (stall)     | csrrw (stall)  | bubble                                    | csrrw rdata=0x0  | —                |
| 5     | (stall)     | csrrw (stall)  | bubble                                    | bubble           | csrrw: t0 ← 0x0 |
| 6     | resume      | csrr decode    | —                                         | —                | —                |

#### Example 2: CSRRS — set specific bits

```asm
# Set bit 3 (MIE) of mstatus
li     t0, 0x8              # bitmask: bit 3 = 0b1000
csrrs  t1, mstatus, t0      # t1 = old mstatus, mstatus |= 0x8

# Before: mstatus = 0x00000000
# After:  mstatus = 0x00000008, t1 = 0x00000000
```

#### Example 3: CSRRC — clear specific bits

```asm
# Clear bit 3 (MIE) of mstatus
li     t0, 0x8
csrrc  t1, mstatus, t0      # t1 = old mstatus, mstatus &= ~0x8

# Before: mstatus = 0x00000008
# After:  mstatus = 0x00000000, t1 = 0x00000008
```

### 3.9 Verification strategy

**Testbench assertions to write (in `riscv_top_tb.sv` or a dedicated Phase 1 tb):**

```systemverilog
// Test 1: CSRRW round-trip
// Run: li t1, 0xDEADBEEF; csrrw t0, mscratch, t1; csrr t2, mscratch
// Wait for WB of csrr
assert(dut.regfile.rf[5]  == 32'h0)         else $fatal("CSRRW: t0 should be old mscratch=0");
assert(dut.regfile.rf[7]  == 32'hDEADBEEF)  else $fatal("CSRR:  t2 should be new mscratch");
assert(dut.csr_file.mscratch_q == 32'hDEADBEEF) else $fatal("mscratch register wrong");

// Test 2: CSRRS set bits
// Run: li t0, 0x8; csrrs t1, mstatus, t0
assert(dut.csr_file.mstatus_q[3] == 1'b1) else $fatal("CSRRS: MIE bit not set");

// Test 3: CSRRC clear bits
// Run after test 2: csrrc t1, mstatus, t0
assert(dut.csr_file.mstatus_q[3] == 1'b0) else $fatal("CSRRC: MIE bit not cleared");
```

**Waveform checkpoints (GTKWave / Questa):**

Probe these signals and verify:
- `csr_addrE` in EX = `12'h340` (mscratch address)
- `CSRRDataE` leaving EX = old value
- `csr_wdataE` entering CSR file write port = new value
- `csr_weE` = 1 during EX of the CSR instruction
- `result` (WB mux output) = old value (not new) when `ResultSrcW = 2'b11`
- `StallF` and `StallD` fire and release correctly

### 3.10 Common mistakes in Phase 1

1. **Writing new value instead of old to rd.** `rd` must receive the value that was in the
   CSR *before* the write. `CSRRDataE` must be latched at EX/MEM as `CSRRDataM` and then
   at MEM/WB as `CSRRDataW`. Do not route `csr_wdataE` into the writeback path.

2. **Routing csr_addrE through `riscv_extend.sv`.** `instrD[31:20]` is the 12-bit CSR
   address. Do NOT pass it through the immediate extension unit — that would sign-extend it
   to 32 bits. Latch the raw 12 bits directly into `csr_addrE` in the ID/EX pipeline register.

3. **Forgetting the WB mux extension.** The current `riscv_mux_3_1 mux_w` only has three
   inputs. Replace it with `riscv_mux_4_1` and use `ResultSrcW = 2'b11` for CSR readback.
   Ensure `riscv_control_unit` drives `ResultSrc = 2'b11` for CSR instructions.

4. **Treating misa as writable.** `misa_q` is a constant for this RV32I implementation.
   The write case for `misa` must not exist in `riscv_csr_file.sv`. The default `; // ignore`
   covers it.

5. **Using `mux_R2_out` instead of `mux_R1_out` in `riscv_csr_execute`.** CSR instructions
   use `rs1` (operand A path) for the write data. The forwarded rs1 is `mux_R1_out`
   (output of `mux_alu_1`). `mux_R2_out` is rs2 and must not be used here.

6. **Not adding `csr_instrD_top` to `riscv_hazard_unit`.** Without the stall, a CSR
   instruction will attempt to read a CSR before prior instructions have committed, causing
   wrong results. Always add the serialisation stall before testing.

### 3.11 What works after Phase 1

- CSRRW, CSRRS, CSRRC with register-source operands
- mscratch, mstatus (basic read/write), mtvec, mie, mepc, mcause, mtval
- Read-only identity CSRs (mhartid, mvendorid, marchid) returning constant 0
- mcycle incrementing every clock (hardware side)
- Pipeline serialisation stall for CSR instructions

---

## 4. Phase 2 — Immediate Variants + Suppression Rules {#phase2}

### 4.1 Goal

Add CSRRWI, CSRRSI, CSRRCI. Implement the complete suppression rule matrix from Table 7
of the spec. After this phase, all six CSR instructions are architecturally correct.

### 4.2 Why this phase

The immediate variants are structurally identical to the register variants except the operand
comes from `csr_uimmE` (bits [19:15] of the instruction, zero-extended — already latched
in Phase 1). The *suppression rules* differ between the two families, and they differ by
instruction within each family.

### 4.3 Spec reference

Section 6.1, pages 47–49. Table 7 (the read/write suppression matrix). Critical sentence:
"For CSRRSI and CSRRCI, if the uimm[4:0] field is zero, then these instructions will not
write to the CSR."

### 4.4 Suppression rule matrix (your implementation checklist)

```
Instruction  | rd=x0?  | rs1/uimm=x0/0? | Reads CSR? | Writes CSR?
─────────────┼─────────┼────────────────┼────────────┼────────────
CSRRW        | YES     | —              | NO         | YES
CSRRW        | NO      | —              | YES        | YES
CSRRS        | —       | YES (rs1=x0)   | YES        | NO
CSRRS        | —       | NO             | YES        | YES
CSRRC        | —       | YES (rs1=x0)   | YES        | NO
CSRRC        | —       | NO             | YES        | YES
CSRRWI       | YES     | —              | NO         | YES
CSRRWI       | NO      | —              | YES        | YES
CSRRSI       | —       | YES (uimm=0)   | YES        | NO
CSRRSI       | —       | NO             | YES        | YES
CSRRCI       | —       | YES (uimm=0)   | YES        | NO
CSRRCI       | —       | NO             | YES        | YES
```

### 4.5 RTL implementation of suppression

Update `riscv_csr_execute.sv`:

```systemverilog
`include "riscv_csr_defines.svh"

module riscv_csr_execute (
    input  logic [31:0] CSRRDataE,
    input  logic [31:0] mux_R1_out,
    input  logic [2:0]  funct3E,
    input  logic        csr_imm_selE,
    input  logic [4:0]  csr_uimmE,
    input  logic        rd_is_x0,      // RdE == 5'b00000  (from riscv_top_pipeline)
    input  logic        rs1_is_x0,     // Rs1E == 5'b00000 (from riscv_top_pipeline)

    output logic [31:0] csr_wdataE,
    output logic        do_csr_read,
    output logic        do_csr_write
);

    logic [31:0] operand;
    logic        zero_operand;

    assign operand      = csr_imm_selE ? {27'b0, csr_uimmE} : mux_R1_out;
    assign zero_operand = csr_imm_selE ? (csr_uimmE == 5'b0) : rs1_is_x0;

    always_comb begin
        unique case (funct3E[1:0])
            2'b01: csr_wdataE = operand;
            2'b10: csr_wdataE = CSRRDataE | operand;
            2'b11: csr_wdataE = CSRRDataE & (~operand);
            default: csr_wdataE = 32'h0;
        endcase
    end

    // Suppression logic — directly encoding Table 7
    always_comb begin
        unique case (funct3E)
            `CSR_OP_RW:  begin do_csr_read = ~rd_is_x0;    do_csr_write = 1'b1;          end
            `CSR_OP_RS:  begin do_csr_read = 1'b1;          do_csr_write = ~zero_operand; end
            `CSR_OP_RC:  begin do_csr_read = 1'b1;          do_csr_write = ~zero_operand; end
            `CSR_OP_RWI: begin do_csr_read = ~rd_is_x0;    do_csr_write = 1'b1;          end
            `CSR_OP_RSI: begin do_csr_read = 1'b1;          do_csr_write = ~zero_operand; end
            `CSR_OP_RCI: begin do_csr_read = 1'b1;          do_csr_write = ~zero_operand; end
            default:     begin do_csr_read = 1'b0;          do_csr_write = 1'b0;          end
        endcase
    end

endmodule
```

In `riscv_top_pipeline.sv`, add the suppression inputs and update the write enable:

```systemverilog
// rd_is_x0 and rs1_is_x0 from the already-latched EX-stage register addresses:
logic rd_is_x0, rs1_is_x0;
assign rd_is_x0  = (RdE  == 5'b00000);
assign rs1_is_x0 = (Rs1E == 5'b00000);

// Updated csr_execute instantiation with new ports:
riscv_csr_execute csr_exec (
    .CSRRDataE    (CSRRDataE),
    .mux_R1_out   (mux_R1_out),
    .funct3E      (funct3E),
    .csr_imm_selE (csr_imm_selE),
    .csr_uimmE    (csr_uimmE),
    .rd_is_x0     (rd_is_x0),     // NEW
    .rs1_is_x0    (rs1_is_x0),    // NEW
    .csr_wdataE   (csr_wdataE),
    .do_csr_read  (do_csr_read),
    .do_csr_write (do_csr_write)
);

// Gate CSR write enable by suppression and legality
assign csr_weE = csr_instrE & do_csr_write & ~csr_illegal;

// Gate register file writeback: when do_csr_read=0 (CSRRW with rd=x0),
// suppress the writeback by forcing RegWrite off for this instruction.
// The cleanest way: the control unit already sets RegWrite=1 for CSR instrs.
// Override it in the WB stage: hold RegWriteW low when CSR and do_csr_read=0.
// Since do_csr_read is an EX-stage signal, propagate it through EX/MEM → MEM/WB:
logic        do_csr_read_M, do_csr_read_W;
// (add to pipeline register latching in execute_stage and memory_stage)
// In WB: assign effective_RegWriteW = RegWriteW & (~csr_instrW | do_csr_read_W);
// Pass effective_RegWriteW to riscv_register_file.w_en instead of RegWriteW.
```

### 4.6 Assembly examples

#### Example 1: CSRRWI — write immediate to mtvec

```asm
# Set mtvec to address 0x4 (uimm=4, 5 bits only, max 31)
csrrwi x0, mtvec, 4        # mtvec = 4, don't read (rd=x0 suppresses read)

# Before: mtvec = 0x00000000
# After:  mtvec = 0x00000004
```

#### Example 2: CSRRSI — set bits with immediate

```asm
# Set bit 3 (MIE in mstatus), uimm=8 = 0b01000
csrrsi x0, mstatus, 8      # mstatus |= 8, don't read old value (rd=x0)

# Before: mstatus = 0x00000000
# After:  mstatus = 0x00000008 (MIE bit set)
```

#### Example 3: CSRRCI with uimm=0 — suppressed write

```asm
# Read mstatus without writing (uimm=0 suppresses write)
csrrci t0, mstatus, 0      # t0 = mstatus, NO write to mstatus

# Equivalent to: csrr t0, mstatus (= CSRRS t0, mstatus, x0)
# Before: mstatus = 0x00000008
# After:  mstatus = 0x00000008 (unchanged), t0 = 0x00000008
```

#### Example 4: CSRRW to read-only CSR, rd=x0 — must NOT read

```asm
csrrw x0, mhartid, t0     # rd=x0 → no read; write discarded (mhartid read-only)
# mhartid remains 0x00000000 regardless of t0
```

### 4.7 Corner case: CSRRS/CSRRC to read-only CSR with rs1≠x0

```asm
li    t0, 0x1
csrrs t1, mhartid, t0     # Phase 2: t1=0, mhartid unchanged (write discarded silently)
                           # Phase 3: this will raise illegal-instruction
```

This corner case highlights why Phase 3 (read-only violation detection) must check both
`csr_addrE[11:10]==2'b11` AND `do_csr_write==1`.

### 4.8 Verification strategy for Phase 2

```systemverilog
// Test every cell of Table 7:

// CSRRW rd=x0: no read, yes write
csrrw x0, mscratch, t0;
// Check: x0 unchanged (always 0), mscratch = t0's value

// CSRRS rs1=x0: yes read, no write (read-only probe)
csrrs t1, mscratch, x0;
// Check: mscratch unchanged, t1 = mscratch value

// CSRRWI rd=x0: no read, yes write
csrrwi x0, mscratch, 7;
// Check: mscratch = 7 (0x00000007)

// CSRRSI uimm=0: yes read, no write
csrrsi t0, mscratch, 0;
// Check: mscratch unchanged, t0 = mscratch value

// CSRRCI uimm=0: yes read, no write
csrrci t0, mscratch, 0;
// Check: mscratch unchanged, t0 = mscratch value
```

### 4.9 Common mistakes in Phase 2

1. **Confusing rs1=x0 with rs1 holding value 0.** The suppression check is on the *register
   address field* `Rs1E == 5'b00000`, not on `mux_R1_out == 32'h0`. If t0 happens to contain 0,
   `CSRRS t1, mstatus, t0` still writes mstatus (write mask 0, so no bits change, but side
   effect fires). Only `rs1=x0` suppresses the write.

2. **Applying register-form suppression to immediate form.** For CSRRSI/CSRRCI, check
   `csr_uimmE == 5'b00000`. For CSRRS/CSRRC, check `Rs1E == 5'b00000`.
   Use `csr_imm_selE` to select the correct check inside `riscv_csr_execute`.

3. **Not propagating `do_csr_read` through EX/MEM → MEM/WB.** The register file write
   for CSR instructions must be `RegWriteW & (~csr_instrW | do_csr_read_W)`. Propagate
   `do_csr_read` as a new pipeline register field through `riscv_execute_stage` and
   `riscv_memory_stage` just like `csr_instrE/M/W`.

4. **Forgetting that uimm is zero-extended, not sign-extended.** `csr_uimmE[4:0]` → `{27'b0, csr_uimmE}`.
   Never pass it through `riscv_extend.sv`. Latch it raw from `instrD[19:15]` in
   `riscv_decode_stage` and zero-extend inside `riscv_csr_execute`.

---

## 5. Phase 3 — Read-Only CSRs and Illegal-Address Detection {#phase3}

### 5.1 Goal

Raise an illegal-instruction exception when software attempts to:
(a) write a read-only CSR (where `csr_addrE[11:10] == 2'b11`), or
(b) access an undefined CSR address.

After this phase, the core behaves correctly when firmware tries to write a constant CSR.
The exception does not yet trap (no trap handler) — it asserts a signal for use in Phase 5.

### 5.2 Why this phase

Before building the counter logic or the trap system, you need to know what constitutes a
legal CSR access. The illegal-instruction detection is a combinational check in decode that
feeds into the exception path. Building it now means every later phase gets the check for free.

### 5.3 Spec reference

Section 6.1, page 47: "The CSR specifier is encoded in the 12-bit csr field." Upper two
bits (`csr[11:10]`) encode access: `11` = read-only. Privileged Spec Vol II Section 2.1:
"Attempts to access a non-existent CSR raise an illegal instruction exception."

### 5.4 The two distinct illegal conditions

**Condition A: Write to a read-only CSR**

```
csr_addrE[11:10] == 2'b11  AND  do_csr_write_decode == 1
```

Examples: `mhartid` (0xF14), `mvendorid` (0xF11), `cycle` (0xC00), `instret` (0xC02).
Note: `csrrs t0, mhartid, x0` does NOT trigger this because `do_csr_write==0`.

**Condition B: Access to an undefined CSR address**

The `csr_illegal` output from `riscv_csr_file` fires for any address not in the case
statement. This constitutes an illegal instruction regardless of read or write.

### 5.5 RTL changes

#### In `riscv_control_unit.sv` (decode stage — using decode-time signals):

```systemverilog
// New decode-time outputs to add to riscv_control_unit port list:
output logic illegal_csr_access,
output logic csr_readonly_viol,
output logic csr_undef_viol

// ── do_csr_write_decode: replicate suppression in decode using instrD fields ──
// rs1_addr = instrD[19:15], rd_addr = instrD[11:7] (both visible in decode)
logic do_csr_write_decode;
always_comb begin
    case (funct3)   // funct3 from instrD[14:12]
        `CSR_OP_RW, `CSR_OP_RWI: do_csr_write_decode = 1'b1;
        `CSR_OP_RS, `CSR_OP_RC:  do_csr_write_decode = (rs1_addr != 5'b0);
        `CSR_OP_RSI,`CSR_OP_RCI: do_csr_write_decode = (rs1_addr != 5'b0); // rs1 field = uimm
        default:                  do_csr_write_decode = 1'b0;
    endcase
end
// Note: rs1_addr and rd_addr must be added as inputs to riscv_control_unit,
// OR computed inside riscv_decode_stage.sv where instrD is available.

// ── Read-only violation ───────────────────────────────────────────────────────
// csr_addr here = instrD[31:20] (pass as new input to riscv_control_unit, or
// compute in riscv_decode_stage and assign to an output wire directly)
assign csr_readonly_viol = (csr_addr[11:10] == 2'b11) && do_csr_write_decode;

// ── Undefined address: decode-time lookup ────────────────────────────────────
always_comb begin
    csr_undef_viol = 1'b1; // default: undefined
    case (csr_addr)
        `CSR_MHARTID, `CSR_MVENDORID, `CSR_MARCHID, `CSR_MIMPID,
        `CSR_MISA, `CSR_MSTATUS, `CSR_MIE, `CSR_MTVEC,
        `CSR_MSCRATCH, `CSR_MEPC, `CSR_MCAUSE, `CSR_MTVAL,
        `CSR_MCYCLE, `CSR_MCYCLEH, `CSR_MINSTRET, `CSR_MINSTRETH,
        `CSR_CYCLE, `CSR_CYCLEH, `CSR_INSTRET, `CSR_INSTRETH:
            csr_undef_viol = 1'b0;
        default:
            csr_undef_viol = 1'b1;
    endcase
end

assign illegal_csr_access = csr_instr && (csr_readonly_viol || csr_undef_viol);
```

> **Implementation note:** `riscv_control_unit.sv` currently receives `instrD[6:0]` (opcode),
> `instrD[14:12]` (funct3), and `instrD[30]` (funct7_5). To avoid a large refactor, you can
> alternatively compute `illegal_csr_access`, `csr_readonly_viol`, and `csr_undef_viol`
> directly inside `riscv_decode_stage.sv` as combinational logic using `instrD[31:20]` and
> the decode outputs from `riscv_control_unit`, then pass `illegal_csr_access` as an output
> port of `riscv_decode_stage`.

For Phase 3, log `illegal_csr_access` in simulation but do not yet take a trap.
The hardware action (trap) comes in Phase 5.

### 5.6 Assembly examples

#### Example 1: Write to mhartid — should be illegal

```asm
li   t0, 0x42
csrrw x0, mhartid, t0     # mhartid[11:10]=11, do_csr_write=1 → ILLEGAL
# Expected: illegal_csr_access asserted in decode
# Expected: mhartid remains 0x00000000
```

#### Example 2: CSRRS to read-only CSR with rs1=x0 — LEGAL

```asm
csrrs t0, mhartid, x0     # mhartid[11:10]=11, but rs1=x0 → do_csr_write=0 → LEGAL
# Expected: illegal_csr_access NOT asserted
# Expected: t0 = 0x00000000 (mhartid value)
```

#### Example 3: Access undefined CSR — should be illegal

```asm
csrr t0, 0x900             # CSR 0x900 is undefined
# Expected: illegal_csr_access asserted
```

### 5.7 Verification strategy

```systemverilog
// Test 1: write to read-only CSR
// run_asm: li t0, 1; csrrw x0, mhartid, t0
assert(dut.decode_stage_inst.illegal_csr_access == 1'b1) else $fatal("read-only write not detected");

// Test 2: CSRRS with rs1=x0 to read-only CSR — must be legal
// run_asm: csrrs t0, mhartid, x0
assert(dut.decode_stage_inst.illegal_csr_access == 1'b0) else $fatal("legal read marked illegal");
assert(dut.regfile.rf[5] == 32'h0)                       else $fatal("mhartid should be 0");

// Test 3: undefined address
// run_asm: csrr t0, 0x900
assert(dut.decode_stage_inst.illegal_csr_access == 1'b1) else $fatal("undefined CSR not detected");
```

### 5.8 Common mistakes in Phase 3

1. **Checking `csr_addrE[11:10]==11` without gating on `do_csr_write`.** The spec is explicit:
   a read to a read-only CSR is legal. Checking the address alone incorrectly rejects
   `csrr t0, cycle`.

2. **Checking legality in EX instead of decode.** Detect in decode — it maps to where
   `illegal_csr_access` feeds the trap controller in Phase 5.

3. **Forgetting user-mode mirror CSRs are read-only.** `cycle` (0xC00), `instret` (0xC02),
   `cycleh` (0xC80), `instreth` (0xC82) all have `csr[11:10]==11`. Writes are illegal.
   Reads are legal and return the same physical register value as the M-mode counters.

---

## 6. Phase 4 — Performance Counters (mcycle / minstret) {#phase4}

### 6.1 Goal

Make `mcycle` and `minstret` architecturally correct — readable by software, writable
(software write overrides hardware increment), and counting the right events.
The user-mode mirror CSRs (`cycle`, `instret`) return the same values.

### 6.2 Why this phase

`mcycle` and `minstret` are the most important diagnostic tools in any RISC-V system.
They have subtle semantics: the hardware increment and the software write can collide
in the same cycle, and RV32 requires reading the upper and lower 32 bits separately.

### 6.3 Spec reference

Chapter 7, Section 7.1 (Zicntr extension), pages 51–53.

### 6.4 Hardware details

#### mcycle

Use a `_next` local variable pattern so the software write correctly overrides the hardware
increment without relying on non-blocking assignment ordering:

```systemverilog
// In riscv_csr_file.sv always_ff block:
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mcycle_q <= 64'h0;
    end else begin
        logic [63:0] mcycle_next;
        mcycle_next = mcycle_q + 64'h1;   // default: always increment

        // Software write overrides the corresponding half:
        if (csr_weE && csr_addrE == `CSR_MCYCLE)
            mcycle_next[31:0]  = csr_wdataE;
        if (csr_weE && csr_addrE == `CSR_MCYCLEH)
            mcycle_next[63:32] = csr_wdataE;

        mcycle_q <= mcycle_next;
    end
end
```

#### minstret

`minstret` counts retired instructions. "Retired" = exited WB without being squashed.
In this design, a valid (non-squashed) instruction at WB is one where `RegWriteW`
is meaningful AND no flush is hitting WB. Add a `validW` bit:

```systemverilog
// In riscv_top_pipeline.sv:
// validW propagates from validM through MEM/WB. A bubble has valid=0.
// For Phase 4, use a simplified approach using the existing flush signals:
// (FlushW is not yet wired — this core currently has no FlushW. Add it in Phase 5.)
// For Phase 4, use: instret_inc = ~(pipeline is flushed at WB).
// Simple approximation for now: wire instret_inc from a "valid" bit added to MEM/WB.

logic instret_inc;
// A true "valid" bit requires tracking bubble injection through the pipeline.
// Minimal Phase 4 implementation: any instruction reaching WB that is not
// a NOP/bubble retires. Use RegWriteW as a proxy (most real instructions set it).
// For precise counting, add a `validW` pipeline register field in Phase 5.
assign instret_inc = 1'b1;  // simplified: increments every cycle (fix in Phase 5)
```

Wire `instret_inc` into `riscv_csr_file`:

```systemverilog
// Update the CSR file instantiation in riscv_top_pipeline.sv:
.instret_inc (instret_inc)

// In riscv_csr_file.sv always_ff block (same pattern as mcycle):
logic [63:0] minstret_next;
minstret_next = minstret_q + (instret_inc ? 64'h1 : 64'h0);
if (csr_weE && csr_addrE == `CSR_MINSTRET)
    minstret_next[31:0]  = csr_wdataE;
if (csr_weE && csr_addrE == `CSR_MINSTRETH)
    minstret_next[63:32] = csr_wdataE;
minstret_q <= minstret_next;
```

### 6.5 The 64-bit read race problem on RV32

On RV32, software reads `mcycle` (low 32) and `mcycleh` (high 32) as two separate
instructions. The canonical safe read sequence:

```asm
again:
    rdcycleh   t2           # read high (= CSRRS t2, cycleh, x0)
    rdcycle    t1           # read low  (= CSRRS t1, cycle,  x0)
    rdcycleh   t3           # read high again
    bne        t3, t2, again # if high changed, try again
# Result: {t2, t1} is a coherent 64-bit value
```

`rdcycle` and `rdcycleh` are pseudoinstructions that decode identically to
`CSRRS rd, 0xC00, x0` and `CSRRS rd, 0xC80, x0`. No special hardware is needed —
just ensure `0xC00`/`0xC80`/`0xC02`/`0xC82` are in `riscv_csr_file`'s read mux
(already included in Phase 1's CSR file template).

### 6.6 Assembly examples

#### Example 1: Read cycle counter

```asm
rdcycle   t0    # t0 = mcycle[31:0]
rdcycleh  t1    # t1 = mcycle[63:32]
```

#### Example 2: Measure elapsed cycles

```asm
rdcycle t0               # save start
# ... work ...
rdcycle t1               # save end
sub     t2, t1, t0       # t2 = elapsed cycles
```

#### Example 3: Write mcycle to zero

```asm
csrw mcycle,  x0         # mcycle[31:0]  = 0
csrw mcycleh, x0         # mcycle[63:32] = 0
# (sw write overrides hw increment for this cycle)
```

#### Example 4: Verify minstret counts retired instructions

```asm
csrr  t0, minstret       # read starting count (N)
nop                      # 1 instruction
nop                      # 2 instructions
nop                      # 3 instructions
csrr  t1, minstret       # read ending count
# t1 = N+3: the 3 NOPs and the first csrr retired; the second csrr reads before it retires
sub   t2, t1, t0         # t2 = 3
```

### 6.7 Verification strategy

```systemverilog
// Cycle counter test
integer cycles_before, cycles_after, elapsed;
@(posedge clk) cycles_before = dut.csr_file.mcycle_q;
repeat(100) @(posedge clk);
@(posedge clk) cycles_after = dut.csr_file.mcycle_q;
assert(cycles_after - cycles_before == 101) else $fatal("mcycle increment wrong");

// Write override test: run csrw mcycle, x0
@(posedge clk); // after csrw retires
assert(dut.csr_file.mcycle_q[31:0] == 32'h1) // 0 written, then one more increment
    else $fatal("mcycle write override failed");
```

### 6.8 Common mistakes in Phase 4

1. **Incrementing minstret for squashed instructions.** Add a `validW` bit in the MEM/WB
   register. Clear it on flush. Gate `instret_inc` on `validW & ~FlushW`.

2. **Both hw increment and sw write using blocking assignments in the same always block.**
   Use the `_next` pattern shown above. The last non-blocking assignment wins otherwise.

3. **The read returning the post-write value.** The CSR file read mux reads `mcycle_q`
   (the registered value). Never expose `mcycle_next` as the read output.

4. **Forgetting `mcycleh` carries the same upper bits whether accessed via 0xB80 or 0xC80.**
   The M-mode and user-mode views must read the same `mcycle_q[63:32]`.

---

## 7. Phase 5 — Minimal M-Mode CSRs for Trap Handling {#phase5}

### 7.1 Goal

Implement the trap entry and exit sequence using `mstatus`, `mtvec`, `mscratch`, `mepc`,
`mcause`, and `mtval`. After this phase, the processor can take an ECALL exception, jump
to a trap handler, and return with MRET.

### 7.2 Why this phase

Every real CSR use case — RTOS context switching, system call interfaces, timer interrupts —
requires the trap mechanism. You now have the CSR file with the right registers. This phase
wires the trap *logic* to those registers.

### 7.3 Spec reference

RISC-V Privileged Architecture Vol II, Chapter 3, Sections 3.1.6–3.1.9 (mstatus, mtvec,
mepc, mcause, mtval). Section 3.3 (machine-mode trap handling). Unprivileged spec: ECALL
encoding (opcode SYSTEM, funct3=000, imm12=0x000), EBREAK (imm12=0x001), MRET (imm12=0x302).

### 7.4 What the trap entry sequence does (hardware perspective)

When an exception is taken, the hardware performs these *atomic* actions in the same cycle:

```
1. mepc    ← PC of the trapping instruction
2. mcause  ← {is_interrupt, cause_code[30:0]}
3. mtval   ← faulting address / bad instruction bits / 0 for ECALL
4. mstatus.MPIE ← mstatus.MIE    (save old interrupt enable)
5. mstatus.MIE  ← 0              (disable interrupts during handler)
6. mstatus.MPP  ← current_priv   (save privilege; always M-mode for Phase 5)
7. PC       ← mtvec_base         (redirect to trap vector)
```

When MRET executes:

```
1. PC           ← mepc
2. mstatus.MIE  ← mstatus.MPIE
3. mstatus.MPIE ← 1
4. mstatus.MPP  ← 00
```

### 7.5 New hardware block: `riscv_trap_ctrl.sv`

Instantiate in `riscv_top_pipeline.sv`:

```systemverilog
// riscv_trap_ctrl.sv
module riscv_trap_ctrl (
    // Exception sources
    input  logic        exc_illegal_instr,  // from decode (illegal_csr_access or other)
    input  logic        exc_ecall,          // ECALL instruction in decode
    input  logic        exc_ebreak,         // EBREAK instruction in decode
    input  logic        exc_load_misalign,  // from riscv_memory_stage
    input  logic        exc_store_misalign, // from riscv_memory_stage
    input  logic        exc_instr_misalign, // from branch/jump target check

    // PC and instruction for trap capture
    input  logic [31:0] exc_pc,             // PC of faulting instruction
    input  logic [31:0] exc_instr,          // faulting instruction bits (for mtval)
    input  logic [31:0] exc_addr,           // memory address (for load/store misalign)

    // CSR values needed for trap decisions
    input  logic [31:0] mtvec_in,           // from riscv_csr_file.mtvec_out
    input  logic [31:0] mstatus_in,         // from riscv_csr_file.mstatus_out

    // MRET
    input  logic        mret_instr,         // MRET decoded in decode stage

    // Outputs to riscv_csr_file hardware write ports
    output logic        trap_we,
    output logic [31:0] trap_mepc,
    output logic [31:0] trap_mcause,
    output logic [31:0] trap_mtval,

    // Outputs to PC redirect (merged with existing PCSrcE logic in riscv_top_pipeline)
    output logic        take_trap,
    output logic [31:0] trap_pc,

    output logic        take_mret,
    output logic [31:0] mret_pc             // = mepc (wired from csr_file.mepc_out)
);

    logic [31:0] cause;
    logic [31:0] tval;
    logic [31:0] epc;
    logic        any_exception;

    always_comb begin
        cause         = 32'h0;
        tval          = 32'h0;
        epc           = exc_pc;
        any_exception = 1'b0;

        // Priority order (highest first):
        if (exc_instr_misalign) begin
            cause         = 32'd0;   // instruction address misaligned
            tval          = exc_addr;
            any_exception = 1'b1;
        end else if (exc_illegal_instr) begin
            cause         = 32'd2;   // illegal instruction
            tval          = exc_instr;
            any_exception = 1'b1;
        end else if (exc_ecall) begin
            cause         = 32'd11;  // ecall from M-mode
            tval          = 32'h0;
            any_exception = 1'b1;
        end else if (exc_ebreak) begin
            cause         = 32'd3;   // breakpoint
            tval          = exc_pc;
            any_exception = 1'b1;
        end else if (exc_load_misalign) begin
            cause         = 32'd4;
            tval          = exc_addr;
            any_exception = 1'b1;
        end else if (exc_store_misalign) begin
            cause         = 32'd6;
            tval          = exc_addr;
            any_exception = 1'b1;
        end
    end

    assign take_trap   = any_exception;
    assign trap_we     = any_exception;
    assign trap_mepc   = epc;
    assign trap_mcause = cause;
    assign trap_mtval  = tval;

    // mstatus update on trap entry: MPIE←MIE, MIE←0, MPP←11 (M-mode)
    // (This value must be written to mstatus_q — wire into a hardware port of csr_file)

    // Trap PC redirect: always use base address for exceptions
    assign trap_pc = {mtvec_in[31:2], 2'b00};

    assign take_mret = mret_instr;
    // mret_pc = csr_file.mepc_out (wired at top level)

endmodule
```

### 7.6 Pipeline changes for trap handling in `riscv_top_pipeline.sv`

```systemverilog
// Flush on trap or MRET
logic flush_on_trap;
assign flush_on_trap = take_trap | take_mret;

// PC source priority (extend the existing PCSrcE / target logic):
// Existing: assign PCSrcE = target_taken || jumpE;
// New:
logic [31:0] PCTargetFinal;
always_comb begin
    if (take_trap)
        PCTargetFinal = trap_pc;          // from riscv_trap_ctrl
    else if (take_mret)
        PCTargetFinal = mepc_out_wire;    // from riscv_csr_file.mepc_out
    else if (PCSrcE)
        PCTargetFinal = PCTargetE;        // existing branch/jump
    else
        PCTargetFinal = PCPlus4D;         // PC + 4 (normal)
end
// Route PCTargetFinal into riscv_fetch_stage as PCTargetE

// Flush all pipeline stages on trap:
// FlushD: the existing signal already covers branch. Add trap:
// FlushE: same.
// FlushM (new): needed to squash EX/MEM on trap
// FlushW (new): needed to squash MEM/WB on trap (ensures minstret doesn't count trapped instr)
logic FlushM, FlushW;
assign FlushM = flush_on_trap;
assign FlushW = flush_on_trap;

// Add FlushM and FlushW ports to riscv_execute_stage and riscv_memory_stage
// to clear their output registers when asserted.
```

**ECALL/MRET decode** — add to `riscv_control_unit.sv` (the stubs were added in Phase 1):

```systemverilog
// ecall_instr, ebreak_instr, mret_instr already decoded in Phase 1 stubs.
// Wire them from riscv_decode_stage to riscv_top_pipeline and into riscv_trap_ctrl.
```

**Update mstatus on trap entry and MRET** — add hardware write ports to `riscv_csr_file.sv`:

```systemverilog
// Add to riscv_csr_file port list:
input  logic        mstatus_trap_we,    // 1 on trap entry
input  logic [31:0] mstatus_trap_val,   // new mstatus on trap entry
input  logic        mstatus_mret_we,    // 1 on MRET
input  logic [31:0] mstatus_mret_val,   // new mstatus on MRET

// In always_ff block (highest priority, overrides sw write):
if (mstatus_trap_we)
    mstatus_q <= mstatus_trap_val;
else if (mstatus_mret_we)
    mstatus_q <= mstatus_mret_val;
else if (csr_weE && csr_addrE == `CSR_MSTATUS)
    mstatus_q <= csr_wdataE & 32'h0000_1888;  // Phase 5: expand WARL mask
```

Compute `mstatus_trap_val` and `mstatus_mret_val` in `riscv_trap_ctrl.sv`:

```systemverilog
// Inside riscv_trap_ctrl, add outputs:
output logic [31:0] mstatus_trap_val,
output logic [31:0] mstatus_mret_val

// mstatus on trap: MPIE←MIE, MIE←0, MPP←11
assign mstatus_trap_val = {mstatus_in[31:13], 2'b11,        // MPP = M-mode
                           mstatus_in[10:8],
                           mstatus_in[3],                   // MPIE ← old MIE
                           mstatus_in[6:4],
                           1'b0,                            // MIE ← 0
                           mstatus_in[2:0]};

// mstatus on MRET: MIE←MPIE, MPIE←1, MPP←00
assign mstatus_mret_val = {mstatus_in[31:13], 2'b00,        // MPP ← 00
                           mstatus_in[10:8],
                           1'b1,                            // MPIE ← 1
                           mstatus_in[6:4],
                           mstatus_in[7],                   // MIE ← old MPIE
                           mstatus_in[2:0]};
```

### 7.7 ECALL and MRET encoding

```systemverilog
// In riscv_control_unit.sv SYSTEM case (already stubbed):
ecall_instr  = (funct3 == 3'b000) && (instrD[31:20] == 12'h000);
ebreak_instr = (funct3 == 3'b000) && (instrD[31:20] == 12'h001);
mret_instr   = (funct3 == 3'b000) && (instrD[31:20] == 12'h302);
// instrD[31:20] must be passed to riscv_control_unit as a new input,
// OR computed in riscv_decode_stage and passed as decode-stage outputs.
```

### 7.8 The complete mstatus field map for RV32I M-mode only

```
Bit  31:   SD   — dirty state summary (tie to 0 for RV32I M-only)
Bits 12:11: MPP  — previous privilege mode (00=U, 01=S, 11=M)
Bit   7:   MPIE — machine previous interrupt enable
Bit   3:   MIE  — machine interrupt enable
All other bits: 0 or read-only 0
```

WARL mask for Phase 5: `32'h0000_1888` (bits 3, 7, 11, 12 writable).

### 7.9 Assembly examples

#### Example 1: ECALL trap and return

```asm
la   t0, trap_handler
csrw mtvec, t0          # mtvec = trap_handler address (direct mode)

ecall                   # raises exception, cause=11

# Trap handler:
trap_handler:
    csrr t0, mcause     # t0 = 11 (ecall from M-mode)
    csrr t1, mepc       # t1 = PC of ecall instruction
    addi t1, t1, 4      # advance past ecall
    csrw mepc, t1
    mret                # PC ← mepc; MIE ← MPIE; MPIE ← 1

# CSR state trace:
# Before ecall:  mstatus={MIE=1,MPIE=0}
# After ecall:   mstatus={MIE=0,MPIE=1,MPP=11}, mepc=<ecall PC>, mcause=11
# After mret:    mstatus={MIE=1,MPIE=1,MPP=00}, PC=<ecall PC + 4>
```

#### Example 2: Illegal instruction trap

```asm
la   t0, ill_handler
csrw mtvec, t0

li   t1, 0x42
csrrw x0, mhartid, t1  # ILLEGAL → trap

ill_handler:
    csrr t0, mcause     # t0 = 2 (illegal instruction)
    csrr t1, mtval      # t1 = the illegal instruction bits
    csrr t2, mepc       # t2 = PC of the illegal instruction
    addi t2, t2, 4
    csrw mepc, t2
    mret
```

#### Example 3: Verify mstatus.MIE is disabled inside handler

```asm
# Before ecall: mstatus.MIE = 1
ecall
# Hardware sets MIE=0 on trap entry
# Inside handler:
csrr t0, mstatus
andi t0, t0, 8          # extract bit 3 (MIE) → must be 0
```

### 7.10 mtvec vectored mode

```systemverilog
// In riscv_trap_ctrl.sv:
always_comb begin
    if (mtvec_in[0] && is_interrupt)
        trap_pc = {mtvec_in[31:2], 2'b00} + (cause_code << 2);
    else
        trap_pc = {mtvec_in[31:2], 2'b00};  // exceptions always use base
end
// For Phase 5: start with direct mode only (mtvec[0]=0 or WARL-forced).
```

### 7.11 Verification strategy for Phase 5

```systemverilog
// Test 1: ECALL trap
// la t0, handler; csrw mtvec, t0; ecall
assert(dut.csr_file.mcause_q      == 32'd11)       else $fatal("mcause wrong");
assert(dut.csr_file.mepc_q        == ecall_pc)     else $fatal("mepc wrong");
assert(dut.csr_file.mstatus_q[3]  == 1'b0)         else $fatal("MIE not cleared on trap");
assert(dut.csr_file.mstatus_q[7]  == 1'b1)         else $fatal("MPIE not saved");
// Verify the fetch stage has redirected to handler_addr:
assert(dut.new_fet.pc_reg         == handler_addr) else $fatal("PC not redirected to mtvec");

// Test 2: MRET
// (inside handler) addi mepc+4; csrw mepc; mret
assert(dut.new_fet.pc_reg         == ecall_pc+4)   else $fatal("MRET PC wrong");
assert(dut.csr_file.mstatus_q[3]  == 1'b1)         else $fatal("MIE not restored on MRET");
assert(dut.csr_file.mstatus_q[7]  == 1'b1)         else $fatal("MPIE not set to 1 on MRET");

// Test 3: Illegal instruction trap
// li t1, 1; csrrw x0, mhartid, t1
assert(dut.csr_file.mcause_q == 32'd2)             else $fatal("illegal instr cause wrong");
assert(dut.csr_file.mtval_q  == illegal_instr_bits) else $fatal("mtval wrong");
```

### 7.12 Common mistakes in Phase 5

1. **mepc = PC+4 for ECALL instead of PC.** `mepc` for ECALL points to the ECALL instruction.
   The *handler* advances mepc by 4 before MRET. If hardware stores PC+4, software
   `csrr-addi-csrw-mret` skips two instructions.

2. **Not flushing the ECALL instruction from WB.** The trapping instruction does NOT retire
   (minstret does not increment). Squash WB as part of the trap flush. Add `FlushW`.

3. **MRET not restoring mstatus correctly.** Sequence: `MIE←MPIE`, `MPIE←1`, `MPP←00`.
   A common mistake: `MPIE←0` (losing interrupt restoration ability) or not clearing MPP.

4. **PC redirect before mtvec has a valid value.** If firmware has not yet written `mtvec`
   and an exception fires, `mtvec_q=0` redirects to address 0. Add an assertion:
   `assert(!(take_trap && mtvec_q == 0))` in simulation.

5. **Trap CSR write colliding with an in-flight CSRW to the same register.** The pipeline
   flush squashes the in-flight CSRW before it reaches EX. Verify in simulation with a
   `csrw mepc, t0` followed immediately by an ECALL.

6. **Confusing which pipeline stage PC to save in mepc.** In this 5-stage pipeline:
   - Illegal instruction/ECALL/EBREAK: detected in decode → use `PCD` (the PC of the
     instruction currently in decode = the trapping instruction's PC).
   - Misaligned load/store: detected in MEM → use the PC carried forward through EX/MEM.

---

## 8. CSR Address Map Reference {#csrmap}

```
Address  Name        Access   Phase  Notes
──────────────────────────────────────────────────────────────────────────────
0x300    mstatus     MRW      1/5    Global interrupt enable, trap state
0x301    misa        MRO      1      ISA extension bits; wired constant (RV32I)
0x304    mie         MRW      5      Per-interrupt enable
0x305    mtvec       MRW      5      Trap vector base address
0x340    mscratch    MRW      1      General-purpose scratch register
0x341    mepc        MRW      5      Exception return address
0x342    mcause      MRW      5      Exception/interrupt cause
0x343    mtval       MRW      5      Additional trap value
0x344    mip         MRO(hw)  5      Pending interrupts (hardware-driven)
0xB00    mcycle      MRW      4      Cycle counter low 32 bits
0xB02    minstret    MRW      4      Retired instruction count low 32 bits
0xB80    mcycleh     MRW      4      Cycle counter high 32 bits
0xB82    minstreth   MRW      4      Retired instruction count high 32 bits
0xC00    cycle       URO      4      User mirror of mcycle low
0xC02    instret     URO      4      User mirror of minstret low
0xC80    cycleh      URO      4      User mirror of mcycleh high
0xC82    instreth    URO      4      User mirror of minstreth high
0xF11    mvendorid   MRO      1      Vendor ID (constant 0)
0xF12    marchid     MRO      1      Architecture ID (constant 0)
0xF13    mimpid      MRO      1      Implementation ID (constant 0)
0xF14    mhartid     MRO      1      Hart ID (constant 0)
```

Access codes: M=Machine, U=User, R=Read, W=Write, O=Only (read-only)

---

## 9. Forwarding and Hazard Reference {#hazard}

### CSR RAW hazard patterns and resolutions

```
Pattern 1: CSR Write → CSR Read (same CSR, back-to-back)
  csrrw x0, mscratch, t0    ← in MEM when next is in EX
  csrr  t1, mscratch        ← needs new value of mscratch

  Resolution: Pipeline serialisation stall.
  The csr_pipeline_stall in riscv_hazard_unit ensures the second CSR instruction
  cannot enter EX until the first has exited WB. The CSR write takes effect at the
  EX clock edge (registered in always_ff). No forwarding path needed for CSR→CSR.

Pattern 2: ALU → CSR Write (register dependency)
  addi t0, t1, 5            ← result available as ALUResultM / result (WB)
  csrrw x0, mscratch, t0   ← needs t0's value as operand

  Resolution: Existing MEM→EX and WB→EX forwarding handles this.
  riscv_mux_3_1 mux_alu_1 produces mux_R1_out which is connected to
  riscv_csr_execute.mux_R1_out. The existing ForwardAE logic in riscv_hazard_unit
  correctly forwards ALUResultM or result into mux_R1_out. No new forwarding needed.

Pattern 3: Load → CSR Write (load-use)
  lw    t0, 0(a0)           ← load result available after MEM
  csrrw x0, mscratch, t0   ← needs t0 one cycle earlier

  Resolution: Load-use stall (already in riscv_hazard_unit via lwStall) + forwarding.
  The load-use stall (ResultSrcE_0 & (Rs1D==RdE | Rs2D==RdE)) inserts a bubble.
  After the stall, t0 is available from MEM/WB via WB→EX forwarding (ForwardAE=2'b01).

Pattern 4: CSR Read → ALU Use (normal dependency)
  csrr  t0, mscratch        ← t0 written at WB (ResultSrcW=2'b11 → CSRRDataW)
  add   t1, t0, t2          ← needs t0

  Resolution: With serialisation stall, the add cannot enter EX until the csrr has
  exited WB. t0 is already committed to riscv_register_file.rf[t0] by the time the
  add reaches EX. Standard WB→EX forwarding (ForwardAE=2'b01 using result) also covers
  this without needing the stall, since result is the WB mux output.
```

### Hazard unit additions summary

```systemverilog
// In riscv_hazard_unit.sv — complete updated version:

module riscv_hazard_unit(
    input logic [4:0] Rs1E, Rs2E, RdM, RdW,
    input logic RegWriteM, RegWriteW,
    input logic ResultSrcE_0,
    input logic [4:0] RdE,
    input logic [4:0] Rs1D, Rs2D,
    input logic PCSrcE,
    // NEW: CSR stall inputs
    input logic csr_instrD,   // CSR instruction currently in decode (from riscv_top_pipeline)
    input logic csr_instrE,   // CSR instruction in EX   (from execute_stage output port)
    input logic csr_instrM,   // CSR instruction in MEM  (from memory_stage output port)
    input logic csr_instrW,   // CSR instruction in WB   (from memory_stage output port)

    output logic FlushE, StallD, StallF,
    output logic [1:0] ForwardAE, ForwardBE,
    output logic FlushD
);

logic lwStall;
logic downstream_csr;
logic csr_pipeline_stall;

always @(*) begin
    // ── Forwarding (unchanged) ──────────────────────────────────────────────
    if (((Rs1E == RdM) & (RegWriteM)) & (Rs1E != 0))
        ForwardAE = 2'b10;
    else if (((Rs1E == RdW) & (RegWriteW)) & (Rs1E != 0))
        ForwardAE = 2'b01;
    else
        ForwardAE = 2'b00;

    if (((Rs2E == RdM) & (RegWriteM)) & (Rs2E != 0))
        ForwardBE = 2'b10;
    else if (((Rs2E == RdW) & (RegWriteW)) & (Rs2E != 0))
        ForwardBE = 2'b01;
    else
        ForwardBE = 2'b00;

    // ── Load-use stall (unchanged) ──────────────────────────────────────────
    lwStall = ResultSrcE_0 & ((Rs1D == RdE) | (Rs2D == RdE));

    // ── CSR serialisation stall (NEW) ───────────────────────────────────────
    downstream_csr      = csr_instrE | csr_instrM | csr_instrW;
    csr_pipeline_stall  = csr_instrD & downstream_csr;

    // ── Stall/Flush signals ─────────────────────────────────────────────────
    StallF = lwStall | csr_pipeline_stall;
    StallD = lwStall | csr_pipeline_stall;
    FlushD = PCSrcE;   // Branch/jump flush (trap flush added in Phase 5 via take_trap)
    FlushE = lwStall | PCSrcE;
    // NOTE: csr_pipeline_stall is NOT added to FlushE — the CSR instruction
    // in ID must be preserved (stall), never flushed.
end

endmodule
```

---

## Appendix: Phase Completion Checklist

```
Phase 0:
  ☐ riscv_csr_defines.svh created with all address constants and ResultSrc encoding
  ☐ Existing pipeline signals documented (all *E, *M, *W flat wires)
  ☐ WB mux identified as riscv_mux_3_1 mux_w in riscv_top_pipeline.sv
  ☐ is_system_instr stub in riscv_control_unit confirmed
  ☐ Gap list produced: no CSR file, no CSR execute, no 4th WB mux input

Phase 1:
  ☐ riscv_csr_defines.svh in rtl/RV32I/
  ☐ riscv_csr_file.sv created and instantiated in riscv_top_pipeline.sv
  ☐ riscv_csr_execute.sv created and instantiated in riscv_top_pipeline.sv (EX level)
  ☐ riscv_mux_4_1.sv created
  ☐ riscv_mux_3_1 mux_w replaced by riscv_mux_4_1 mux_w with CSRRDataW on Sel=2'b11
  ☐ riscv_control_unit.sv: csr_instr, csr_op, csr_imm_sel outputs added; ResultSrc=2'b11 for CSR
  ☐ riscv_decode_stage.sv: csr_instrE, csr_opE, csr_imm_selE, csr_uimmE, csr_addrE added to ID/EX register and output ports
  ☐ riscv_execute_stage.sv: CSRRDataE, CSRRDataM, csr_instrE, csr_instrM added
  ☐ riscv_memory_stage.sv: CSRRDataM/W, csr_instrM/W propagated to MEM/WB register
  ☐ riscv_hazard_unit.sv: csr_pipeline_stall, downstream_csr added; StallF/StallD updated
  ☐ csr_instrD_top computed in riscv_top_pipeline.sv and wired to hazard unit
  ☐ CSRRW: t0=old_mscratch, mscratch=new_value verified in simulation
  ☐ CSRRS: set bits verified
  ☐ CSRRC: clear bits verified

Phase 2:
  ☐ do_csr_write / do_csr_read computed in riscv_csr_execute from Table 7
  ☐ rd_is_x0 = (RdE==5'b0) and rs1_is_x0 = (Rs1E==5'b0) computed in riscv_top_pipeline
  ☐ csr_imm_selE selects csr_uimmE path in riscv_csr_execute operand mux
  ☐ do_csr_read propagated through EX/MEM → MEM/WB as do_csr_read_M/W
  ☐ RegWriteW gated by do_csr_read_W for CSR instructions
  ☐ All 12 cells of Table 7 pass dedicated tests
  ☐ CSRRWI with rd=x0: no read, yes write verified
  ☐ CSRRSI with uimm=0: yes read, no write verified

Phase 3:
  ☐ csr_readonly_viol logic implemented (using instrD[31:20][11:10] and do_csr_write_decode)
  ☐ csr_undef_viol decode-time lookup matches all addresses in riscv_csr_defines.svh
  ☐ do_csr_write_decode replicated in decode (not dependent on EX signals)
  ☐ illegal_csr_access output added to riscv_decode_stage.sv port list
  ☐ Write to mhartid triggers illegal_csr_access
  ☐ CSRRS to mhartid with rs1=x0 does NOT trigger illegal_csr_access
  ☐ Access to 0x900 triggers illegal_csr_access

Phase 4:
  ☐ mcycle_q increments every clock using _next pattern in riscv_csr_file.sv
  ☐ minstret_q increments on valid instruction retirement
  ☐ Software write to mcycle/minstret overrides hardware increment
  ☐ instret_inc properly gated (add validW in Phase 5 for correctness)
  ☐ rdcycle / rdcycleh decode correctly (CSRRS to 0xC00/0xC80 with Rs1=x0)
  ☐ 64-bit coherent read sequence (rdcycleh/rdcycle/rdcycleh/bne) tested
  ☐ minstret count matches actual retired instruction count

Phase 5:
  ☐ riscv_trap_ctrl.sv created and instantiated in riscv_top_pipeline.sv
  ☐ ECALL decode: opcode=SYSTEM, funct3=000, instrD[31:20]=0x000
  ☐ EBREAK decode: opcode=SYSTEM, funct3=000, instrD[31:20]=0x001
  ☐ MRET decode: opcode=SYSTEM, funct3=000, instrD[31:20]=0x302
  ☐ Trap entry: mepc=PCD (decode PC), mcause=cause, mtval=tval
  ☐ Trap entry: mstatus.MPIE=old_MIE, mstatus.MIE=0, mstatus.MPP=11
  ☐ Pipeline flush on trap: FlushD, FlushE, FlushM, FlushW all asserted
  ☐ PC redirect to mtvec_base on exception (mtvec_out from riscv_csr_file)
  ☐ MRET: PC=mepc_out, MIE←MPIE, MPIE←1, MPP←00
  ☐ ECALL: mcause=11, mepc=ecall_pc (NOT +4) verified
  ☐ Illegal instruction: mcause=2, mtval=instr_bits verified
  ☐ Nested trap prevention (MIE=0 inside handler) verified
  ☐ minstret does NOT increment for trapped instructions (FlushW gates instret_inc)
  ☐ mstatus WARL mask expanded to 32'h0000_1888 in riscv_csr_file.sv
```
