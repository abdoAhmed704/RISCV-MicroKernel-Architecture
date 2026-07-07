module T_Risc_core_mul_in();
    parameter XLEN = 32  ;
    logic  [XLEN-1 : 0] i_mul_in_srcA;
    logic  [XLEN-1 : 0] i_mul_in_srcB;
    logic  [1:0]        i_mul_in_ctrl;
    logic  [XLEN-1 : 0] o_mul_in_multiplier;
    logic  [XLEN-1 : 0] o_mul_in_multiplicand ;



    Risc_core_mul_in 
    #(
        .XLEN(XLEN)
    )
    M1
    (
        .i_mul_in_srcA(i_mul_in_srcA),
        .i_mul_in_srcB(i_mul_in_srcB),
        .i_mul_in_ctrl(i_mul_in_ctrl),
        .o_mul_in_multiplier(o_mul_in_multiplier),
        .o_mul_in_multiplicand(o_mul_in_multiplicand) 
    );

    initial #1000 $finish;




    initial begin
        i_mul_in_srcA = -50 ;
        i_mul_in_srcB = -25;

        repeat(100)fork
            #10; i_mul_in_srcA = i_mul_in_srcA + 1 ;
            #10; i_mul_in_srcB = i_mul_in_srcB + 1 ;
            #10; i_mul_in_ctrl     = $random; 
        join
        
    end
endmodule