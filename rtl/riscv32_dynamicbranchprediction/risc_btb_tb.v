module btb_table_tb();
    reg          clk_tb, rst_n_tb;
    reg   [31:0] fetch_pc_tb;
    wire  [31:0] predicted_target_pc_tb;
    reg          write_en_tb;
    reg   [31:0] exe_pc_tb;
    reg   [31:0] actual_target_pc_tb;

    // ????? ?????? ???? ???
    initial clk_tb = 1'b0;
    always #15 clk_tb = ~clk_tb;

    initial begin
        $dumpfile("btb_table.vcd");
        $dumpvars;

        // ???? ???????? ??? BTB (????? ???????? ????? ??? Hex)
        $display("Time(ns) | rst | fetch_pc | pred_target | write_en | exe_pc   | actual_target");
        $display("--------------------------------------------------------------------------------");
        $monitor("%8d |  %b  | %8h |  %8h   |    %b     | %8h |   %8h", 
                 $time, rst_n_tb, fetch_pc_tb, predicted_target_pc_tb, write_en_tb, exe_pc_tb, actual_target_pc_tb);

        $display("*************Test case 1 (Reset Case)******************");
        rst_n_tb = 0; fetch_pc_tb = 32'h0; write_en_tb = 0; exe_pc_tb = 32'h0; actual_target_pc_tb = 32'h0;
        #15; rst_n_tb = 1; 

        $display("*************Test case 2 (Alignment & Zero Target)******************");
        @(posedge clk_tb); #2;
        exe_pc_tb           = 32'h0000_0004; // index = 1
        actual_target_pc_tb = 32'h0000_2000; // ????? ?????? ????
        write_en_tb         = 1'b1;
        
        @(posedge clk_tb); #2;
        write_en_tb         = 1'b0;
        fetch_pc_tb         = 32'h0000_0007; // ??? ??? index = 1 ?????? ?? ??? Alignment
        
        $display("*************Test case 3 (Max Bounds & Wrap-around)******************");
        @(posedge clk_tb); #2;
        exe_pc_tb           = 32'hFFFF_FFFF; // index = 8'hFF
        actual_target_pc_tb = 32'hFFFF_FFFC; // ???? ????? ??????
        write_en_tb         = 1'b1;
        
        @(posedge clk_tb); #2;
        write_en_tb         = 1'b0;
        fetch_pc_tb         = 32'h0000_03FC; // ??? ??? index = 8'hFF
        
        $display("*************Test case 4 (Collision Case)******************");
        @(posedge clk_tb); #2;
        // ????? ?????? ?? ??? ?????? ??? index = 8'h0A
        fetch_pc_tb         = 32'h0000_0028; 
        exe_pc_tb           = 32'h0000_0028; 
        actual_target_pc_tb = 32'h1234_5678;
        write_en_tb         = 1'b1;
        
        @(posedge clk_tb); #2;
        write_en_tb         = 1'b0; // ??? ??????? ?????? ???? ??????? ?????? 12345678
        
        @(posedge clk_tb);
        #30;
        $finish;
    end

    // ????? ??? DUT
    btb_table DUT (
        .clk(clk_tb),
        .rst_n(rst_n_tb),
        .fetch_pc(fetch_pc_tb),
        .predicted_target_pc(predicted_target_pc_tb),
        .write_en(write_en_tb),
        .exe_pc(exe_pc_tb),
        .actual_target_pc(actual_target_pc_tb)
    );

endmodule

