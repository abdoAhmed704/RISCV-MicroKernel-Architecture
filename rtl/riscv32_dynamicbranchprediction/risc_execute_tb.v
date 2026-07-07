 
module execute_prediction_logic_tb();

     
    reg  [31:0] exe_pc_tb;
    reg         predict_taken_old_tb;
    reg         exe_is_branch_tb;
    reg         actual_taken_tb;
    reg  [31:0] actual_target_pc_tb;
    reg  [1:0]  current_counter_tb;

    
    wire        bht_write_en_tb;
    wire        btb_write_en_tb;
    wire [1:0]  next_counter_tb;
    wire        flush_pipeline_tb;
    wire [31:0] corrected_pc_tb;

    
    execute_prediction_logic DUT (
        .exe_pc(exe_pc_tb),
        .predict_taken_old(predict_taken_old_tb),
        .exe_is_branch(exe_is_branch_tb),
        .actual_taken(actual_taken_tb),
        .actual_target_pc(actual_target_pc_tb),
        .current_counter(current_counter_tb),
        .bht_write_en(bht_write_en_tb),
        .btb_write_en(btb_write_en_tb),
        .next_counter(next_counter_tb),
        .flush_pipeline(flush_pipeline_tb),
        .corrected_pc(corrected_pc_tb)
    );

    initial begin
        $dumpfile("execute_prediction_logic.vcd");
        $dumpvars;

        $display("Time | is_br | pred_old | act_taken | curr_cnt | next_cnt | bht_we | btb_we | flush | corrected_pc");
        $display("------------------------------------------------------------------------------------------------------");
        $monitor("%4d |   %b   |    %b     |     %b     |    %b    |    %b    |   %b    |   %b    |   %b   | %8h", 
                 $time, exe_is_branch_tb, predict_taken_old_tb, actual_taken_tb, current_counter_tb, next_counter_tb, bht_write_en_tb, btb_write_en_tb, flush_pipeline_tb, corrected_pc_tb);

        
        exe_pc_tb = 32'h0000_1000;
        actual_target_pc_tb = 32'h0000_2000;
        predict_taken_old_tb = 0; exe_is_branch_tb = 0; actual_taken_tb = 0; current_counter_tb = 2'b00;
        #10;

        $display("************* Case 1 & 2: Correct Predictions (No Flush) *************");
        exe_is_branch_tb = 1; predict_taken_old_tb = 1; actual_taken_tb = 1; current_counter_tb = 2'b10;
        #10;
        predict_taken_old_tb = 0; actual_taken_tb = 0; current_counter_tb = 2'b01;
        #10;

        $display("************* Case 3 & 4: Mispredictions (Flush Active) *************");
        predict_taken_old_tb = 1; actual_taken_tb = 0; 
        #10;
        predict_taken_old_tb = 0; actual_taken_tb = 1; 
        #10;

        $display("************* Case 5: Non-Branch Instruction Check *************");
        exe_is_branch_tb = 0; actual_taken_tb = 1; 
        #10;

        $display("************* Case 6: Counter Saturation Lower Bound (00) *************");
        exe_is_branch_tb = 1; actual_taken_tb = 0; current_counter_tb = 2'b00; 
        #10;
        actual_taken_tb = 1; 
        #10;

        $display("************* Case 7: Counter Saturation Upper Bound (11) *************");
        actual_taken_tb = 1; current_counter_tb = 2'b11; 
        #10;
        actual_taken_tb = 0; 
        #10;

        $display("************* Case 8: PC Wrap-around Bound *************");
        exe_pc_tb = 32'hFFFF_FFFC; actual_taken_tb = 0;
        #10;

        #10;
        $finish;
    end

endmodule



