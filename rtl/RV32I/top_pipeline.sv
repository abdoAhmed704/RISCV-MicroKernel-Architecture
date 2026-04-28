module top_pipeline(input clk, input rst_n, output reg [31:0] result);


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
logic ImmPassE;
logic I_TypeE;
logic inst_typeE;

// memory:
logic RegWriteM;
logic [1:0] ResultSrcM;
logic MemWriteM;
logic [31:0] ALUResultM;
logic [31:0] WriteDataM;
logic [4:0] RdM;
logic [31:0] PCPlus4M;
logic [2:0] funct3M;



// writeback
logic RegWriteW;
logic [4:0] RdW;
logic [1:0] ResultSrcW;
logic [31:0] ALUResultW;
logic [31:0] ReadDataW;
logic [31:0] PCPlus4W;

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

Hazard_Unit hu(.Rs1E(Rs1E), .Rs2E(Rs2E), .RdM(RdM), .RdW(RdW), .RegWriteM(RegWriteM), .RegWriteW(RegWriteW), .ResultSrcE_0(ResultSrcE[0]), 
                .RdE(RdE), .Rs1D(Rs1D), .Rs2D(Rs1D), .PCSrcE(PCSrcE), .FlushE(FlushE), .StallD(StallD), .StallF(StallF), .ForwardAE(ForwardAE), .ForwardBE(ForwardBE), .FlushD(FlushD));



fetch_stage new_fet(.clk(clk), .rst_n(rst_n), .PCTargetE(PCTargetE), .PCSrcE(PCSrcE), .instrD(instrD),
                    .PCPlus4D(PCPlus4D), .PCD(PCD), .enable(!StallD), .CLR(FlushD), .enable_pc(!StallF));



decode decode_keda_keda(.clk(clk), .rst_n(rst_n),.instrD(instrD), .PCPlus4D(PCPlus4D), .PCD(PCD), .RegWriteW(RegWriteW), .ResultW(result),
         .RdW(RdW), .PCE(PCE), .PCPlus4E(PCPlus4E), .RegWriteE(RegWriteE), .ResultSrcE(ResultSrcE), .MemWriteE(MemWriteE),
         .jumpE(jumpE), .Branch_takenE(Branch_takenE), .BranchE(BranchE), .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE), .RD1E(RD1E), 
         .RD2E(RD2E), .ImmExtE(ImmExtE), .RdE(RdE),
         .CLR(FlushE),
         .Rs1E(Rs1E),
         .Rs2E(Rs2E),
         .Rs1D(Rs1D),
         .Rs2D(Rs2D),
         .funct3E(funct3E),
         .ImmPassE(ImmPassE),
         .inst_typeE(inst_typeE)
         );


mux3_1 mux_alu_1(.A(RD1E), .B(result), .C(ALUResultM), .Sel(ForwardAE), .out(mux_R1_out));
mux3_1 mux_alu_2(.A(RD2E), .B(result), .C(ALUResultM), .Sel(ForwardBE), .out(mux_R2_out));

excute excute_kda_kda(  .clk(clk), .PCE(PCE), .PCPlus4E(PCPlus4E), .RegWriteE(RegWriteE), .ResultSrcE(ResultSrcE), 
                        .MemWriteE(MemWriteE), .jumpE(jumpE), .ALUControlE(ALUControlE), .ALUSrcE(ALUSrcE), 
                        .inst_typeE(inst_typeE), .funct3E(funct3E), .ImmPassE(ImmPassE),
                        .RD1E(mux_R1_out), .RD2E(mux_R2_out), .ImmExtE(ImmExtE), .RdE(RdE), .RegWriteM(RegWriteM), 
                        .ResultSrcM(ResultSrcM), .MemWriteM(MemWriteM), .ALUResultM(ALUResultM), .WriteDataM(WriteDataM), .RdM(RdM), .PCTargetE(PCTargetE), .PCPlus4M(PCPlus4M),
                        .ZeroE(ZeroE), .funct3M(funct3M));



memory data_mem(.clk(clk), .RegWriteM(RegWriteM), .ResultSrcM(ResultSrcM), .MemWriteM(MemWriteM), .ALUResultM(ALUResultM), 
            .WriteDataM(WriteDataM), .RdM(RdM), .PCPlus4M(PCPlus4M), .funct3M(funct3M), .RegWriteW(RegWriteW), .ResultSrcW(ResultSrcW), .RdW(RdW),
            .ALUResultW(ALUResultW), .ReadDataW(ReadDataW), .PCPlus4W(PCPlus4W));


mux3_1 mux_w(.A(ALUResultW), .B(ReadDataW), .C(PCPlus4W), .Sel(ResultSrcW), .out(result));


pcSrc_controller pcontrol (.ZeroE(ZeroE), .Branch_takenE(Branch_takenE), .BranchE(BranchE), .target_taken(target_taken));

assign PCSrcE = target_taken || jumpE;

endmodule
