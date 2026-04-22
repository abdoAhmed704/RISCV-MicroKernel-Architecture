module register_file(A1, A2, A3, WD3, w_en, clk, RD1, RD2);

input [4:0] A1, A2, A3;
input [31:0] WD3;
input w_en, clk;
output [31:0] RD1, RD2;


reg [31:0] registers [0:31];

assign RD1 = (A1 != 0)? registers[A1]: 0;
assign RD2 = (A2 != 0)? registers[A2]: 0;

always @(negedge clk) begin
    if (w_en)begin
        registers[A3] <= WD3;
    end
end

endmodule

