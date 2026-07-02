module riscv_memory_stage(
    input clk,
    input rst_n,
    input RegWriteM,
    input [1:0] ResultSrcM,
    input MemWriteM,
    input [31:0] ALUResultM,
    input [31:0] WriteDataM,
    input [4:0] RdM,
    input [31:0] PCPlus4M,
    input [2:0] funct3M,
    input logic flushW,
    input logic [31:0] PCM,
    input logic [31:0] instrM,
    input logic [1:0]  csr_opM,
    input logic [11:0] csr_addrM,
    input logic        csr_wenM,
    input logic        is_system_instrM,
    output logic [31:0] PCW,
    output logic [31:0] instrW,
    output logic        csr_wenW,
    output logic [11:0] csr_addrW,
    output logic [1:0]  csr_opW,
    output logic        is_system_instrW,
    output logic        lw_access_fault_M,
    output logic        sw_access_fault_M,
    output reg RegWriteW,
    output reg [1:0] ResultSrcW,
    output reg [4:0] RdW,
    output reg [31:0] ALUResultW,
    output reg [31:0] ReadDataW,
    output reg [31:0] PCPlus4W
    // output reg [31:0] ResultW
);

    wire [31:0] ReadDataM;

    // Access fault and alignment check logic
    logic lw_misaligned, sw_misaligned;
    assign lw_misaligned = (funct3M == 3'b010 && ALUResultM[1:0] != 2'b00) || 
                           ((funct3M == 3'b001 || funct3M == 3'b101) && ALUResultM[0] != 1'b0);
    assign sw_misaligned = (funct3M == 3'b010 && ALUResultM[1:0] != 2'b00) || 
                           (funct3M == 3'b001 && ALUResultM[0] != 1'b0);

    assign lw_access_fault_M = (ResultSrcM == 2'b01) && ((ALUResultM >= 16384) || lw_misaligned);
    assign sw_access_fault_M = MemWriteM && ((ALUResultM >= 16384) || sw_misaligned);

    // Gate writing to data memory on any trap/flush or store fault
    logic dmem_write_en;
    assign dmem_write_en = MemWriteM && !flushW && !sw_access_fault_M;

    // instantiate Data Memory
    riscv_data_mem dmem (
        .clk(clk), // Clock signal
        .WriteEnable(dmem_write_en), // Write enable signal gated by flush and faults
        .Address(ALUResultM), // Address for memory access (ALU result)
        .WriteData(WriteDataM), // Data to write to memory (from execute stage)
        .ReadData(ReadDataM), // Data read from memory (to be used in write-back stage)
        .funct3(funct3M)
    );

    // Pipeline register for the memory stage to write-back stage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flushW) begin
            RegWriteW        <= 0;
            ResultSrcW       <= 0;
            RdW              <= 0;
            PCPlus4W         <= 0;
            ALUResultW       <= 0;
            ReadDataW        <= 0;
            PCW              <= 0;
            instrW           <= 0;
            csr_wenW         <= 0;
            csr_addrW        <= 0;
            csr_opW          <= 0;
            is_system_instrW <= 0;
        end else begin
            RegWriteW        <= RegWriteM; // Pass register write enable signal to write-back stage
            ResultSrcW       <= ResultSrcM; // Pass ALU result source control signal to write-back stage
            RdW              <= RdM; // Pass destination
            PCPlus4W         <= PCPlus4M; // Pass PC + 4 to write-back stage
            ALUResultW       <= ALUResultM; // Pass ALU result to write-back stage
            ReadDataW        <= ReadDataM; // Pass data read from memory to write-back stage
            PCW              <= PCM;
            instrW           <= instrM;
            csr_wenW         <= csr_wenM;
            csr_addrW        <= csr_addrM;
            csr_opW          <= csr_opM;
            is_system_instrW <= is_system_instrM;
        end
    end

endmodule
