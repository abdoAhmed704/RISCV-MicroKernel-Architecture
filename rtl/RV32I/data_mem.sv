module data_mem #(
    parameter DATA_WIDTH = 32, // Width of data
    parameter ADDR_WIDTH = 32, 
    parameter MEM_SIZE = 32 
)(
    input clk,
    input WriteEnable,
    input [2:0] funct3,
    input [DATA_WIDTH-1:0] WriteData,
    input [ADDR_WIDTH-1:0] Address,
    output reg [DATA_WIDTH-1:0] ReadData
);

    reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];

    always_comb begin
        case (funct3)
            3'b000: ReadData = {{24{memory[Address[ADDR_WIDTH-1:0]][7]}}, memory[Address[ADDR_WIDTH-1:0]][7:0]};   // LOAD BYTE
            3'b001: ReadData = {{16{memory[Address[ADDR_WIDTH-1:0]][15]}}, memory[Address[ADDR_WIDTH-1:0]][15:0]};   // LOAD HALF
            3'b010: ReadData = memory[Address[ADDR_WIDTH-1:0]]; //LOAD WORD LW
            3'b100: ReadData = {{24{1'b0}}, memory[Address[ADDR_WIDTH-1:0]][7:0]};   // LOAD BYTE U
            3'b101: ReadData = {{16{1'b0}}, memory[Address[ADDR_WIDTH-1:0]][15:0]};   // LOAD HALF U
            default: ReadData = 32'b0;
        endcase
    end 

    always @(posedge clk) begin
        if (WriteEnable) begin
            case (funct3)
                3'b000: memory[Address[ADDR_WIDTH-1:0]] <= {{24{1'b0}}, WriteData[7:0]};   // STORE BYTE
                3'b001: memory[Address[ADDR_WIDTH-1:0]] <= {{16{1'b0}}, WriteData[15:0]};   // STORE HALF
                3'b010: memory[Address[ADDR_WIDTH-1:0]] <= WriteData[31:0]; // STORE WORD
                default: memory[Address] <= memory[Address];         // Do nothing
            endcase
        end
    end

endmodule