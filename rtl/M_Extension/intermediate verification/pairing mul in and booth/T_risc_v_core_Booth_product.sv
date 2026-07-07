module T_pairing_mul_in_booth();

    parameter XLEN = 32 ;

    logic [XLEN-1 : 0]srcA;
    logic [XLEN-1 : 0]srcB;
    logic [1:0]funct3;
    logic clk;
    logic rstn;
    logic en;
    logic [2*XLEN-1 : 0] booth_prdct;
    logic booth_dne;

    pairing_mul_in_booth
#(
    .XLEN(XLEN)
)
T1
(
    .srcA(srcA),
    .srcB(srcB),
    .funct3(funct3),
    .clk(clk),
    .rstn(rstn),
    .en(en),
    .booth_prdct(booth_prdct),
    .booth_dne(booth_dne)
);

    initial begin
        clk = 0 ; forever begin
            #5;
            clk = ! clk;
        end
    end


    initial begin
        rstn = 0;
        #10;
        rstn = 1;
        #10;
        rstn = 0;
        #10;
        rstn = 1;

        #10;
        
    repeat(70)begin
        
        srcA = $random;
        srcB = $random;
        en = 1;
        funct3 = $random;
        #320;
    end

    $stop;
        

    end
endmodule