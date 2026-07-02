module riscv_csr_unit (
    input  logic        i_csr_unit_clk,
    input  logic        i_csr_unit_rst_n,
    input  logic        i_csr_unit_mexternal,
    input  logic        i_csr_unit_sexternal,
    input  logic        i_csr_unit_mem_wen,
    input  logic [31:0] i_csr_unit_pc,
    input  logic [31:0] i_csr_unit_fault_addr,
    input  logic [31:0] i_csr_unit_instr,
    input  logic        i_csr_unit_csr_wen,
    input  logic [1:0]  i_csr_unit_op,
    input  logic [31:0] i_csr_unit_src,
    input  logic [11:0] i_csr_unit_csr_addr,
    input  logic        i_csr_unit_illegal_instr_id,
    input  logic        i_csr_unit_illegal_instr_exe,
    input  logic        i_csr_unit_instr_addr_misaligned,
    input  logic        i_csr_unit_lw_access_fault,
    input  logic        i_csr_unit_sw_access_fault,
    input  logic        i_csr_unit_mret_wb,
    input  logic        i_csr_unit_ecall,
    input  logic        i_csr_unit_ebreak,
    input  logic        i_csr_unit_sret,
    output logic        o_csr_unit_ack,
    output logic [31:0] o_csr_unit_rdata,
    output logic [31:0] o_csr_unit_irq_handler,
    output logic [31:0] o_csr_unit_rtrn_addr,
    output logic        o_csr_unit_addr_ctrl,
    output logic        o_csr_unit_mux1,
    output logic        o_csr_unit_if_flush,
    output logic        o_csr_unit_id_flush,
    output logic        o_csr_unit_exe_flush,
    output logic        o_csr_unit_mem_flush
);

    // ── Privilege Level ───────────────────────────────────────────────────────
    logic [1:0] priv_mode_q; // 2'b11 = M-mode, 2'b01 = S-mode

    // ── CSR registers ─────────────────────────────────────────────────────────
    logic [31:0] mstatus_q;
    logic [31:0] mie_q;
    logic [31:0] mtvec_q;
    logic [31:0] stvec_q;
    logic [31:0] medeleg_q;
    logic [31:0] mideleg_q;
    logic [31:0] mscratch_q;
    logic [31:0] sscratch_q;
    logic [31:0] mepc_q;
    logic [31:0] sepc_q;
    logic [31:0] mcause_q;
    logic [31:0] scause_q;
    logic [31:0] mtval_q;
    logic [31:0] stval_q;

    // Performance counters and timers
    logic [63:0] mcycle_q;
    logic [63:0] minstret_q;
    logic [63:0] mtime;
    logic [63:0] mtimecmp;
    logic [63:0] stimecmp;

    // ── ISA Reporting (misa) ──────────────────────────────────────────────────
    // MXL=1 (32-bit), extensions: IMAC (bits 8, 12, 0, 2), M/S-modes (bits 12, 18)
    logic [31:0] misa;
    assign misa = {
        2'b01,                              // MXL = 1 (RV32)
        4'b0,                               // Reserved
        26'b00000001000001000100000101       // RV-IMAC, M & S modes
    };

    // ── Supervisor view of mstatus (sstatus) ──────────────────────────────────
    logic [31:0] sstatus;
    assign sstatus = {
        23'b0,
        mstatus_q[8],                       // SPP (Previous privilege mode)
        2'b0,
        mstatus_q[5],                       // SPIE (Previous interrupt enable)
        3'b0,
        mstatus_q[1],                       // SIE (Supervisor interrupt enable)
        1'b0
    };

    // ── Enabled Interrupts & Routing ──────────────────────────────────────────
    logic meip_active, mtip_active, seip_active, stip_active;
    assign meip_active = i_csr_unit_mexternal && mie_q[11];
    assign mtip_active = (mtime >= mtimecmp)  && mie_q[7];
    assign seip_active = i_csr_unit_sexternal && mie_q[9];
    assign stip_active = (mtime >= stimecmp)  && mie_q[5];

    logic meip_delegated, mtip_delegated, seip_delegated, stip_delegated;
    assign meip_delegated = mideleg_q[11];
    assign mtip_delegated = mideleg_q[7];
    assign seip_delegated = mideleg_q[9];
    assign stip_delegated = mideleg_q[5];

    // M-mode interrupt enable check
    logic m_interrupts_globally_enabled;
    assign m_interrupts_globally_enabled = (priv_mode_q < 2'b11) || ((priv_mode_q == 2'b11) && mstatus_q[3]);

    // S-mode interrupt enable check
    logic s_interrupts_globally_enabled;
    assign s_interrupts_globally_enabled = (priv_mode_q < 2'b01) || ((priv_mode_q == 2'b01) && mstatus_q[1]);

    logic m_int_active;
    logic [31:0] m_int_cause;
    always_comb begin
        m_int_active = 1'b0;
        m_int_cause = 32'h0;
        if (m_interrupts_globally_enabled) begin
            if (meip_active && !meip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd11}; // Machine external interrupt
            end else if (mtip_active && !mtip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd7};  // Machine timer interrupt
            end else if (seip_active && !seip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd9};  // Supervisor external interrupt
            end else if (stip_active && !stip_delegated) begin
                m_int_active = 1'b1;
                m_int_cause = {1'b1, 31'd5};  // Supervisor timer interrupt
            end
        end
    end

    logic s_int_active;
    logic [31:0] s_int_cause;
    always_comb begin
        s_int_active = 1'b0;
        s_int_cause = 32'h0;
        if (priv_mode_q < 2'b11) begin // Can only trigger S-mode interrupt if not in M-mode
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

    logic int_active;
    logic [31:0] int_cause;
    logic int_to_s;
    assign int_active = m_int_active || s_int_active;
    assign int_cause  = m_int_active ? m_int_cause : s_int_cause;
    assign int_to_s   = m_int_active ? 1'b0 : 1'b1;

    logic take_interrupt;
    // Do not interrupt while handling an xRET instruction in the memory stage
    assign take_interrupt = int_active && !i_csr_unit_mret_wb && !i_csr_unit_sret;

    // ── CSR Legality Checks ───────────────────────────────────────────────────
    logic csr_instr_active;
    assign csr_instr_active = (i_csr_unit_op != 2'b00);

    logic priv_violation;
    logic write_to_ro;
    logic addr_invalid;

    assign priv_violation = (priv_mode_q < i_csr_unit_csr_addr[9:8]);
    assign write_to_ro = (i_csr_unit_csr_addr[11:10] == 2'b11) && i_csr_unit_csr_wen;

    always_comb begin
        addr_invalid = 1'b0;
        case (i_csr_unit_csr_addr)
            12'h300, 12'h100, 12'h301, 12'h304, 12'h104, 12'h305, 12'h105,
            12'h302, 12'h303, 12'h340, 12'h140, 12'h341, 12'h141, 12'h342,
            12'h142, 12'h343, 12'h143, 12'h344, 12'h144, 12'hB00, 12'hB80,
            12'hB02, 12'hB82, 12'hC00, 12'hC80, 12'hC02, 12'hC82,
            12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'h180, 12'h14D, 12'h15D,
            12'h30D, 12'h31D: addr_invalid = 1'b0;
            default:          addr_invalid = 1'b1;
        endcase
    end

    logic csr_illegal;
    assign csr_illegal = csr_instr_active && (addr_invalid || priv_violation || write_to_ro);

    // ── Exception Decoding ────────────────────────────────────────────────────
    logic exc_active;
    logic [31:0] exc_cause;
    logic [31:0] exc_tval;
    logic exc_delegated;

    always_comb begin
        exc_active = 1'b1;
        exc_cause = 32'h0;
        exc_tval = 32'h0;
        
        if (i_csr_unit_illegal_instr_id || i_csr_unit_illegal_instr_exe || csr_illegal) begin
            exc_cause = 32'd2; // Illegal instruction
            exc_tval = i_csr_unit_instr;
        end else if (i_csr_unit_instr_addr_misaligned) begin
            exc_cause = 32'd0; // Instruction address misaligned
            exc_tval = i_csr_unit_fault_addr;
        end else if (i_csr_unit_ecall) begin
            exc_cause = (priv_mode_q == 2'b11) ? 32'd11 : 32'd9;
            exc_tval = 32'h0;
        end else if (i_csr_unit_ebreak) begin
            exc_cause = 32'd3; // Breakpoint
            exc_tval = i_csr_unit_pc;
        end else if (i_csr_unit_sw_access_fault) begin
            exc_cause = 32'd7; // Store access fault
            exc_tval = i_csr_unit_fault_addr;
        end else if (i_csr_unit_lw_access_fault) begin
            exc_cause = 32'd5; // Load access fault
            exc_tval = i_csr_unit_fault_addr;
        end else begin
            exc_active = 1'b0;
        end
    end

    assign exc_delegated = exc_active && medeleg_q[exc_cause[4:0]] && (priv_mode_q < 2'b11);

    // ── Trap Decision ─────────────────────────────────────────────────────────
    logic take_trap;
    assign take_trap = take_interrupt || exc_active;

    logic trap_to_s;
    assign trap_to_s = take_interrupt ? int_to_s : exc_delegated;

    logic [31:0] final_cause;
    assign final_cause = take_interrupt ? int_cause : exc_cause;

    logic [31:0] trap_target_pc;
    always_comb begin
        if (trap_to_s) begin
            if (stvec_q[1:0] == 2'b01 && final_cause[31])
                trap_target_pc = {stvec_q[31:2], 2'b00} + {final_cause[29:0], 2'b00};
            else
                trap_target_pc = {stvec_q[31:2], 2'b00};
        end else begin
            if (mtvec_q[1:0] == 2'b01 && final_cause[31])
                trap_target_pc = {mtvec_q[31:2], 2'b00} + {final_cause[29:0], 2'b00};
            else
                trap_target_pc = {mtvec_q[31:2], 2'b00};
        end
    end

    // ── CSR Read Data ─────────────────────────────────────────────────────────
    logic [31:0] mip_val;
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
                12'hF11: o_csr_unit_rdata = 32'h0;
                12'hF12: o_csr_unit_rdata = 32'h0;
                12'hF13: o_csr_unit_rdata = 32'h0;
                12'hF14: o_csr_unit_rdata = 32'h0;
                12'h180: o_csr_unit_rdata = 32'h0; // satp (no virtualization or translation)
                12'h14D: o_csr_unit_rdata = stimecmp[31:0];
                12'h15D: o_csr_unit_rdata = stimecmp[63:32];
                12'h30D: o_csr_unit_rdata = mtimecmp[31:0];
                12'h31D: o_csr_unit_rdata = mtimecmp[63:32];
                default: o_csr_unit_rdata = 32'h0;
            endcase
        end
    end

    // ── CSR Write Value ───────────────────────────────────────────────────────
    logic [31:0] csr_wdata;
    always_comb begin
        case (i_csr_unit_op)
            2'b01:   csr_wdata = i_csr_unit_src;
            2'b10:   csr_wdata = o_csr_unit_rdata | i_csr_unit_src;
            2'b11:   csr_wdata = o_csr_unit_rdata & (~i_csr_unit_src);
            default: csr_wdata = 32'h0;
        endcase
    end

    logic csr_write_active;
    assign csr_write_active = i_csr_unit_csr_wen && !csr_illegal;

    // ── Sequential State Update ───────────────────────────────────────────────
    always_ff @(posedge i_csr_unit_clk or negedge i_csr_unit_rst_n) begin
        if (!i_csr_unit_rst_n) begin
            priv_mode_q <= 2'b11;
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
            mcycle_q <= mcycle_q + 1;
            mtime    <= mtime + 1;

            if (i_csr_unit_instr != 32'h0 && !take_trap && !i_csr_unit_mret_wb && !i_csr_unit_sret) begin
                minstret_q <= minstret_q + 1;
            end

            if (take_trap) begin
                if (trap_to_s) begin
                    sepc_q       <= i_csr_unit_pc;
                    scause_q     <= final_cause;
                    stval_q      <= (m_int_active || s_int_active) ? 32'h0 : exc_tval;
                    mstatus_q[8] <= priv_mode_q[0]; // SPP
                    mstatus_q[5] <= mstatus_q[1];   // SPIE <= SIE
                    mstatus_q[1] <= 1'b0;           // SIE <= 0
                    priv_mode_q  <= 2'b01;          // S-mode
                end else begin
                    mepc_q           <= i_csr_unit_pc;
                    mcause_q         <= final_cause;
                    mtval_q          <= (m_int_active || s_int_active) ? 32'h0 : exc_tval;
                    mstatus_q[12:11] <= priv_mode_q;     // MPP
                    mstatus_q[7]     <= mstatus_q[3];    // MPIE <= MIE
                    mstatus_q[3]     <= 1'b0;            // MIE <= 0
                    priv_mode_q      <= 2'b11;          // M-mode
                end
            end else if (i_csr_unit_mret_wb) begin
                priv_mode_q      <= mstatus_q[12:11]; // MPP
                mstatus_q[3]     <= mstatus_q[7];    // MIE <= MPIE
                mstatus_q[7]     <= 1'b1;            // MPIE <= 1
                mstatus_q[12:11] <= 2'b00;           // MPP <= 00
            end else if (i_csr_unit_sret) begin
                priv_mode_q  <= {1'b0, mstatus_q[8]}; // SPP
                mstatus_q[1] <= mstatus_q[5];        // SIE <= SPIE
                mstatus_q[5] <= 1'b1;                // SPIE <= 1
                mstatus_q[8] <= 1'b0;                // SPP <= 0
            end else if (csr_write_active) begin
                case (i_csr_unit_csr_addr)
                    12'h300: begin // mstatus
                        mstatus_q[12:11] <= csr_wdata[12:11];
                        mstatus_q[8]     <= csr_wdata[8];
                        mstatus_q[7]     <= csr_wdata[7];
                        mstatus_q[5]     <= csr_wdata[5];
                        mstatus_q[3]     <= csr_wdata[3];
                        mstatus_q[1]     <= csr_wdata[1];
                    end
                    12'h100: begin // sstatus
                        mstatus_q[8] <= csr_wdata[8];
                        mstatus_q[5] <= csr_wdata[5];
                        mstatus_q[1] <= csr_wdata[1];
                    end
                    12'h304: mie_q <= csr_wdata & 32'h00000AAA; // M+S: {MEIE,SEIE,MTIE,STIE,MSIE,SSIE}
                    12'h104: mie_q <= (mie_q & ~mideleg_q) | (csr_wdata & mideleg_q & 32'h00000AAA);
                    12'h305: mtvec_q <= csr_wdata;
                    12'h105: stvec_q <= csr_wdata;
                    12'h302: medeleg_q <= csr_wdata;
                    12'h303: mideleg_q <= csr_wdata & 32'h00000222;
                    12'h340: mscratch_q <= csr_wdata;
                    12'h140: sscratch_q <= csr_wdata;
                    12'h341: mepc_q <= {csr_wdata[31:2], 2'b00};
                    12'h141: sepc_q <= {csr_wdata[31:2], 2'b00};
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

    // ── Outputs ───────────────────────────────────────────────────────────────
    assign o_csr_unit_ack         = take_interrupt;
    assign o_csr_unit_irq_handler = trap_target_pc;
    assign o_csr_unit_rtrn_addr   = i_csr_unit_mret_wb ? mepc_q : sepc_q;
    assign o_csr_unit_addr_ctrl   = take_trap;
    assign o_csr_unit_mux1        = take_trap || i_csr_unit_mret_wb || i_csr_unit_sret;
    assign o_csr_unit_if_flush    = o_csr_unit_mux1;
    assign o_csr_unit_id_flush    = o_csr_unit_mux1;
    assign o_csr_unit_exe_flush   = o_csr_unit_mux1;
    assign o_csr_unit_mem_flush   = o_csr_unit_mux1;

endmodule
