module riscv_top_pipeline(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mexternal = 1'b0,
    input  logic        sexternal = 1'b0,
    output logic [31:0] result,
    // Interrupt acknowledge: pulses HIGH when an interrupt is being taken.
    // Connect to an external interrupt controller (e.g. PLIC) so it can
    // de-assert the interrupt line after the core has accepted it.
    output logic        irq_ack
);

logic [31:0] PCTargetE;
logic  PCSrcE;

logic [31:0] PCPlus4D;
logic [31:0] PCD;

logic [31:0] instrD;

// Execute
logic [31:0] PCE; 
logic [31:0] PCPlus4E; 
logic RegWriteE; 
logic [1:0] ResultSrcE; 
logic MemWriteE; 
logic jumpE; 
logic [2:0] Branch_takenE;
logic BranchE; 
logic [2:0] ALUControlE; 
logic ALUSrcE;
logic [31:0] RD1E;
logic [31:0] RD2E;
logic [31:0] ImmExtE;
logic [4:0] RdE;
logic [2:0] funct3E;
logic [1:0] ImmPassE;
logic I_TypeE;
logic inst_typeE;
logic jalr_pcE;

// SYSTEM and CSR wires
logic [31:0] instrE;
logic [1:0]  csr_opE;
logic [11:0] csr_addrE;
logic        csr_wenE;
logic [4:0]  csr_uimmE;
logic        csr_imm_selE;
logic        illegal_instr_id_E;
logic        ecallE;
logic        ebreakE;
logic        mretE;
logic        sretE;
logic        is_system_instrE;

// memory:
logic RegWriteM;
logic [1:0] ResultSrcM;
logic MemWriteM;
logic [31:0] ALUResultM;
logic [31:0] WriteDataM;
logic [4:0] RdM;
logic [31:0] PCPlus4M;
logic [2:0] funct3M;

// M Stage SYSTEM and CSR
logic [31:0] PCM;
logic [31:0] instrM;
logic [1:0]  csr_opM;
logic [11:0] csr_addrM;
logic        csr_wenM;
logic [31:0] csr_srcM;
logic        illegal_instr_id_M;
logic        illegal_instr_exe_M;
logic        instr_addr_misaligned_M;
logic        ecallM;
logic        ebreakM;
logic        mretM;
logic        sretM;
logic        is_system_instrM;

// writeback
logic RegWriteW;
logic [4:0] RdW;
logic [1:0] ResultSrcW;
logic [31:0] ALUResultW;
logic [31:0] ReadDataW;
logic [31:0] PCPlus4W;

// W Stage SYSTEM and CSR
logic [31:0] PCW;
logic [31:0] instrW;
logic        csr_wenW;
logic [11:0] csr_addrW;
logic [1:0]  csr_opW;
logic        is_system_instrW;
logic [31:0] CSRRDataW;

// Faults from Memory Stage
logic lw_access_fault_M;
logic sw_access_fault_M;

// CSR Unit outputs
logic o_csr_unit_ack;          // → driven out as top-level 'irq_ack' port
logic [31:0] o_csr_unit_rdata;
logic [31:0] o_csr_unit_irq_handler;
logic [31:0] o_csr_unit_rtrn_addr;
logic o_csr_unit_addr_ctrl;
logic o_csr_unit_mux1;
// o_csr_unit_if_flush is intentionally not used to drive any internal
// signal: the fetch-stage pipeline register is already cleared by
// o_csr_unit_id_flush (wired into fetch .CLR below), which fires at the
// same time. Driving it here keeps the port legally connected.
logic o_csr_unit_if_flush;    // redundant — see comment above
logic o_csr_unit_id_flush;
logic o_csr_unit_exe_flush;
logic o_csr_unit_mem_flush;

// Hazard
logic [4:0] Rs1E;
logic [4:0] Rs2E;
logic [1:0] ForwardAE, ForwardBE;
logic [31:0] mux_R1_out;
logic [31:0] mux_R2_out;
logic FlushE;
logic StallD;
logic FlushD;
logic StallF;

logic [4:0] Rs1D, Rs2D;

logic funct7_5E;

logic target_taken;

logic ZeroE;

riscv_hazard_unit hu(
    .Rs1E(Rs1E), .Rs2E(Rs2E), .RdM(RdM), .RdW(RdW), .RegWriteM(RegWriteM), .RegWriteW(RegWriteW), .ResultSrcE_0(ResultSrcE[0]), 
    .RdE(RdE), .Rs1D(Rs1D), .Rs2D(Rs2D), .PCSrcE(PCSrcE), .FlushE(FlushE), .StallD(StallD), .StallF(StallF), .ForwardAE(ForwardAE), .ForwardBE(ForwardBE), .FlushD(FlushD)
);

