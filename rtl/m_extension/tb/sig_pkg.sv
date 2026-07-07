package M_ex_sgnls;
    parameter XLEN = 32;

    class sig;
        rand logic [XLEN-1 : 0] i_mul_div_srcA;
        rand logic [XLEN-1 : 0] i_mul_div_srcB;
        rand logic [2:0]i_mul_div_funct3;

        function new (logic [XLEN-1 : 0] i_mul_div_srcA = 0 , [XLEN-1 : 0] i_mul_div_srcB = 0 , logic [2:0] i_mul_div_funct3 = 0);
            this.i_mul_div_srcA = i_mul_div_srcA;
            this.i_mul_div_srcB = i_mul_div_srcB;
            this.i_mul_div_funct3 = i_mul_div_funct3;
        endfunction
    endclass
endpackage
