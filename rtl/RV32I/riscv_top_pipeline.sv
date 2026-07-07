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

// ── Dynamic Branch Predictor signals ─────────────────────────────────────────
logic        predict_takenF;       // BPU prediction at fetch time
logic [31:0] next_pc_predictionF;  // BPU predicted target PC
logic [31:0] PCFx_out;             // next PC before pipeline reg (from fetch)
logic        predict_takenD;       // prediction propagated to decode stage
logic        predict_takenE;       // prediction propagated to execute stage
logic        mispredictionE;       // 1 when BPU was wrong at execute
logic        bp_flush_pipeline;    // flush signal from branch predictor
logic [31:0] bp_corrected_pc;      // corrected PC from branch predictor

// ── AI Unit (Linear Classifier) signals ──────────────────────────────────────
// Custom opcode 0x0B interface decoded from execute stage instruction
logic        ai_wr_weight;
logic [1:0]  ai_wr_w_row;
logic [1:0]  ai_wr_w_col;
logic [7:0]  ai_wr_w_data;
logic        ai_wr_input;
logic [1:0]  ai_wr_i_addr;
logic [7:0]  ai_wr_i_data;
logic        ai_start;
logic [31:0] ai_scores [0:3];
logic [1:0]  ai_predicted_class;
logic        ai_done;
logic        ai_read_validE;
logic [31:0] ai_read_dataE;

riscv_hazard_unit hu(
    .Rs1E(Rs1E), .Rs2E(Rs2E), .RdM(RdM), .RdW(RdW), .RegWriteM(RegWriteM), .RegWriteW(RegWriteW), .ResultSrcE_0(ResultSrcE[0]), 
    .RdE(RdE), .Rs1D(Rs1D), .Rs2D(Rs2D), .PCSrcE(PCSrcE), .FlushE(FlushE), .StallD(StallD), .StallF(StallF), .ForwardAE(ForwardAE), .ForwardBE(ForwardBE), .FlushD(FlushD)
);

// PC target selection for fetch stage considering traps/returns
logic [31:0] PCTargetE_to_fetch;
logic PCSrcE_to_fetch;
assign PCTargetE_to_fetch = o_csr_unit_mux1 ? (o_csr_unit_addr_ctrl ? o_csr_unit_irq_handler : o_csr_unit_rtrn_addr) :
                             (bp_flush_pipeline ? bp_corrected_pc : PCTargetE);
assign PCSrcE_to_fetch = PCSrcE || bp_flush_pipeline || o_csr_unit_mux1;

riscv_fetch_stage new_fet(
    .clk(clk), .rst_n(rst_n), .PCTargetE(PCTargetE_to_fetch), .PCSrcE(PCSrcE_to_fetch), .instrD(instrD),
    .PCPlus4D(PCPlus4D), .PCD(PCD), .enable(!StallD), .CLR(FlushD || bp_flush_pipeline || o_csr_unit_id_flush), .enable_pc(!StallF || o_csr_unit_mux1 || bp_flush_pipeline),
    .predict_takenF(predict_takenF),
    .next_pc_predictionF(next_pc_predictionF),
    .PCFx_out(PCFx_out),
    .PCF_out(),
    .predict_takenD(predict_takenD)
);

riscv_decode_stage decode_stage_inst(
    .clk(clk), .rst_n(rst_n), .instrD(instrD), .PCPlus4D(PCPlus4D), .PCD(PCD), .RegWriteW(RegWriteW), .ResultW(result),
    .RdW(RdW), .PCE(PCE), .PCPlus4E(PCPlus4E), .RegWriteE(RegWriteE), .ResultSrcE(ResultSrcE), .MemWriteE(MemWriteE),
    .jumpE(jumpE), .Branch_takenE(Branch_takenE), .BranchE(BranchE), .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE), .RD1E(RD1E), 
    .RD2E(RD2E), .ImmExtE(ImmExtE), .RdE(RdE),
    .CLR(FlushE || bp_flush_pipeline || o_csr_unit_exe_flush),
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

// Propagate branch prediction from D to E stage
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || FlushE || o_csr_unit_exe_flush)
        predict_takenE <= 1'b0;
    else
        predict_takenE <= predict_takenD;
end

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
    .custom_result_validE(ai_read_validE),
    .custom_resultE(ai_read_dataE),
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

// ── Branch predictor: misprediction detection ─────────────────────────────────
// A branch misprediction occurs when:
//  - The instruction in Execute is a branch (BranchE) AND
//  - The actual outcome (target_taken) differs from the prediction (predict_takenE)
assign mispredictionE = BranchE && (target_taken != predict_takenE);

