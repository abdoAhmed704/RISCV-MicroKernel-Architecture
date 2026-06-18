module data_mem #(
    parameter DATA_WIDTH = 32, // Width of data
    parameter ADDR_WIDTH = 32, 
    parameter MEM_SIZE = 4096
)(
    input logic clk,
    input logic WriteEnable,
    input logic [2:0] funct3,
    input logic [DATA_WIDTH-1:0] WriteData,
    input logic [ADDR_WIDTH-1:0] Address,
    output logic [DATA_WIDTH-1:0] ReadData
);

    reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];
    initial begin
        for (int i = 0; i < MEM_SIZE; i++) memory[i] = 32'h0;
    end
    
    logic [31:0] selected_word;
    assign selected_word = memory[Address[ADDR_WIDTH-1:2]];

    always_comb begin
        case (funct3)
            3'b000: begin // LOAD BYTE (signed)
                case (Address[1:0])
                    2'b00: ReadData = {{24{selected_word[7]}}, selected_word[7:0]};
                    2'b01: ReadData = {{24{selected_word[15]}}, selected_word[15:8]};
                    2'b10: ReadData = {{24{selected_word[23]}}, selected_word[23:16]};
                    2'b11: ReadData = {{24{selected_word[31]}}, selected_word[31:24]};
                endcase
            end
            3'b001: begin // LOAD HALF (signed)
                case (Address[1])
                    1'b0: ReadData = {{16{selected_word[15]}}, selected_word[15:0]};
                    1'b1: ReadData = {{16{selected_word[31]}}, selected_word[31:16]};
                endcase
            end
            3'b010: ReadData = selected_word; // LOAD WORD LW
            3'b100: begin // LOAD BYTE U (unsigned)
                case (Address[1:0])
                    2'b00: ReadData = {24'b0, selected_word[7:0]};
                    2'b01: ReadData = {24'b0, selected_word[15:8]};
                    2'b10: ReadData = {24'b0, selected_word[23:16]};
                    2'b11: ReadData = {24'b0, selected_word[31:24]};
                endcase
            end
            3'b101: begin // LOAD HALF U (unsigned)
                case (Address[1])
                    1'b0: ReadData = {16'b0, selected_word[15:0]};
                    1'b1: ReadData = {16'b0, selected_word[31:16]};
                endcase
            end
            default: ReadData = 32'b0;
        endcase
    end 

    always @(posedge clk) begin
        if (WriteEnable) begin
            $display("WriteEnable = %h, WriteData = %h, Address = %h", WriteEnable, WriteData, Address);
            case (funct3)
                3'b000: begin // STORE BYTE
                    case (Address[1:0])
                        2'b00: memory[Address[ADDR_WIDTH-1:2]][7:0]   <= WriteData[7:0];
                        2'b01: memory[Address[ADDR_WIDTH-1:2]][15:8]  <= WriteData[7:0];
                        2'b10: memory[Address[ADDR_WIDTH-1:2]][23:16] <= WriteData[7:0];
                        2'b11: memory[Address[ADDR_WIDTH-1:2]][31:24] <= WriteData[7:0];
                    endcase
                end
                3'b001: begin // STORE HALF
                    case (Address[1])
                        1'b0: memory[Address[ADDR_WIDTH-1:2]][15:0]  <= WriteData[15:0];
                        1'b1: memory[Address[ADDR_WIDTH-1:2]][31:16] <= WriteData[15:0];
                    endcase
                end
                3'b010: memory[Address[ADDR_WIDTH-1:2]] <= WriteData[31:0]; // STORE WORD
                default: ; // Do nothing
            endcase
        end
    end

endmodule