// PC target selection for fetch stage considering traps/returns
logic [31:0] PCTargetE_to_fetch;
logic PCSrcE_to_fetch;
assign PCTargetE_to_fetch = o_csr_unit_mux1 ? (o_csr_unit_addr_ctrl ? o_csr_unit_irq_handler : o_csr_unit_rtrn_addr) : PCTargetE;
assign PCSrcE_to_fetch = PCSrcE || o_csr_unit_mux1;

riscv_fetch_stage new_fet(
    .clk(clk), .rst_n(rst_n), .PCTargetE(PCTargetE_to_fetch), .PCSrcE(PCSrcE_to_fetch), .instrD(instrD),
    .PCPlus4D(PCPlus4D), .PCD(PCD), .enable(!StallD), .CLR(FlushD || o_csr_unit_id_flush), .enable_pc(!StallF || o_csr_unit_mux1)
);

riscv_decode_stage decode_stage_inst(
    .clk(clk), .rst_n(rst_n), .instrD(instrD), .PCPlus4D(PCPlus4D), .PCD(PCD), .RegWriteW(RegWriteW), .ResultW(result),
    .RdW(RdW), .PCE(PCE), .PCPlus4E(PCPlus4E), .RegWriteE(RegWriteE), .ResultSrcE(ResultSrcE), .MemWriteE(MemWriteE),
    .jumpE(jumpE), .Branch_takenE(Branch_takenE), .BranchE(BranchE), .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE), .RD1E(RD1E), 
    .RD2E(RD2E), .ImmExtE(ImmExtE), .RdE(RdE),
    .CLR(FlushE || o_csr_unit_exe_flush),
    .Rs1E(Rs1E),
    .Rs2E(Rs2E),
    .Rs1D(Rs1D),
    .Rs2D(Rs2D),
    .funct3E(funct3E),
    .ImmPassE(ImmPassE),
    .inst_typeE(inst_typeE),
    .jalr_pcE(jalr_pcE),
    // SYSTEM and CSR outputs
    .instrE(instrE),
    .o_csr_opE(csr_opE),
    .o_csr_addrE(csr_addrE),
    .o_csr_wenE(csr_wenE),
    .o_csr_uimmE(csr_uimmE),
    .o_csr_imm_selE(csr_imm_selE),
    .o_illegal_instr_id_E(illegal_instr_id_E),
    .o_ecallE(ecallE),
    .o_ebreakE(ebreakE),
    .o_mretE(mretE),
    .o_sretE(sretE),
    .o_is_system_instrE(is_system_instrE)
);

riscv_mux_3_1 mux_alu_1(.A(RD1E), .B(result), .C(ALUResultM), .Sel(ForwardAE), .out(mux_R1_out));
riscv_mux_3_1 mux_alu_2(.A(RD2E), .B(result), .C(ALUResultM), .Sel(ForwardBE), .out(mux_R2_out));

riscv_execute_stage execute_stage_inst(
    .clk(clk), .rst_n(rst_n), .CLR(o_csr_unit_exe_flush),
    .PCE(PCE), .PCPlus4E(PCPlus4E), .RegWriteE(RegWriteE), .ResultSrcE(ResultSrcE), 
    .MemWriteE(MemWriteE), .jumpE(jumpE), .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE), 
    .inst_typeE(inst_typeE), .funct3E(funct3E), .ImmPassE(ImmPassE),
    .jalr_pcE(jalr_pcE), .RD1E(mux_R1_out), .RD2E(mux_R2_out), .ImmExtE(ImmExtE), .RdE(RdE), .RegWriteM(RegWriteM), 
    .ResultSrcM(ResultSrcM), .MemWriteM(MemWriteM), .ALUResultM(ALUResultM), .WriteDataM(WriteDataM), .RdM(RdM), .PCTargetE_new(PCTargetE), .PCPlus4M(PCPlus4M),
    .ZeroE(ZeroE), .funct3M(funct3M),
    // SYSTEM and CSR inputs/outputs
    .instrE(instrE),
    .csr_opE(csr_opE),
    .csr_addrE(csr_addrE),
    .csr_wenE(csr_wenE),
    .csr_uimmE(csr_uimmE),
    .csr_imm_selE(csr_imm_selE),
    .illegal_instr_id_E(illegal_instr_id_E),
    .ecallE(ecallE),
    .ebreakE(ebreakE),
    .mretE(mretE),
    .sretE(sretE),
    .is_system_instrE(is_system_instrE),
    .PCSrcE(PCSrcE),
    .PCM(PCM),
    .instrM(instrM),
    .csr_opM(csr_opM),
    .csr_addrM(csr_addrM),
    .csr_wenM(csr_wenM),
    .csr_srcM(csr_srcM),
    .illegal_instr_id_M(illegal_instr_id_M),
    .illegal_instr_exe_M(illegal_instr_exe_M),
    .instr_addr_misaligned_M(instr_addr_misaligned_M),
    .ecallM(ecallM),
    .ebreakM(ebreakM),
    .mretM(mretM),
    .sretM(sretM),
    .is_system_instrM(is_system_instrM)
);

