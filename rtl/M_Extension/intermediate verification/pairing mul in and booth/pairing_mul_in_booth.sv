module pairing_mul_in_booth
#(
    parameter XLEN = 32
)(
    input logic [XLEN-1 : 0]srcA,
    input logic [XLEN-1 : 0]srcB,
    input logic [1:0]funct3,
    input logic clk,
    input logic rstn,
    input logic en,
    output logic [2*XLEN-1 : 0]booth_prdct,
    output logic booth_dne
);

//mul_in_output
logic [XLEN-1 : 0] multiplicand;
logic [XLEN-1 : 0] multiplier;

Risc_core_mul_in
#(
    .XLEN(XLEN)
)
C1
(
    .i_mul_in_srcA(srcA),
    .i_mul_in_srcB(srcB),
    .i_mul_in_ctrl(funct3),
    .o_mul_in_multiplier(multiplier),
    .o_mul_in_multiplicand(multiplicand)
);

risc_v_core_Booth_product
#(
    .XLEN(XLEN)
)
C2
(
    .i_booth_multiplicand(multiplicand),
    .i_booth_multiplier(multiplier),
    .i_booth_clk(clk),
    .i_booth_rstn(rstn),
    .i_booth_en(en),
    .o_booth_product(booth_prdct),
    .o_booth_done(booth_dne)
);

endmodule