module alu(
input [31:0] src_a, src_b,
input [2:0] alu_control,
input funct7_5,
output Zero,
output reg [31:0] result
);

always @(*) begin
    case (alu_control)
        3'b000: begin
            if(!funct7_5) begin
                result = src_a + src_b;                  // ADD
            end
            else begin
                result = src_a - src_b;                 // SUB
            end
        end
        
        3'b001: begin
            if(!funct7_5) 
                result = src_a >> src_b[4:0];               // SRL (Logical)
            else 
                result = $signed(src_a) >>> src_b[4:0];     // SRA (Arithmetic)
        end
        3'b010: result = src_a & src_b;                // AND
        3'b011: result = src_a | src_b;              // OR
        3'b100: result = src_a ^ src_b;             // XOR
        3'b101: result = ($signed(src_a) < $signed(src_b))? 1:0;     // SLT
        3'b110: result = src_a << src_b;    
        3'b111: result = (src_a < src_b)? 1:0;      // SLTU
        default: result = 32'b0;

    endcase

end

assign Zero = (result == 0);

endmodule