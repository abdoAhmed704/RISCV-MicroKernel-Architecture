module T_Risc_core_mul_out();

    parameter XLEN = 32; 
    logic [2*XLEN-1 : 0] i_mul_out_booth_product; // the result of the product is 2*XLEN
    logic                i_mul_out_srcAsign;
    logic                i_mul_out_srcBsign;
    logic [1 : 0]        i_mul_out_ctrl;
    logic [XLEN-1 : 0]   o_mul_out_rslt;


    Risc_core_mul_out
    #(  
        .XLEN(XLEN)
    )
    M3
    (
    .i_mul_out_booth_product(i_mul_out_booth_product), // the result of the product is 2*XLEN
    .i_mul_out_srcAsign(i_mul_out_srcAsign),
    .i_mul_out_srcBsign(i_mul_out_srcBsign),
    .i_mul_out_ctrl(i_mul_out_ctrl),
    .o_mul_out_rslt(o_mul_out_rslt)              // RISC dest only has XLEN bits
    );


    initial #10000 $finish;
    

    initial begin
        i_mul_out_ctrl = 0 ; 
        i_mul_out_booth_product = {{32{1'b1}} , {30{1'b0}} , 2'b10};
        {i_mul_out_srcAsign , i_mul_out_srcBsign} = 2'b00;
        #10;
        repeat(3)begin
            {i_mul_out_srcAsign , i_mul_out_srcBsign} = {i_mul_out_srcAsign , i_mul_out_srcBsign} + 1'b1;
            #10;
        end 

        #20;
        i_mul_out_ctrl = 1 ; 
        {i_mul_out_srcAsign , i_mul_out_srcBsign} = 2'b00;
        #10;
        repeat(3)begin
            {i_mul_out_srcAsign , i_mul_out_srcBsign} = {i_mul_out_srcAsign , i_mul_out_srcBsign} + 1'b1;
            #10;
        end
        
        #20;
        i_mul_out_ctrl = 2 ; 
        {i_mul_out_srcAsign , i_mul_out_srcBsign} = 2'b00;
        #10;
        repeat(3)begin
            {i_mul_out_srcAsign , i_mul_out_srcBsign} = {i_mul_out_srcAsign , i_mul_out_srcBsign} + 1'b1;
            #10;
        end 
        
        #20;
        i_mul_out_ctrl = 3 ; 
        {i_mul_out_srcAsign , i_mul_out_srcBsign} = 2'b00;
        #10;
        repeat(3)begin
            {i_mul_out_srcAsign , i_mul_out_srcBsign} = {i_mul_out_srcAsign , i_mul_out_srcBsign} + 1'b1;
            #10;
        end 

    end
endmodule