riscv_memory_stage memory_stage_inst(
    .clk(clk), .rst_n(rst_n), .RegWriteM(RegWriteM), .ResultSrcM(ResultSrcM), .MemWriteM(MemWriteM), .ALUResultM(ALUResultM), 
    .WriteDataM(WriteDataM), .RdM(RdM), .PCPlus4M(PCPlus4M), .funct3M(funct3M), .RegWriteW(RegWriteW), .ResultSrcW(ResultSrcW), .RdW(RdW),
    .ALUResultW(ALUResultW), .ReadDataW(ReadDataW), .PCPlus4W(PCPlus4W),
    // SYSTEM and CSR inputs/outputs
    .flushW(o_csr_unit_mem_flush),
    .PCM(PCM),
    .instrM(instrM),
    .csr_opM(csr_opM),
    .csr_addrM(csr_addrM),
    .csr_wenM(csr_wenM),
    .is_system_instrM(is_system_instrM),
    .PCW(PCW),
    .instrW(instrW),
    .csr_wenW(csr_wenW),
    .csr_addrW(csr_addrW),
    .csr_opW(csr_opW),
    .is_system_instrW(is_system_instrW),
    .lw_access_fault_M(lw_access_fault_M),
    .sw_access_fault_M(sw_access_fault_M)
);

// CSR Unit Instantiation
riscv_csr_unit csr_unit (
    .i_csr_unit_clk(clk),
    .i_csr_unit_rst_n(rst_n),
    .i_csr_unit_mexternal(mexternal),
    .i_csr_unit_sexternal(sexternal),
    .i_csr_unit_mem_wen(MemWriteM),
    .i_csr_unit_pc(PCM),
    .i_csr_unit_fault_addr(ALUResultM),
    .i_csr_unit_instr(instrM),
    .i_csr_unit_csr_wen(csr_wenM),
    .i_csr_unit_op(csr_opM),
    .i_csr_unit_src(csr_srcM),
    .i_csr_unit_csr_addr(csr_addrM),
    .i_csr_unit_illegal_instr_id(illegal_instr_id_M),
    .i_csr_unit_illegal_instr_exe(1'b0), // Tied to 0 (privilege check and address check are internal to CSR Unit)
    .i_csr_unit_instr_addr_misaligned(instr_addr_misaligned_M),
    .i_csr_unit_lw_access_fault(lw_access_fault_M),
    .i_csr_unit_sw_access_fault(sw_access_fault_M),
    .i_csr_unit_mret_wb(mretM),
    .i_csr_unit_ecall(ecallM),
    .i_csr_unit_ebreak(ebreakM),
    .i_csr_unit_sret(sretM),
    .o_csr_unit_ack(o_csr_unit_ack),
    .o_csr_unit_rdata(o_csr_unit_rdata),
    .o_csr_unit_irq_handler(o_csr_unit_irq_handler),
    .o_csr_unit_rtrn_addr(o_csr_unit_rtrn_addr),
    .o_csr_unit_addr_ctrl(o_csr_unit_addr_ctrl),
    .o_csr_unit_mux1(o_csr_unit_mux1),
    .o_csr_unit_if_flush(o_csr_unit_if_flush),
    .o_csr_unit_id_flush(o_csr_unit_id_flush),
    .o_csr_unit_exe_flush(o_csr_unit_exe_flush),
    .o_csr_unit_mem_flush(o_csr_unit_mem_flush)
);

// Latch combinationally read CSR data in M stage to W stage
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || o_csr_unit_mem_flush) begin
        CSRRDataW <= 32'h0;
    end else begin
        CSRRDataW <= o_csr_unit_rdata;
    end
end

// 4-to-1 writeback multiplexer including CSR read data
riscv_mux_4_1 mux_w(
    .A(ALUResultW),    // Sel = 2'b00
    .B(ReadDataW),     // Sel = 2'b01
    .C(PCPlus4W),      // Sel = 2'b10
    .D(CSRRDataW),     // Sel = 2'b11 (CSR read data)
    .Sel(ResultSrcW),
    .out(result)
);

riscv_pc_src_controller pcontrol (.ZeroE(ZeroE), .Branch_takenE(Branch_takenE), .BranchE(BranchE), .target_taken(target_taken));

assign PCSrcE = target_taken || jumpE;

// ── Interrupt acknowledge output ──────────────────────────────────────────
// Exposed at top level so an external interrupt controller (PLIC) can
// de-assert mexternal / sexternal once the core has latched the interrupt.
assign irq_ack = o_csr_unit_ack;

endmodule
