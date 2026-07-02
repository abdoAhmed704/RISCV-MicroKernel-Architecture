# CSR Unit Port-by-Port Signal Tracing

This document provides a precise, port-by-port trace of the `riscv_csr_unit` instantiation in [riscv_top_pipeline.sv](file:///c:/Users/ABDOU/Desktop/GP_folder/RISC-V/repos/RISCV-MicroKernel-Architecture/rtl/RV32I/riscv_top_pipeline.sv). It explains where every input signal originates (from Fetch down to Memory) and where every output signal goes to redirect/flush the pipeline.

---

## 1. Input Ports (Origins & Propagation Paths)

### `i_csr_unit_clk`
*   **Origin:** Global system clock signal (`clk`).

### `i_csr_unit_rst_n`
*   **Origin:** Global system active-low asynchronous reset (`rst_n`).

### `i_csr_unit_mexternal`
*   **Origin:** Core boundary input port (`mexternal`). Comes from the external system (e.g. a platform interrupt controller or peripheral pin).

### `i_csr_unit_sexternal`
*   **Origin:** Core boundary input port (`sexternal`). Comes from the external system for Supervisor-level interrupts.

### `i_csr_unit_mem_wen` ◄ `MemWriteM`
*   **Origin:** Generated in the Decode stage by the Control Unit (`MemWriteD`).
*   **Path:** `MemWriteD` (D) ──[D/E Register]──► `MemWriteE` (E) ──[E/M Register]──► `MemWriteM` (M).

### `i_csr_unit_pc` ◄ `PCM`
*   **Origin:** Program Counter register in the Fetch stage (`PCF`).
*   **Path:** `PCF` (F) ──[F/D Register]──► `PCD` (D) ──[D/E Register]──► `PCE` (E) ──[E/M Register]──► `PCM` (M).

### `i_csr_unit_fault_addr` ◄ `ALUResultM`
*   **Origin:** Memory address computed by the ALU in the Execute stage (`ALUResultE`).
*   **Path:** `ALUResultE` (E) ──[E/M Register]──► `ALUResultM` (M).

### `i_csr_unit_instr` ◄ `instrM`
*   **Origin:** Fetched instruction read from instruction memory in Fetch (`instrF`).
*   **Path:** `instrF` (F) ──[F/D Register]──► `instrD` (D) ──[D/E Register]──► `instrE` (E) ──[E/M Register]──► `instrM` (M).

### `i_csr_unit_csr_wen` ◄ `csr_wenM`
*   **Origin:** Decoded in Decode (`csr_wenD`). High if the instruction writes to a CSR, applying the Zicsr Write Suppression Rules.
*   **Path:** `csr_wenD` (D) ──[D/E Register]──► `csr_wenE` (E) ──[E/M Register]──► `csr_wenM` (M).

### `i_csr_unit_op` ◄ `csr_opM`
*   **Origin:** Decoded in Decode (`csr_opD = instrD[13:12]`).
*   **Path:** `csr_opD` (D) ──[D/E Register]──► `csr_opE` (E) ──[E/M Register]──► `csr_opM` (M).

### `i_csr_unit_src` ◄ `csr_srcM`
*   **Origin:** Resolved in Execute (`csr_srcE`) based on operand source:
    *   If `csr_imm_selE` is 1 (immediate CSR write): `{27'b0, csr_uimmE}`.
    *   If `csr_imm_selE` is 0 (register CSR write): The forwarded register value `RD1E` (`mux_R1_out`).
*   **Path:** `csr_srcE` (E) ──[E/M Register]──► `csr_srcM` (M).

### `i_csr_unit_csr_addr` ◄ `csr_addrM`
*   **Origin:** Decoded in Decode (`csr_addrD = instrD[31:20]`).
*   **Path:** `csr_addrD` (D) ──[D/E Register]──► `csr_addrE` (E) ──[E/M Register]──► `csr_addrM` (M).

### `i_csr_unit_illegal_instr_id` ◄ `illegal_instr_id_M`
*   **Origin:** Decoded in Decode (`illegal_instr_id_D`). High if the opcode is invalid or if system parameters are misconfigured.
*   **Path:** `illegal_instr_id_D` (D) ──[D/E Register]──► `illegal_instr_id_E` (E) ──[E/M Register]──► `illegal_instr_id_M` (M).

### `i_csr_unit_illegal_instr_exe` ◄ `1'b0`
*   **Origin:** Tied to 0. (Privilege checks and address boundary checks are performed internally by the CSR unit logic).

### `i_csr_unit_instr_addr_misaligned` ◄ `instr_addr_misaligned_M`
*   **Origin:** Computed in Execute (`instr_addr_misaligned_E`). High if a taken branch/jump target `PCTargetE_new` is not word-aligned.
*   **Path:** `instr_addr_misaligned_E` (E) ──[E/M Register]──► `instr_addr_misaligned_M` (M).

### `i_csr_unit_lw_access_fault` ◄ `lw_access_fault_M`
*   **Origin:** Computed in Memory stage (`lw_access_fault_M`). High if a Load instruction targets an invalid/out-of-bounds address (`ALUResultM >= 16384`) or is misaligned.

### `i_csr_unit_sw_access_fault` ◄ `sw_access_fault_M`
*   **Origin:** Computed in Memory stage (`sw_access_fault_M`). High if a Store instruction targets an invalid/out-of-bounds address (`ALUResultM >= 16384`) or is misaligned.

### `i_csr_unit_mret_wb` ◄ `mretM`
*   **Origin:** Decoded in Decode (`mretD`). High if instruction is `mret`.
*   **Path:** `mretD` (D) ──[D/E Register]──► `mretE` (E) ──[E/M Register]──► `mretM` (M).

### `i_csr_unit_ecall` ◄ `ecallM`
*   **Origin:** Decoded in Decode (`ecallD`). High if instruction is `ecall`.
*   **Path:** `ecallD` (D) ──[D/E Register]──► `ecallE` (E) ──[E/M Register]──► `ecallM` (M).

### `i_csr_unit_ebreak` ◄ `ebreakM`
*   **Origin:** Decoded in Decode (`ebreakD`). High if instruction is `ebreak`.
*   **Path:** `ebreakD` (D) ──[D/E Register]──► `ebreakE` (E) ──[E/M Register]──► `ebreakM` (M).

### `i_csr_unit_sret` ◄ `sretM`
*   **Origin:** Decoded in Decode (`sretD`). High if instruction is `sret`.
*   **Path:** `sretD` (D) ──[D/E Register]──► `sretE` (E) ──[E/M Register]──► `sretM` (M).

---

## 2. Output Ports (Destinations & Controls)

### `o_csr_unit_ack` ──► `irq_ack`
*   **Destination:** Core boundary output pin `irq_ack`.
*   **Purpose:** High for 1 cycle to signal to the external interrupt controller (e.g., PLIC) that the core has successfully latched and accepted the pending interrupt, allowing the controller to de-assert its request pin.

### `o_csr_unit_rdata` ──► `CSRRDataW`
*   **Destination:** Registered by an always_ff block into `CSRRDataW` at the end of the Memory stage. `CSRRDataW` then connects to port `D` (input index `2'b11`) of the 4-to-1 writeback multiplexer `mux_w` to write the CSR contents into the register file.

### `o_csr_unit_irq_handler` ──► Fetch PC Mux
*   **Destination:** Connects to the Fetch PC target multiplexer:
    `assign PCTargetE_to_fetch = o_csr_unit_mux1 ? (o_csr_unit_addr_ctrl ? o_csr_unit_irq_handler : o_csr_unit_rtrn_addr) : PCTargetE;`
*   **Purpose:** Provides the target address of the trap handler (`mtvec` or `stvec`) to the Fetch Stage.

### `o_csr_unit_rtrn_addr` ──► Fetch PC Mux
*   **Destination:** Connects to the Fetch PC target multiplexer (see above).
*   **Purpose:** Provides the return address (`mepc` or `sepc`) to the Fetch Stage when returning from a trap via `mret`/`sret`.

### `o_csr_unit_addr_ctrl` ──► Fetch PC Mux Selection
*   **Destination:** Controls the Fetch PC target selection logic (see above).
*   **Purpose:** When high (active trap), it forces the Fetch PC Mux to select the trap handler vector (`o_csr_unit_irq_handler`). When low (active return), it forces the PC Mux to select the return address (`o_csr_unit_rtrn_addr`).

### `o_csr_unit_mux1` ──► Fetch PC Source and Write-Enable Control
*   **Destination:** 
    1.  Standard branch/jump selector override: `assign PCSrcE_to_fetch = PCSrcE || o_csr_unit_mux1;`
    2.  PC register write enable logic: `(!StallF || o_csr_unit_mux1)`.
*   **Purpose:** Overrides normal branch/jump control to steer Fetch to the trap/return target immediately. It also forces the Fetch PC register to write the new target address, bypassing any pipeline stalls caused by data hazards.

### `o_csr_unit_if_flush`
*   *Note:* Legally connected but redundant. The F/D stage pipeline register is already cleared by `o_csr_unit_id_flush` which fires at the exact same moment.

### `o_csr_unit_id_flush` ──► Fetch Stage
*   **Destination:** Active-high clear input `CLR` of the Fetch Stage pipeline register:
    `CLR(FlushD || o_csr_unit_id_flush)`.
*   **Purpose:** Instantly flushes (clears) the instruction register in Decode (`instrD`) on a trap or return.

### `o_csr_unit_exe_flush` ──► Decode Stage and Execute Stage
*   **Destination:** 
    1.  Active-high clear input `CLR` of the Decode Stage pipeline register: `CLR(FlushE || o_csr_unit_exe_flush)`.
    2.  Active-high clear input `CLR` of the Execute Stage: `CLR(o_csr_unit_exe_flush)`.
*   **Purpose:** Instantly flushes instructions currently in the Execute (E) and Memory (M) stages.

### `o_csr_unit_mem_flush` ──► Memory Stage
*   **Destination:** 
    1.  Active-high clear input `flushW` of the Memory Stage pipeline register.
    2.  Active-high clear input of the `CSRRDataW` latch.
*   **Purpose:** Instantly flushes instructions currently in the Writeback (W) stage.
