
module fetch_prediction_logic_tb();

    // ?????? ???????? (reg)
    reg  [31:0] fetch_pc_tb;
    reg         predict_taken_tb;
    reg         btb_hit_tb;
    reg  [31:0] predicted_target_pc_tb;

    // ?????? ???????? (wire)
    wire        take_branch_decision_tb;
    wire [31:0] next_pc_prediction_tb;

    // ????? ??? DUT
    fetch_prediction_logic DUT (
        .fetch_pc(fetch_pc_tb),
        .predict_taken(predict_taken_tb),
        .btb_hit(btb_hit_tb),
        .predicted_target_pc(predicted_target_pc_tb),
        .take_branch_decision(take_branch_decision_tb),
        .next_pc_prediction(next_pc_prediction_tb)
    );

    initial begin
        $dumpfile("fetch_prediction_logic.vcd");
        $dumpvars;

        $display("Time | fetch_pc | taken | hit | pred_target | decision | next_pc");
        $display("-------------------------------------------------------------------------");
        $monitor("%4d | %8h |   %b   |  %b  |  %8h |    %b     | %8h", 
                 $time, fetch_pc_tb, predict_taken_tb, btb_hit_tb, predicted_target_pc_tb, take_branch_decision_tb, next_pc_prediction_tb);

        // ????? ????????
        fetch_pc_tb = 32'h0000_1000;
        predict_taken_tb = 0;
        btb_hit_tb = 0;
        predicted_target_pc_tb = 32'h0000_2000;
        #10;

        $display("************* Case 1: Absolute No Branch (0,0) *************");
        fetch_pc_tb = 32'h0000_1000; predict_taken_tb = 0; btb_hit_tb = 0;
        #10;

        $display("************* Case 2: False Hit (0,1) *************");
        predict_taken_tb = 0; btb_hit_tb = 1;
        #10;

        $display("************* Case 3: Missing BTB (1,0) *************");
        predict_taken_tb = 1; btb_hit_tb = 0;
        #10;

        $display("************* Case 4: Full Hit & Taken (1,1) *************");
        predict_taken_tb = 1; btb_hit_tb = 1;
        #10;

        $display("************* Case 5: PC Wrap-around Bound *************");
        fetch_pc_tb = 32'hFFFF_FFFC; // ??????? ??? PC+4 ??? ?? 00000000
        predict_taken_tb = 0; btb_hit_tb = 0;
        #10;

        $display("************* Case 6: Target Boundary Check (Taken at Wrap) *************");
        predicted_target_pc_tb = 32'hFFFF_FFFC;
        predict_taken_tb = 1; btb_hit_tb = 1;
        #10;

        #10;
        $finish;
    end

endmodule

