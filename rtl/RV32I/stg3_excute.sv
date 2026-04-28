module excute (
    input logic clk,
    input logic [31:0] PCE,
    input logic [31:0] PCPlus4E,
    input logic RegWriteE,
    input logic [1:0] ResultSrcE,
    input logic MemWriteE,
    input logic jumpE,
    input logic [2:0] ALUControlE,
    input logic ALUSrcE,
    input logic [31:0] RD1E,
    input logic [31:0] RD2E,
    input logic [31:0] ImmExtE,
    input logic [4:0] RdE,
    input logic [2:0] funct3E,
    input logic ImmPassE,
    input logic inst_typeE,

    output logic  RegWriteM,
    output logic  [1:0] ResultSrcM,
    output logic  MemWriteM,
    output logic  [31:0] ALUResultM,
    output logic  [31:0] WriteDataM,
    output logic  [4:0] RdM,
    output logic  [31:0] PCTargetE,
    output logic  [31:0] PCPlus4M,
    output logic ZeroE,
    output logic [2:0] funct3M
);



    wire [31:0] SrcBE;
    wire [31:0] WriteDataE;

    wire [31:0] ALUResultE;

    assign WriteDataE = RD2E; // Data to be written to memory (used in the memory stage)

    // SrcBE is the second operand for the ALU, which can be either RD2E or ImmExtE based on the ALUSrcE control signal
    assign SrcBE = (!ALUSrcE) ? RD2E: ImmExtE;
    // ALU instantiation
    alu aluE (
        .src_a(RD1E), // Source operand A
        .src_b(SrcBE), // Source operand B (either RD2E or ImmExtE based on ALUSrcE)
        .inst_typeE(inst_typeE),
        .alu_control(ALUControlE), // ALU control signal
        .Zero(ZeroE), // Zero flag output from ALU
        .result(ALUResultE) // ALU result (not used in this stage)
    );

    // instantiage PCTarget unit
    PCTarget pctargetE (
        .PC(PCE), // PC + 4 input
        .ImmExt(ImmExtE), // Extended immediate input
        .PC_Target(PCTargetE) // Calculated PC target output
    );

    // PCSrcE is determined by the branch condition (BranchE && ZeroE) or the jump signal (jumpE)
    

    // Pipeline register for the execute stage to memory stage
    always @(posedge clk) begin
        RegWriteM <= RegWriteE; // Pass register write enable signal to memory stage
        ResultSrcM <= ResultSrcE; // Pass ALU result source control signal to memory stage
        MemWriteM <= MemWriteE; // Pass memory write enable signal to memory stage
        WriteDataM <= WriteDataE; // Pass data to be written to memory to memory stage
        RdM <= RdE; // Pass destination register address to memory stage
        PCPlus4M <= PCPlus4E; // Pass PC + 4 to memory stage
        funct3M <= funct3E;
        if (ImmPassE) begin
            ALUResultM <= ImmExtE; // Pass the immediate value directly to memory stage for LUI and AUIPC instructions
        end else begin
            ALUResultM <= ALUResultE; // Pass ALU result to memory stage for other instructions
        end
    end


endmodule