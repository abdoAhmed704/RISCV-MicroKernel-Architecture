module T_risc_v_core_Booth_product();

    parameter XLEN = 32 ;

    logic [XLEN-1 : 0]   i_booth_multiplicand;
    logic [XLEN-1 : 0]   i_booth_multiplier;
    logic                i_booth_clk;
    logic                i_booth_rstn;
    logic                i_booth_en;
    logic [2*XLEN-1 : 0] o_booth_product;
    logic                o_booth_done;

    risc_v_core_Booth_product
    #(
        .XLEN(XLEN)
    )
    M5
    (
        .i_booth_multiplicand(i_booth_multiplicand),
        .i_booth_multiplier(i_booth_multiplier),
        .i_booth_clk(i_booth_clk),
        .i_booth_rstn(i_booth_rstn),
        .i_booth_en(i_booth_en),
        .o_booth_product(o_booth_product),
        .o_booth_done(o_booth_done)
    );

    initial begin
        i_booth_clk = 0 ; forever begin
            #5;
            i_booth_clk = ! i_booth_clk;
        end
    end

    initial begin
        #1000 $finish;
    end

    initial begin
        i_booth_rstn = 0;
        #10;
        i_booth_rstn = 1;
        #10;
        i_booth_rstn = 0;
        #10;
        i_booth_rstn = 1;


        #10;
        i_booth_multiplicand = 1;
        i_booth_multiplier = 7;
        i_booth_en = 0;


        #100;
        i_booth_multiplicand = 1;
        i_booth_multiplier = 7;
        i_booth_en = 1;
    end
endmodule