import M_ex_sgnls::*;
module T_M_extension_TOP();

    parameter XLEN = 32;

    logic i_mul_div_clk;
    logic i_mul_div_rst_n;
    logic i_mul_div_en;
    logic [XLEN-1:0] i_mul_div_srcA;
    logic [XLEN-1:0] i_mul_div_srcB;
    logic [2:0] i_mul_div_funct3;
    logic o_mul_div_dne;
    logic o_mul_div_busy;
    logic o_mul_div_div_by_zero;
    logic o_mul_div_overflow;
    logic [XLEN-1:0] o_mul_div_rslt;

    //global object for testing
    sig M1 = new ;

M_extension_TOP 
#(
    .XLEN(XLEN)
)
M1_TB
(
    .i_mul_div_clk(i_mul_div_clk),
    .i_mul_div_rst_n(i_mul_div_rst_n),
    .i_mul_div_en(i_mul_div_en),
    .i_mul_div_srcA(i_mul_div_srcA),
    .i_mul_div_srcB(i_mul_div_srcB),
    .i_mul_div_funct3(i_mul_div_funct3),
    .o_mul_div_dne(o_mul_div_dne),
    .o_mul_div_busy(o_mul_div_busy),
    .o_mul_div_div_by_zero(o_mul_div_div_by_zero),
    .o_mul_div_overflow(o_mul_div_overflow),
    .o_mul_div_rslt(o_mul_div_rslt)
);

initial begin
    i_mul_div_clk = 0;
    forever begin
        #5;
        i_mul_div_clk = ~ i_mul_div_clk;
    end
end

initial begin
    i_mul_div_rst_n = 0;
    i_mul_div_srcA  = 5;
    i_mul_div_srcB  = 15;
    i_mul_div_en    = 0;
    i_mul_div_funct3= 3;

    #10;

    i_mul_div_rst_n = 1;
    i_mul_div_srcA  = 5;
    i_mul_div_srcB  = 15;
    i_mul_div_en    = 0;
    i_mul_div_funct3= 3;

    #10;

    i_mul_div_rst_n = 0;
    i_mul_div_srcA  = 5;
    i_mul_div_srcB  = 15;
    i_mul_div_en    = 1;
    i_mul_div_funct3= 3;

    #10;

    i_mul_div_rst_n = 0;
    i_mul_div_srcA  = 5;
    i_mul_div_srcB  = 15;
    i_mul_div_en    = 0;
    i_mul_div_funct3= 3;

    #10;

    i_mul_div_rst_n = 0;
    i_mul_div_srcA  = 5;
    i_mul_div_srcB  = 15;
    i_mul_div_en    = 1;
    i_mul_div_funct3= 3;

    repeat(80)
        begin
            #700;
            i_mul_div_en = 1;
            i_mul_div_rst_n = 0;
            M1.randomize();
            i_mul_div_funct3 = M1.i_mul_div_funct3;
            i_mul_div_srcA = M1.i_mul_div_srcA;
            i_mul_div_srcB = M1.i_mul_div_srcB;
        end
        $stop;

end
endmodule