module alu(
input logic [31:0] src_a, src_b,
input logic [2:0] alu_control,
input logic inst_typeE,
output logic Zero,
output logic [31:0] result
);

always @(*) begin
    // $display("@@@@    src_a=%b, src_b%b", src_a, src_b);
    case (alu_control)
        3'b000: begin
            if(!inst_typeE)begin
                result = src_a + src_b;                     // ADD
                // $display("SAY THE WORDS");
            end
            else begin
                result = src_a - src_b;                     // SUB
                // $display("SAY YOU WANT THIS...");
            end
        end

        3'b001: begin
            if(!inst_typeE)
                result = src_a >> src_b[4:0];                                       // SRL (Logical)
            else 
                result = $signed(src_a) >>> src_b[4:0];                             // SRA (Arithmetic)
        end
        3'b010: result = src_a & src_b;                                             // AND
        3'b011: result = src_a | src_b;                                             // OR
        3'b100: result = src_a ^ src_b;                                             // XOR
        3'b101: result = ($signed(src_a) < $signed(src_b))? 1:0;                    // SLT
        3'b110: result = src_a << src_b[4:0];                                       // SLL
        3'b111: result = ($unsigned(src_a) < $unsigned(src_b)) ? 32'b1 : 32'b0;      // SLTU
        default: result = 32'b0;

    endcase

end

assign Zero = (result == 0);

endmodule