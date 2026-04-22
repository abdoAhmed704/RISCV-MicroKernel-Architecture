module memory(
    input clk,
    input RegWriteM,
    input [1:0] ResultSrcM,
    input MemWriteM,
    input [31:0] ALUResultM,
    input [31:0] WriteDataM,
    input [4:0] RdM,
    input [31:0] PCPlus4M,
    input [2:0] funct3M,
    output reg RegWriteW,
    output reg [1:0] ResultSrcW,
    output reg [4:0] RdW,
    output reg [31:0] ALUResultW,
    output reg [31:0] ReadDataW,
    output reg [31:0] PCPlus4W
    // output reg [31:0] ResultW
);

    wire [31:0] ReadDataM;

    // instantiate Data Memory
    data_mem dmem (
        .clk(clk), // Clock signal
        .WriteEnable(MemWriteM), // Write enable signal from memory stage
        .Address(ALUResultM), // Address for memory access (ALU result)
        .WriteData(WriteDataM), // Data to write to memory (from execute stage)
        .ReadData(ReadDataM), // Data read from memory (to be used in write-back stage)
        .funct3(funct3M)
    );

    // Pipeline register for the memory stage to write-back stage
    always @(posedge clk) begin
        RegWriteW <= RegWriteM; // Pass register write enable signal to write-back stage
        ResultSrcW <= ResultSrcM; // Pass ALU result source control signal to write-back stage
        RdW <= RdM; // Pass destination
        PCPlus4W <= PCPlus4M; // Pass PC + 4 to write-back stage
        ALUResultW <= ALUResultM; // Pass ALU result to write-back stage
        ReadDataW <= ReadDataM; // Pass data read from memory to write-back stage

    end


endmodule