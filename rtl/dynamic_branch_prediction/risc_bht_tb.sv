module bht_table_tb();
    reg          clk_tb,rst_n_tb;
    reg   [31:0] fetch_pc_tb;
    wire  [1:0]  exe_current_counter_tb;
    wire         predict_taken_tb;
    reg          write_en_tb;
    reg   [31:0] exe_pc_tb;
    reg   [1:0]  write_counter_tb;

   
       initial clk_tb = 1'b0;
       always #15 clk_tb = ~clk_tb;

   initial begin
    $dumpfile("bht_table.vcd");
    $dumpvars ;

        // -------------------------------------------------------------
        // ????? ??? $monitor ????? ???????? ???????? ????????
        // -------------------------------------------------------------
        $display("Time(ns) | rst | fetch_pc | predict_taken | write_en | exe_pc   | write_counter | exe_curr_cnt");
        $display("-------------------------------------------------------------------------------------------------");
        $monitor("%8d |  %b  | %8h |       %b       |    %b     | %8h |       %b      |      %b", 
                 $time, rst_n_tb, fetch_pc_tb, predict_taken_tb, write_en_tb, exe_pc_tb, write_counter_tb, exe_current_counter_tb);
  

    $display("*************Test case 1 (Reset Case)******************");
    rst_n_tb = 0; fetch_pc_tb = 32'h0; write_en_tb = 0; exe_pc_tb = 32'h0; write_counter_tb = 2'b00;
    #15; rst_n_tb = 1; // ????? ??? ???? ?????? ??????

        $display("*************Test case 2 (Alignment corner)******************");

    // 2. Test Alignment corner (fetch_pc[9:2] should be 8'h01 for both)
    @(posedge clk_tb); #2;
    fetch_pc_tb = 32'h0000_0004; // index = 1
    @(posedge clk_tb); #2;
    fetch_pc_tb = 32'h0000_0007; // index = 1 (??? ??????)
    
     $display("*************Test case 3 (Overflow/Wrap-around)******************");

    // 3. Test Overflow/Wrap-around ??? ?? index ???? ????? ?????? ??? MSB
    @(posedge clk_tb); #2;
    fetch_pc_tb = 32'hFFFF_FFFF; // ??? index
    @(posedge clk_tb); #2;
    fetch_pc_tb = 32'h0000_03FC; // ??? index
            $display("*************Test case 4 (Collision Case)******************");

    // 4. Test Collision Case (Read & Write at index 8'h0A)
    @(posedge clk_tb); #2;
    fetch_pc_tb = 32'h0000_0028; // index = 8'h0A
    exe_pc_tb   = 32'h0000_0028; // index = 8'h0A
    write_counter_tb = 2'b11;
    write_en_tb = 1; // ????? ????? ?? ??? ??????
    
    @(posedge clk_tb); #2;
    write_en_tb = 0; // ???? ???????
    // ??? ??????? predict_taken ???? ??? 2'b11 ???? ?????? ??????? ???? ????

            $display("*************Test case 5 (Saturating Cases)******************");

    // -------------------------------------------------------------
    // 5. ????? ????? ??????? ??????? (Saturating Cases Verification)
    // -------------------------------------------------------------
    
    // ?????? ???? ??? Strongly Not Taken (00)
    @(posedge clk_tb); #2;
    exe_pc_tb        = 32'h0000_0040; // index = 8'h10
    write_counter_tb = 2'b00;         // Strongly Not Taken
    write_en_tb      = 1'b1;
    
    // ?????? ???? ??? Strongly Taken (11) ?? ???? ???
    @(posedge clk_tb); #2;
    exe_pc_tb        = 32'h0000_0044; // index = 8'h11
    write_counter_tb = 2'b11;         // Strongly Taken
    write_en_tb      = 1'b1;

    // ????? ??????? ???? ???????? ?? ???????? ???????
    @(posedge clk_tb); #2;
    write_en_tb      = 1'b0;          // ???? ??????? ????
    
    // ????? ?????? ????? (index 8'h10) ?????? ?? ????? (??????? 0)
    fetch_pc_tb      = 32'h0000_0040; 
    
    @(posedge clk_tb); #2;
    // ??? ??????? ???????? predict_taken_tb ???? 0 
    // ??? ??? ????? ???? ???? ??? ?????? (index 8'h11)
    fetch_pc_tb      = 32'h0000_0044; 

    @(posedge clk_tb);
    // ??? ??????? predict_taken_tb ???? 1
    #30;
    $finish;
end

bht_table DUT
    (
        .clk(clk_tb),
        .rst_n(rst_n_tb),
        .fetch_pc(fetch_pc_tb),
        .exe_pc(exe_pc_tb),
        .write_en(write_en_tb),
        .write_counter(write_counter_tb),
        .predict_taken(predict_taken_tb),
        .exe_current_counter(exe_current_counter_tb)
    );

endmodule


