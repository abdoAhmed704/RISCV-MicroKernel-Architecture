module riscv_fetch_stage(
    input clk,
    input rst_n,
    input [31:0] PCTargetE,
    input PCSrcE,
    input enable_pc, enable, CLR,  // Added 
    input predict_takenF,           // Added for branch prediction
    input [31:0] next_pc_predictionF, // Added for branch prediction
    output [31:0] PCFx_out,         // Added for branch prediction
    output reg [31:0] instrD,
    output reg [31:0] PCPlus4D,
    output reg [31:0] PCD,
    output [31:0] PCF_out,          // Exposes current PCF
    output reg predict_takenD       // Added for branch prediction
);

wire [31:0] PCFx;
wire [31:0] PCPlus4F;
reg [31:0] PCF;
wire [31:0] instrF;

wire is_compressedF = (instrF[1:0] != 2'b11);
assign PCPlus4F = PCF + (is_compressedF ? 32'd2 : 32'd4);
assign PCFx = (PCSrcE) ? PCTargetE : ((predict_takenF) ? next_pc_predictionF : PCPlus4F); 
assign PCFx_out = PCFx;
assign PCF_out = PCF;

always@(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        PCF <= 0;
    end else begin
        if(enable_pc)
            PCF <= PCFx;
    end
end

riscv_instruction_mem imem (
    .PC(PCF),
    .inst(instrF)
);

    wire [31:0] decoded_instrF;
    wire is_compressed_flagF;
    wire illegal_compressedF;

    riscv_core_compressed_decoder u_compressed_dec (
        .i_compressed_decoder_instr(instrF),
        .o_compressed_decoder_instr(decoded_instrF),
        .o_compressed_decoder_is_compressed(is_compressed_flagF),
        .o_compressed_decoder_illegal_instr(illegal_compressedF)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || CLR) begin
            instrD   <= 0;
            PCPlus4D <= 0;
            PCD      <= 0;
            predict_takenD <= 0;
        end 
        else if (enable) begin
            instrD   <= decoded_instrF;
            PCPlus4D <= PCPlus4F;
            PCD      <= PCF;
            predict_takenD <= predict_takenF;
        end
    end

endmodule
