module fetch_stage(
    input clk,
    input rst_n,
    input [31:0] PCTargetE,
    input PCSrcE,
    input enable_pc, enable, CLR,  // Added 
    output reg [31:0] instrD,
    output reg [31:0] PCPlus4D,
    output reg [31:0] PCD
);


wire [31:0] PCFx;
wire [31:0] PCPlus4F;
reg [31:0] PCF;
wire [31:0] instrF;


assign PCPlus4F = PCF + 4;
assign PCFx = (PCSrcE) ? PCTargetE : PCPlus4F; 


always@(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        PCF <= 0;
    end else begin
        if(enable_pc)
            PCF <= PCFx;
    end
end

instruction_mem imem (
    .PC(PCF),
    .inst(instrF)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n || CLR) begin
        instrD   <= 0;
        PCPlus4D <= 0;
        PCD      <= 0;
    end 
    else if (enable) begin
        instrD   <= instrF;
        PCPlus4D <= PCPlus4F;
        PCD      <= PCF;
    end
end

endmodule
