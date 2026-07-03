module riscv_pc_target (
    input [31:0] PC,
    input [31:0] ImmExt,
    output reg [31:0] PC_Target
);

    always @(*) begin
        PC_Target = PC + ImmExt; // Calculate the target address for branch instructions
    end

endmodule
