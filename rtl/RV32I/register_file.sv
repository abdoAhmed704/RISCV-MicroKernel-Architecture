module register_file(A1, A2, A3, WD3, w_en, clk, RD1, RD2);
    input [4:0] A1, A2, A3;
    input [31:0] WD3;
    input w_en, clk;
    output [31:0] RD1, RD2;

    reg [31:0] registers [0:31];

    // Initialize all registers to 0
    initial begin
        for (int i = 0; i < 32; i++) registers[i] = 32'h0;
    end

    assign RD1 = (A1 != 0) ? registers[A1] : 32'b0;
    assign RD2 = (A2 != 0) ? registers[A2] : 32'b0;

    always @(negedge clk) begin
        // CRITICAL: Check A3 != 0 so x0 stays 0
        if (w_en && (A3 != 5'b0)) begin
            registers[A3] <= WD3;
        end
    end
endmodule