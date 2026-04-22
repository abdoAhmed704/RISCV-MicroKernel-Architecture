module mux3_1(
    input [31:0] A, B, C,
    input [1:0] Sel,
    output logic [31:0] out 
);

always @(*) begin
        
        case (Sel)
            2'b00: out = A; // ALU out
            2'b01: out = B; // Data read from memory
            2'b10: out = C; // PC + 4 (for jump and link instructions)
            default: out = 0; // Default case
        endcase
    end

endmodule