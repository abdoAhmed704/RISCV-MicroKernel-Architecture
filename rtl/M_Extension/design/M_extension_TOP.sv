module M_extension_TOP 
#(
    parameter XLEN = 32
)(
    input logic i_mul_div_clk,
    input logic i_mul_div_rst_n,
    input logic i_mul_div_en,
    input logic [XLEN-1:0] i_mul_div_srcA,
    input logic [XLEN-1:0] i_mul_div_srcB,
    input logic [2:0] i_mul_div_funct3,
    output logic o_mul_div_dne,
    output logic o_mul_div_busy,
    output logic o_mul_div_div_by_zero,
    output logic o_mul_div_overflow,
    output logic [XLEN-1:0] o_mul_div_rslt
);

//intermediate signals
logic [XLEN-1 : 0] multiplicand;
logic [XLEN-1 : 0] multiplier;
logic [2*XLEN-1 : 0] product;

logic [XLEN-1 : 0] dividend;
logic [XLEN-1 : 0] divisor;
logic [XLEN-1 : 0] qotient;
logic [XLEN-1 : 0] rem;

//handshake signals
logic booth_dne;
logic non_rstoring_dne;

logic mul_strt;
logic div_strt;

//mux selectors
logic slct_fast;
logic slct_div_mul;

//stored results
logic [XLEN-1 : 0]fast_rslt;
logic [XLEN-1 : 0]mul_unit_rslt;
logic [XLEN-1 : 0]div_rslt;

//intermediate outputs of MUX's
logic [XLEN-1 : 0]rslt_1;  // div vs mul



Risc_core_mul_in
#(
     .XLEN(XLEN)
)
risc_v_core_mul_in
(
    .i_mul_in_srcA(i_mul_div_srcA),
    .i_mul_in_srcB(i_mul_div_srcB),
    .i_mul_in_ctrl(i_mul_div_funct3[1:0]),
    .o_mul_in_multiplier(multiplier),
    .o_mul_in_multiplicand(multiplicand)
);

risc_v_core_Booth_product
#(
    .XLEN(XLEN) 
)
risc_v_core_booth
(
    .i_booth_multiplicand(multiplicand),
    .i_booth_multiplier(multiplier),
    .i_booth_clk(i_mul_div_clk),
    .i_booth_rstn(i_mul_div_rst_n),
    .i_booth_en(mul_strt),
    .o_booth_product(product),
    .o_booth_done(booth_dne)
);

risc_v_mul_div_ctrl #(
    .XLEN(XLEN)
)
risc_v_core_mul_div_ctrl 
(
    .i_mul_div_ctrl_clk(i_mul_div_clk),
    .i_mul_div_ctrl_rstn(i_mul_div_rst_n),
    .i_mul_div_ctrl_en(i_mul_div_en),
    .i_mul_div_ctrl_div_dne(non_rstoring_dne),
    .i_mul_div_ctrl_mul_dne(booth_dne),
    .i_mul_div_ctrl_funct_3(i_mul_div_funct3),
    .i_mul_div_ctrl_srcA(i_mul_div_srcA),
    .i_mul_div_ctrl_srcB(i_mul_div_srcB),
    .o_mul_div_ctrl_mul_start(mul_strt),
    .o_mul_div_ctrl_div_start(div_strt),
    .o_mul_div_ctrl_dne(o_mul_div_dne),
    .o_mul_div_ctrl_busy(o_mul_div_busy),
    .o_mul_div_ctrl_overflow(o_mul_div_overflow),
    .o_mul_div_ctrl_div_by_zero(o_mul_div_div_by_zero),
    .o_mul_div_ctrl_selector_btween_mul_div(slct_div_mul),
    .o_mul_div_ctrl_selector_btween_fast_MulDiv(slct_fast),
    .o_mul_div_ctrl_fast_rslt(fast_rslt)
);

Risc_core_mul_out
#(
    .XLEN(XLEN)
)
risc_v_core_mul_out
(
    .i_mul_out_booth_product(product), // the result of the product is 2*XLEN
    .i_mul_out_srcAsign(i_mul_div_srcA[XLEN-1]),
    .i_mul_out_srcBsign(i_mul_div_srcB[XLEN-1]),
    .i_mul_out_ctrl(i_mul_div_funct3[1:0]),
    .o_mul_out_rslt(mul_unit_rslt)              // RISC dest only has XLEN bits
);

i_risc_v_div 
#(
    .XLEN(XLEN)
) 
risc_v_core_div_in
(
    .i_div_in_srcA(i_mul_div_srcA),
    .i_div_in_srcB(i_mul_div_srcB),
    .i_div_ctrl(i_mul_div_funct3[1:0]),
    .o_div_divindend(dividend),
    .o_div_divisor(divisor)
);

RISC_V_non_restoring_div
#(
    .XLEN(XLEN)
)
risc_v_core_nn_restoring
(
    .start_from_majoar_FSM(div_strt),
    .non_restoring_clk(i_mul_div_clk),
    .non_restoring_rstn(i_mul_div_rst_n),
    .dividend(dividend),
    .divisor(divisor),
    .non_restoring_Qoutient(qotient),
    .non_restoring_remainder(rem),
    .non_restoring_div_dne_for_major_machine(non_rstoring_dne)
);

o_risc_v_div
#(
    .XLEN(XLEN)
)
risc_v_core_div_out
(
    .o_div_ctrl(i_mul_div_funct3[1:0]),
    .o_srcAsing(i_mul_div_srcA[XLEN-1]),  //dividend
    .o_srcBsign(i_mul_div_srcB[XLEN-1]), //divisor
    .o_div_rem(rem),
    .o_div_Qoutient(qotient),
    .o_div_result(div_rslt)
);

assign rslt_1         = slct_div_mul ? div_rslt : mul_unit_rslt ;
assign o_mul_div_rslt = slct_fast    ? fast_rslt     : rslt_1;

    
endmodule