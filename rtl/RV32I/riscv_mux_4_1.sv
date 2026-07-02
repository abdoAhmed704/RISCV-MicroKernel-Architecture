module riscv_mux_4_1 (
    input  logic [31:0] A,    // Sel = 2'b00
    input  logic [31:0] B,    // Sel = 2'b01
    input  logic [31:0] C,    // Sel = 2'b10
    input  logic [31:0] D,    // Sel = 2'b11
    input  logic [1:0]  Sel,
    output logic [31:0] out
);
    always_comb begin
        unique case (Sel)
            2'b00: out = A;
            2'b01: out = B;
            2'b10: out = C;
            2'b11: out = D;
        endcase
    end
endmodule
