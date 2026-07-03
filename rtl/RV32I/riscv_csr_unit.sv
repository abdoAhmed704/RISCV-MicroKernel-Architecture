// =============================================================================
// Module: riscv_csr_unit
// Project: RISCV-MicroKernel-Architecture
// Description:
//   Control and Status Register (CSR) Unit for a privileged RV32I pipelined core.
//   Implements Machine (M-mode) and Supervisor (S-mode) privilege levels.
//   Handles interrupt detection, exception decoding, delegation, privilege stacks,
//   trap handling (vector routing, mepc/mcause setup), and CSR read/write access.
// =============================================================================

module riscv_csr_unit (
    // ── Global Signals ───────────────────────────────────────────────────────
    input  logic        i_csr_unit_clk,               // Global system clock
    input  logic        i_csr_unit_rst_n,             // Global active-low asynchronous reset

    // ── External Interrupt Pins ──────────────────────────────────────────────
    input  logic        i_csr_unit_mexternal,         // Machine-level external interrupt request (from PLIC)
    input  logic        i_csr_unit_sexternal,         // Supervisor-level external interrupt request (from PLIC)

    // ── Commit/Pipeline State Inputs ─────────────────────────────────────────
    input  logic        i_csr_unit_mem_wen,           // Gated memory write enable signal (to check access faults)
    input  logic [31:0] i_csr_unit_pc,                // PC of the committing instruction in Memory (M) stage
    input  logic [31:0] i_csr_unit_fault_addr,        // ALUResultM representing target memory address for fault check
    input  logic [31:0] i_csr_unit_instr,             // Instruction word of the committing instruction in M stage
    
    // ── CSR Read/Write Port Inputs ───────────────────────────────────────────
    input  logic        i_csr_unit_csr_wen,           // CSR Write Enable from Execute stage
    input  logic [1:0]  i_csr_unit_op,                // CSR Operation: 01=RW (Write), 10=RS (Set), 11=RC (Clear)
    input  logic [31:0] i_csr_unit_src,               // Resolved write data (register RD1 or zero-extended uimm)
    input  logic [11:0] i_csr_unit_csr_addr,          // Target CSR address (from instr[31:20])

    // ── Exception & Trap Signal Inputs ───────────────────────────────────────
    input  logic        i_csr_unit_illegal_instr_id,  // Illegal instruction detected in Decode stage
    input  logic        i_csr_unit_illegal_instr_exe, // Illegal instruction detected in Execute stage (tied to 0)
    input  logic        i_csr_unit_instr_addr_misaligned, // Target branch/jump PC is not 32-bit aligned
    input  logic        i_csr_unit_lw_access_fault,   // Misaligned or out-of-bounds Load access fault
    input  logic        i_csr_unit_sw_access_fault,   // Misaligned or out-of-bounds Store access fault
    input  logic        i_csr_unit_mret_wb,           // Machine-mode return from trap (MRET instruction)
    input  logic        i_csr_unit_ecall,             // ECALL (Environment Call) instruction
    input  logic        i_csr_unit_ebreak,            // EBREAK (Breakpoint) instruction
    input  logic        i_csr_unit_sret,              // Supervisor-mode return from trap (SRET instruction)

    // ── Interrupt & Latching Outputs ─────────────────────────────────────────
    output logic        o_csr_unit_ack,               // Interrupt acknowledge pulse (to clear external request)
    output logic [31:0] o_csr_unit_rdata,             // Combinational CSR read data output
    output logic [31:0] o_csr_unit_irq_handler,       // Address of trap handler vector (mtvec/stvec)
    output logic [31:0] o_csr_unit_rtrn_addr,         // Target return address for MRET/SRET (mepc/sepc)

    // ── Pipeline Redirection & Flush Outputs ─────────────────────────────────
    output logic        o_csr_unit_addr_ctrl,         // PC target selection: 1 = trap handler, 0 = return address
    output logic        o_csr_unit_mux1,              // Master PC override select: high on traps or returns
    output logic        o_csr_unit_if_flush,          // Redundant flush signal for Fetch stage
    output logic        o_csr_unit_id_flush,          // Clears instruction in Decode stage
    output logic        o_csr_unit_exe_flush,         // Clears instruction in Execute & Memory stages
    output logic        o_csr_unit_mem_flush          // Clears instruction in Writeback stage
);

    // =========================================================================
    // 1. Privilege Level Configuration
    // =========================================================================
    // Tracks current CPU execution mode. 2'b11 = Machine (M), 2'b01 = Supervisor (S)
    logic [1:0] priv_mode_q; 

    // =========================================================================
    // 2. Physical CSR Register Definitions
    // =========================================================================
    logic [31:0] mstatus_q;   // Machine Status (interrupt switches + privilege stacks)
    logic [31:0] mie_q;       // Machine Interrupt Enable
    logic [31:0] mtvec_q;     // Machine Trap Vector Base Address
    logic [31:0] stvec_q;     // Supervisor Trap Vector Base Address
    logic [31:0] medeleg_q;   // Machine Exception Delegation Register
    logic [31:0] mideleg_q;   // Machine Interrupt Delegation Register
    logic [31:0] mscratch_q;  // Machine Scratch register (used for context switches)
    logic [31:0] sscratch_q;  // Supervisor Scratch register
    logic [31:0] mepc_q;      // Machine Exception Program Counter
    logic [31:0] sepc_q;      // Supervisor Exception Program Counter
    logic [31:0] mcause_q;    // Machine Cause code
    logic [31:0] scause_q;    // Supervisor Cause code
    logic [31:0] mtval_q;     // Machine Bad Address/Instruction Value
    logic [31:0] stval_q;     // Supervisor Bad Address/Instruction Value

    // Performance counters and timers (64-bit split registers)
    logic [63:0] mcycle_q;    // Cycles elapsed since reset
    logic [63:0] minstret_q;  // Instructions retired (committed)
    logic [63:0] mtime;       // System time counter
    logic [63:0] mtimecmp;    // Machine Timer Compare register
    logic [63:0] stimecmp;    // Supervisor Timer Compare register

    // =========================================================================
    // 3. ISA & Status Views (Read-Only Specs)
    // =========================================================================
    // misa (Machine ISA Register): Reports supported instruction set
    logic [31:0] misa;
    assign misa = {
        2'b01,                              // MXL = 1 (32-bit Architecture)
        4'b0,                               // Reserved
        26'b00000001000001000100000101       // RV-IMAC, Machine + Supervisor privilege modes supported
    };

    // sstatus (Supervisor Status Register): Virtualized read-only S-mode view of mstatus fields
    logic [31:0] sstatus;
    assign sstatus = {
        23'b0,
        mstatus_q[8],                       // SPP  (Supervisor Previous Privilege)
        2'b0,
        mstatus_q[5],                       // SPIE (Supervisor Previous Interrupt Enable)
        3'b0,
        mstatus_q[1],                       // SIE  (Supervisor Interrupt Enable)
        1'b0
    };

    // =========================================================================
    // 4. Enabled Interrupts & Delegation/Routing Logic
    // =========================================================================
    // Individual interrupt inputs gated by local enable bits in mie_q
    logic meip_active, mtip_active, seip_active, stip_active;
    assign meip_active = i_csr_unit_mexternal && mie_q[11]; // Machine External Interrupt
    assign mtip_active = (mtime >= mtimecmp)  && mie_q[7];  // Machine Timer Interrupt
    assign seip_active = i_csr_unit_sexternal && mie_q[9];  // Supervisor External Interrupt
    assign stip_active = (mtime >= stimecmp)  && mie_q[5];  // Supervisor Timer Interrupt

    // Checks delegation registers to see if interrupts route to S-mode instead of M-mode
    logic meip_delegated, mtip_delegated, seip_delegated, stip_delegated;
    assign meip_delegated = mideleg_q[11];
    assign mtip_delegated = mideleg_q[7];
    assign seip_delegated = mideleg_q[9];
    assign stip_delegated = mideleg_q[5];

    // M-mode global interrupts are enabled if:
    // 1. Current mode is lower than M-mode (S-mode/U-mode) OR
    // 2. Current mode is M-mode and mstatus.MIE is set.
    logic m_interrupts_globally_enabled;
    assign m_interrupts_globally_enabled = (priv_mode_q < 2'b11) || ((priv_mode_q == 2'b11) && mstatus_q[3]);

    // S-mode global interrupts are enabled if:
    // 1. Current mode is lower than S-mode (U-mode) OR
    // 2. Current mode is S-mode and mstatus.SIE is set.
    logic s_interrupts_globally_enabled;
    assign s_interrupts_globally_enabled = (priv_mode_q < 2'b01) || ((priv_mode_q == 2'b01) && mstatus_q[1]);

    // Evaluation of active Machine-mode traps
    logic m_int_active;
    logic [31:0] m_int_cause;
    always_comb begin
        m_int_active = 1'b0;
        m_int_cause = 32'h0;
        if (m_interrupts_globally_enabled) begin
            if (meip_active && !meip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd11}; // Cause 11: Machine external interrupt
            end else if (mtip_active && !mtip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd7};  // Cause 7: Machine timer interrupt
            end else if (seip_active && !seip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd9};  // Cause 9: Supervisor external interrupt
            end else if (stip_active && !stip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd5};  // Cause 5: Supervisor timer interrupt
            end
        end
    end

    // Evaluation of active Supervisor-mode traps (can only trigger if current privilege is not M-mode)
    logic s_int_active;
    logic [31:0] s_int_cause;
    always_comb begin
        s_int_active = 1'b0;
        s_int_cause = 32'h0;
        if (priv_mode_q < 2'b11) begin
            if (s_interrupts_globally_enabled) begin
                if (meip_active && meip_delegated) begin
                    s_int_active = 1'b1;
                    s_int_cause = {1'b1, 31'd11};
                end else if (mtip_active && mtip_delegated) begin
                    s_int_active = 1'b1;
                    s_int_cause = {1'b1, 31'd7};
                end else if (seip_active && seip_delegated) begin
                    s_int_active = 1'b1;
                    s_int_cause = {1'b1, 31'd9};
                end else if (stip_active && stip_delegated) begin
                    s_int_active = 1'b1;
                    s_int_cause = {1'b1, 31'd5};
                end
            end
        end
    end

    // Final consolidated interrupt signals
    logic int_active;
    logic [31:0] int_cause;
    logic int_to_s;
    assign int_active = m_int_active || s_int_active;
    assign int_cause  = m_int_active ? m_int_cause : s_int_cause;
    assign int_to_s   = m_int_active ? 1'b0 : 1'b1;

    // Do not latch interrupts on the same clock cycle that MRET or SRET is returning to prevent state thrashing
    logic take_interrupt;
    assign take_interrupt = int_active && !i_csr_unit_mret_wb && !i_csr_unit_sret;

    // =========================================================================
    // 5. CSR Legality & Permission Checks
    // =========================================================================
    logic csr_instr_active;
    assign csr_instr_active = (i_csr_unit_op != 2'b00); // Decodes if instruction targets CSR registers

    logic priv_violation; // Checks if current privilege level is too low for the CSR address
    assign priv_violation = (priv_mode_q < i_csr_unit_csr_addr[9:8]);

    logic write_to_ro;    // Checks if instruction tries to write to a read-only CSR address range
    assign write_to_ro = (i_csr_unit_csr_addr[11:10] == 2'b11) && i_csr_unit_csr_wen;

    logic addr_invalid;   // Checks if target CSR address is implemented in hardware
    always_comb begin
        addr_invalid = 1'b0;
        case (i_csr_unit_csr_addr)
            12'h300, 12'h100, 12'h301, 12'h304, 12'h104, 12'h305, 12'h105,
            12'h302, 12'h303, 12'h340, 12'h140, 12'h341, 12'h141, 12'h342,
            12'h142, 12'h343, 12'h143, 12'h344, 12'h144, 12'hB00, 12'hB80,
            12'hB02, 12'hB82, 12'hC00, 12'hC80, 12'hC02, 12'hC82,
            12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'h180, 12'h14D, 12'h15D,
            12'h30D, 12'h31D: addr_invalid = 1'b0; // Valid addresses
            default:          addr_invalid = 1'b1; // Invalid/unimplemented address
        endcase
    end

    logic csr_illegal;
    assign csr_illegal = csr_instr_active && (addr_invalid || priv_violation || write_to_ro);

    // =========================================================================
    // 6. Exception Priority Decoding
    // =========================================================================
    logic exc_active;
    logic [31:0] exc_cause;
    logic [31:0] exc_tval;
    logic exc_delegated;

    always_comb begin
        exc_active = 1'b1;
        exc_cause = 32'h0;
        exc_tval = 32'h0;
        
        // Priority exception selection logic
        if (i_csr_unit_illegal_instr_id || i_csr_unit_illegal_instr_exe || csr_illegal) begin
            exc_cause = 32'd2; // Illegal instruction exception
            exc_tval = i_csr_unit_instr;
        end else if (i_csr_unit_instr_addr_misaligned) begin
            exc_cause = 32'd0; // Instruction address misaligned exception
            exc_tval = i_csr_unit_fault_addr;
        end else if (i_csr_unit_ecall) begin
            // Environment call cause codes (depends on current privilege level)
            exc_cause = (priv_mode_q == 2'b11) ? 32'd11 : 32'd9;
            exc_tval = 32'h0;
        end else if (i_csr_unit_ebreak) begin
            exc_cause = 32'd3; // Breakpoint exception
            exc_tval = i_csr_unit_pc;
        end else if (i_csr_unit_sw_access_fault) begin
            exc_cause = 32'd7; // Store access fault exception
            exc_tval = i_csr_unit_fault_addr;
        end else if (i_csr_unit_lw_access_fault) begin
            exc_cause = 32'd5; // Load access fault exception
            exc_tval = i_csr_unit_fault_addr;
        end else begin
            exc_active = 1'b0; // No exceptions active
        end
    end

    // Exception routes to S-mode if delegated by medeleg and privilege is lower than M-mode
    assign exc_delegated = exc_active && medeleg_q[exc_cause[4:0]] && (priv_mode_q < 2'b11);

    // =========================================================================
    // 7. Trap Decision & Redirect Routing
    // =========================================================================
    logic take_trap;
    assign take_trap = take_interrupt || exc_active;

    logic trap_to_s;
    assign trap_to_s = take_interrupt ? int_to_s : exc_delegated;

    logic [31:0] final_cause;
    assign final_cause = take_interrupt ? int_cause : exc_cause;

    // Trap target PC vector router
    logic [31:0] trap_target_pc;
    always_comb begin
        if (trap_to_s) begin
            // S-mode Trap Vector base address
            if (stvec_q[1:0] == 2'b01 && final_cause[31])
                // Vectored mode: Base + 4 * Cause Offset
                trap_target_pc = {stvec_q[31:2], 2'b00} + {final_cause[29:0], 2'b00};
            else
                // Direct mode: Base Address
                trap_target_pc = {stvec_q[31:2], 2'b00};
        end else begin
            // M-mode Trap Vector base address
            if (mtvec_q[1:0] == 2'b01 && final_cause[31])
                trap_target_pc = {mtvec_q[31:2], 2'b00} + {final_cause[29:0], 2'b00};
            else
                trap_target_pc = {mtvec_q[31:2], 2'b00};
        end
    end

    // =========================================================================
    // 8. CSR Read Port (Mux Decoding)
    // =========================================================================
    logic [31:0] mip_val; // Evaluates interrupt pending status flags dynamically
    assign mip_val = { 20'b0, i_csr_unit_mexternal, 1'b0, i_csr_unit_sexternal, 1'b0, (mtime >= mtimecmp), 1'b0, (mtime >= stimecmp), 5'b0 };

    always_comb begin
        o_csr_unit_rdata = 32'h0;
        if (csr_instr_active && !csr_illegal) begin
            case (i_csr_unit_csr_addr)
                12'h300: o_csr_unit_rdata = mstatus_q;
                12'h100: o_csr_unit_rdata = sstatus;
                12'h301: o_csr_unit_rdata = misa;
                12'h304: o_csr_unit_rdata = mie_q;
                12'h104: o_csr_unit_rdata = mie_q & mideleg_q;
                12'h305: o_csr_unit_rdata = mtvec_q;
                12'h105: o_csr_unit_rdata = stvec_q;
                12'h302: o_csr_unit_rdata = medeleg_q;
                12'h303: o_csr_unit_rdata = mideleg_q;
                12'h340: o_csr_unit_rdata = mscratch_q;
                12'h140: o_csr_unit_rdata = sscratch_q;
                12'h341: o_csr_unit_rdata = mepc_q;
                12'h141: o_csr_unit_rdata = sepc_q;
                12'h342: o_csr_unit_rdata = mcause_q;
                12'h142: o_csr_unit_rdata = scause_q;
                12'h343: o_csr_unit_rdata = mtval_q;
                12'h143: o_csr_unit_rdata = stval_q;
                12'h344: o_csr_unit_rdata = mip_val;
                12'h144: o_csr_unit_rdata = mip_val & mideleg_q;
                12'hB00: o_csr_unit_rdata = mcycle_q[31:0];
                12'hB80: o_csr_unit_rdata = mcycle_q[63:32];
                12'hB02: o_csr_unit_rdata = minstret_q[31:0];
                12'hB82: o_csr_unit_rdata = minstret_q[63:32];
                12'hC00: o_csr_unit_rdata = mcycle_q[31:0];
                12'hC80: o_csr_unit_rdata = mcycle_q[63:32];
                12'hC02: o_csr_unit_rdata = minstret_q[31:0];
                12'hC82: o_csr_unit_rdata = minstret_q[63:32];
                12'hF11: o_csr_unit_rdata = 32'h0; // mvendorid
                12'hF12: o_csr_unit_rdata = 32'h0; // marchid
                12'hF13: o_csr_unit_rdata = 32'h0; // mimpid
                12'hF14: o_csr_unit_rdata = 32'h0; // mhartid
                12'h180: o_csr_unit_rdata = 32'h0; // satp (no translation/virtualization supported)
                12'h14D: o_csr_unit_rdata = stimecmp[31:0];
                12'h15D: o_csr_unit_rdata = stimecmp[63:32];
                12'h30D: o_csr_unit_rdata = mtimecmp[31:0];
                12'h31D: o_csr_unit_rdata = mtimecmp[63:32];
                default: o_csr_unit_rdata = 32'h0;
            endcase
        end
    end

    // =========================================================================
    // 9. CSR Write Port (Operand Mask Logic)
    // =========================================================================
    logic [31:0] csr_wdata;
    always_comb begin
        case (i_csr_unit_op)
            2'b01:   csr_wdata = i_csr_unit_src;                    // CSRRW: Read/Write (Direct overwrite)
            2'b10:   csr_wdata = o_csr_unit_rdata | i_csr_unit_src;  // CSRRS: Read/Set bits
            2'b11:   csr_wdata = o_csr_unit_rdata & (~i_csr_unit_src); // CSRRC: Read/Clear bits
            default: csr_wdata = 32'h0;
        endcase
    end

    logic csr_write_active;
    assign csr_write_active = i_csr_unit_csr_wen && !csr_illegal;

    // =========================================================================
    // 10. Sequential Register Update Block
    // =========================================================================
    always_ff @(posedge i_csr_unit_clk or negedge i_csr_unit_rst_n) begin
        if (!i_csr_unit_rst_n) begin
            // Reset state registers to defaults
            priv_mode_q <= 2'b11; // Boots in Machine mode
            mstatus_q   <= 32'h0;
            mie_q       <= 32'h0;
            mtvec_q     <= 32'h0;
            stvec_q     <= 32'h0;
            medeleg_q   <= 32'h0;
            mideleg_q   <= 32'h0;
            mscratch_q  <= 32'h0;
            sscratch_q  <= 32'h0;
            mepc_q      <= 32'h0;
            sepc_q      <= 32'h0;
            mcause_q    <= 32'h0;
            scause_q    <= 32'h0;
            mtval_q     <= 32'h0;
            stval_q     <= 32'h0;
            mcycle_q    <= 64'h0;
            minstret_q  <= 64'h0;
            mtime       <= 64'h0;
            mtimecmp    <= 64'hFFFFFFFFFFFFFFFF;
            stimecmp    <= 64'hFFFFFFFFFFFFFFFF;
        end else begin
            // Increment counters on every clock cycle
            mcycle_q <= mcycle_q + 1;
            mtime    <= mtime + 1;

            // Increment retired instruction counter when a valid instruction commits (excludes traps and returns)
            if (i_csr_unit_instr != 32'h0 && !take_trap && !i_csr_unit_mret_wb && !i_csr_unit_sret) begin
                minstret_q <= minstret_q + 1;
            end

            // ── Trap Latching Sequence ───────────────────────────────────────
            if (take_trap) begin
                if (trap_to_s) begin
                    // Latch state to Supervisor status registers
                    sepc_q       <= i_csr_unit_pc;
                    scause_q     <= final_cause;
                    stval_q      <= (m_int_active || s_int_active) ? 32'h0 : exc_tval;
                    mstatus_q[8] <= priv_mode_q[0]; // SPP  (save old privilege mode bit 0)
                    mstatus_q[5] <= mstatus_q[1];   // SPIE <= SIE (save interrupt enable)
                    mstatus_q[1] <= 1'b0;           // SIE <= 0   (disable S-interrupts globally)
                    priv_mode_q  <= 2'b01;          // Update privilege level to S-mode
                end else begin
                    // Latch state to Machine status registers
                    mepc_q           <= i_csr_unit_pc;
                    mcause_q         <= final_cause;
                    mtval_q          <= (m_int_active || s_int_active) ? 32'h0 : exc_tval;
                    mstatus_q[12:11] <= priv_mode_q;     // MPP  (save old privilege level)
                    mstatus_q[7]     <= mstatus_q[3];    // MPIE <= MIE
                    mstatus_q[3]     <= 1'b0;            // MIE  <= 0 (disable M-interrupts globally)
                    priv_mode_q      <= 2'b11;          // Update privilege level to M-mode
                end
            // ── MRET Privilege Stack Restore ─────────────────────────────────
            end else if (i_csr_unit_mret_wb) begin
                priv_mode_q      <= mstatus_q[12:11]; // Restore privilege mode from MPP
                mstatus_q[3]     <= mstatus_q[7];    // MIE  <= MPIE (restore interrupt enable)
                mstatus_q[7]     <= 1'b1;            // MPIE <= 1
                mstatus_q[12:11] <= 2'b00;           // MPP  <= 00 (Clear MPP)
            // ── SRET Privilege Stack Restore ─────────────────────────────────
            end else if (i_csr_unit_sret) begin
                priv_mode_q  <= {1'b0, mstatus_q[8]}; // Restore S-mode privilege from SPP
                mstatus_q[1] <= mstatus_q[5];        // SIE  <= SPIE (restore interrupt enable)
                mstatus_q[5] <= 1'b1;                // SPIE <= 1
                mstatus_q[8] <= 1'b0;                // SPP  <= 0
            // ── Standard Register Write operations ───────────────────────────
            end else if (csr_write_active) begin
                case (i_csr_unit_csr_addr)
                    12'h300: begin // mstatus write (only writable fields)
                        mstatus_q[12:11] <= csr_wdata[12:11]; // MPP
                        mstatus_q[8]     <= csr_wdata[8];     // SPP
                        mstatus_q[7]     <= csr_wdata[7];     // MPIE
                        mstatus_q[5]     <= csr_wdata[5];     // SPIE
                        mstatus_q[3]     <= csr_wdata[3];     // MIE
                        mstatus_q[1]     <= csr_wdata[1];     // SIE
                    end
                    12'h100: begin // sstatus write (writeable S-mode fields)
                        mstatus_q[8] <= csr_wdata[8];         // SPP
                        mstatus_q[5] <= csr_wdata[5];         // SPIE
                        mstatus_q[1] <= csr_wdata[1];         // SIE
                    end
                    12'h304: mie_q <= csr_wdata & 32'h00000AAA; // mie (M+S external, timer, software bits)
                    12'h104: mie_q <= (mie_q & ~mideleg_q) | (csr_wdata & mideleg_q & 32'h00000AAA); // sie
                    12'h305: mtvec_q <= csr_wdata;
                    12'h105: stvec_q <= csr_wdata;
                    12'h302: medeleg_q <= csr_wdata;
                    12'h303: mideleg_q <= csr_wdata & 32'h00000222;
                    12'h340: mscratch_q <= csr_wdata;
                    12'h140: sscratch_q <= csr_wdata;
                    12'h341: mepc_q <= {csr_wdata[31:2], 2'b00}; // Word alignment constraint
                    12'h141: sepc_q <= {csr_wdata[31:2], 2'b00}; // Word alignment constraint
                    12'h342: mcause_q <= csr_wdata;
                    12'h142: scause_q <= csr_wdata;
                    12'h343: mtval_q <= csr_wdata;
                    12'h143: stval_q <= csr_wdata;
                    12'hB00: mcycle_q[31:0] <= csr_wdata;
                    12'hB80: mcycle_q[63:32] <= csr_wdata;
                    12'hB02: minstret_q[31:0] <= csr_wdata;
                    12'hB82: minstret_q[63:32] <= csr_wdata;
                    12'h14D: stimecmp[31:0] <= csr_wdata;
                    12'h15D: stimecmp[63:32] <= csr_wdata;
                    12'h30D: mtimecmp[31:0] <= csr_wdata;
                    12'h31D: mtimecmp[63:32] <= csr_wdata;
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // 11. Combinational Output Assignments
    // =========================================================================
    assign o_csr_unit_ack         = take_interrupt;     // Acknowledge pulse back to external controller
    assign o_csr_unit_irq_handler = trap_target_pc;      // Target trap handler PC vector
    assign o_csr_unit_rtrn_addr   = i_csr_unit_mret_wb ? mepc_q : sepc_q; // Return PC selector
    assign o_csr_unit_addr_ctrl   = take_trap;          // Directs PC Mux to jump to handler vs return address
    
    // Master PC select control is asserted on any active trap, MRET, or SRET redirection
    assign o_csr_unit_mux1        = take_trap || i_csr_unit_mret_wb || i_csr_unit_sret;
    
    // Pipeline stage clears/flushes are triggered together whenever the PC is redirected
    assign o_csr_unit_if_flush    = o_csr_unit_mux1;
    assign o_csr_unit_id_flush    = o_csr_unit_mux1;
    assign o_csr_unit_exe_flush   = o_csr_unit_mux1;
    assign o_csr_unit_mem_flush   = o_csr_unit_mux1;

endmodule
