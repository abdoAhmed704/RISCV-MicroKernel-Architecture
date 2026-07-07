module T_full_mul();

    parameter XLEN = 32 ;

    logic [XLEN-1 : 0] srcA;
    logic [XLEN-1 : 0] srcB;
    logic              clk;
    logic              rstn;
    logic              en;
    logic [1:0]        fucnct3;
    logic[XLEN-1 : 0] rslt;
    logic             dne;

    full_mul 
#(
    .XLEN(XLEN)
)
Y1
(
    .srcA(srcA),
    .srcB(srcB),
    .clk(clk),
    .rstn(rstn),
    .en(en),
    .fucnct3(fucnct3),
    .rslt(rslt),
    .dne(dne)
);

    initial begin
        clk = 0 ; forever begin
            #20;
            clk = ! clk;
        end
    end


    initial begin
        rstn = 0;
        srcA = $random;
        srcB = $random;
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
        fucnct3 = $random;
        #1500;
    end

    $stop;
        

    end
endmodule