// ── Dynamic Branch Predictor ─────────────────────────────────────────────────
dynamic_branch_predictor_top u_branch_pred (
    .clk                (clk),
    .rst_n              (rst_n),
    // Fetch interface
    .fetch_pc           (new_fet.PCF),           // Current PC in fetch
    .predict_taken      (predict_takenF),
    .next_pc_prediction (next_pc_predictionF),
    // Execute feedback interface
    .exe_pc             (PCE),                   // PC of instruction in execute
    .predict_taken_old  (predict_takenE),         // What was predicted for this instr
    .exe_is_branch      (BranchE),               // Is this a branch instruction?
    .actual_taken       (target_taken),           // Actual branch outcome
    .actual_target_pc   (PCTargetE),             // Actual branch target
    // Outputs (flush/corrected_pc are handled by existing hazard logic via PCSrcE)
    .flush_pipeline     (bp_flush_pipeline),
    .corrected_pc       (bp_corrected_pc)
);

// ── AI (Linear Classifier) Unit ──────────────────────────────────────────────
// Custom opcode 0x0B (opcode=0001011) instruction decode:
//  funct3=000: lc.load_weight  rs2=data, rs1=index (row=bits[1:0], col=bits[3:2])
//  funct3=001: lc.load_input   rs2=data, rs1=index (addr=bits[1:0])
//  funct3=010: lc.start        (trigger computation)
//  funct3=011: lc.read         rd=result, rs1=selector
//                selector 0 → done flag
//                selector 1 → predicted_class
//                selector 2 → scores[0] ... selector 5 → scores[3]

logic is_custom_E;
assign is_custom_E = (instrE[6:0] == 7'b0001011);

// AI write weight: funct3=000
assign ai_wr_weight = is_custom_E && (instrE[14:12] == 3'b000) && (instrE[11:7] == 5'd0);
assign ai_wr_w_row  = mux_R2_out[3:2];   // rs2 upper 2 bits = row
assign ai_wr_w_col  = mux_R2_out[1:0];   // rs2 lower 2 bits = col
assign ai_wr_w_data = mux_R1_out[7:0];   // rs1[7:0] = data value

// AI write input: funct3=001
assign ai_wr_input  = is_custom_E && (instrE[14:12] == 3'b001) && (instrE[11:7] == 5'd0);
assign ai_wr_i_addr = mux_R2_out[1:0];   // rs2 lower 2 bits = address
assign ai_wr_i_data = mux_R1_out[7:0];   // rs1[7:0] = data value

// AI start pulse: funct3=010
assign ai_start = is_custom_E && (instrE[14:12] == 3'b010);

assign ai_read_validE = is_custom_E && (instrE[14:12] == 3'b011);

always_comb begin
    unique case (mux_R1_out[2:0])
        3'd0: ai_read_dataE = {31'b0, ai_done};
        3'd1: ai_read_dataE = {30'b0, ai_predicted_class};
        3'd2: ai_read_dataE = ai_scores[0];
        3'd3: ai_read_dataE = ai_scores[1];
        3'd4: ai_read_dataE = ai_scores[2];
        3'd5: ai_read_dataE = ai_scores[3];
        default: ai_read_dataE = 32'b0;
    endcase
end

// AI read result: funct3=011 — drives ALU result back to register file
// The result is muxed into the writeback path; rd must be non-zero
// The ALU result for custom instructions is handled in the execute stage
// by default (ALUOp=00 → ADD → RD1E+RD2E=0+0=0 normally, but we override here)

linear_classifier #(.DW(8), .AW(32), .N(4)) u_linear_classifier (
    .clk             (clk),
    .rst_n           (rst_n),
    // Weight write
    .wr_weight       (ai_wr_weight),
    .wr_w_row        (ai_wr_w_row),
    .wr_w_col        (ai_wr_w_col),
    .wr_w_data       (ai_wr_w_data),
    // Input write
    .wr_input        (ai_wr_input),
    .wr_i_addr       (ai_wr_i_addr),
    .wr_i_data       (ai_wr_i_data),
    // Control
    .start           (ai_start),
    // Outputs
    .scores          (ai_scores),
    .predicted_class (ai_predicted_class),
    .done            (ai_done)
);

// ── Interrupt acknowledge output ──────────────────────────────────────────
// Exposed at top level so an external interrupt controller (PLIC) can
// de-assert mexternal / sexternal once the core has latched the interrupt.
assign irq_ack = o_csr_unit_ack;

endmodule
