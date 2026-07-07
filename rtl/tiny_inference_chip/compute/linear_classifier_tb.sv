`timescale 1ns/1ps

// linear_classifier_tb.sv — Self-Checking Testbench for Linear Classifier
// Runs 5 test cases with automated PASS/FAIL checking.
// Compatible with QuestaSim: vlog + vsim -c -do "run -all"
//
// Test cases:
//   1. Basic classification   — hand-computed W·x with mixed signs
//   2. Identity weight matrix — y = I·x = x (passthrough)
//   3. Negative weights       — verify signed arithmetic
//   4. Zero input vector      — all scores must be 0
//   5. Targeted argmax        — one class deliberately dominant

module linear_classifier_tb;

    // ─── Parameters ──────────────────────────────────────────────
    localparam DW = 8;
    localparam AW = 32;
    localparam N  = 4;
    localparam CLK_PERIOD = 10;

    // ─── DUT Signals ─────────────────────────────────────────────
    reg                       clk;
    reg                       rst_n;

    reg                       wr_weight;
    reg  [1:0]                wr_w_row;
    reg  [1:0]                wr_w_col;
    reg  signed [DW-1:0]      wr_w_data;

    reg                       wr_input;
    reg  [1:0]                wr_i_addr;
    reg  signed [DW-1:0]      wr_i_data;

    reg                       start;

    wire signed [AW-1:0]      scores [0:N-1];
    wire [1:0]                predicted_class;
    wire                      done;

    // ─── DUT Instantiation ───────────────────────────────────────

    linear_classifier #(
        .DW(DW), .AW(AW), .N(N)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .wr_weight       (wr_weight),
        .wr_w_row        (wr_w_row),
        .wr_w_col        (wr_w_col),
        .wr_w_data       (wr_w_data),
        .wr_input        (wr_input),
        .wr_i_addr       (wr_i_addr),
        .wr_i_data       (wr_i_data),
        .start           (start),
        .scores          (scores),
        .predicted_class (predicted_class),
        .done            (done)
    );

    // ─── Clock Generation ────────────────────────────────────────
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ─── Test Infrastructure ─────────────────────────────────────
    integer total_errors;
    integer test_errors;
    integer test_num;

    // ─── Helper Tasks ────────────────────────────────────────────

    task automatic do_reset;
        begin
            rst_n     = 0;
            start     = 0;
            wr_weight = 0;
            wr_input  = 0;
            wr_w_row  = 0;
            wr_w_col  = 0;
            wr_w_data = 0;
            wr_i_addr = 0;
            wr_i_data = 0;
            repeat (3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task automatic write_weight(
        input [1:0]          row,
        input [1:0]          col,
        input signed [DW-1:0] data
    );
        begin
            @(posedge clk);
            wr_weight = 1;
            wr_w_row  = row;
            wr_w_col  = col;
            wr_w_data = data;
            @(posedge clk);
            wr_weight = 0;
        end
    endtask

    task automatic write_input(
        input [1:0]          addr,
        input signed [DW-1:0] data
    );
        begin
            @(posedge clk);
            wr_input  = 1;
            wr_i_addr = addr;
            wr_i_data = data;
            @(posedge clk);
            wr_input  = 0;
        end
    endtask

    task automatic run_and_wait;
        begin
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
            // Wait for done
            wait (done === 1);
            @(posedge clk);
        end
    endtask

    task automatic check_scores(
        input integer exp0,
        input integer exp1,
        input integer exp2,
        input integer exp3,
        input integer exp_class
    );
        integer exp [0:3];
        integer i;
        begin
            exp[0] = exp0;
            exp[1] = exp1;
            exp[2] = exp2;
            exp[3] = exp3;

            for (i = 0; i < 4; i = i + 1) begin
                if (scores[i] !== exp[i]) begin
                    $display("  [FAIL] Score[%0d]: expected %0d, got %0d", i, exp[i], scores[i]);
                    test_errors = test_errors + 1;
                end else begin
                    $display("  [PASS] Score[%0d] = %0d", i, scores[i]);
                end
            end

            if (predicted_class !== exp_class[1:0]) begin
                $display("  [FAIL] Predicted class: expected %0d, got %0d", exp_class, predicted_class);
                test_errors = test_errors + 1;
            end else begin
                $display("  [PASS] Predicted class = %0d", predicted_class);
            end
        end
    endtask

    // ─── Main Test Sequence ──────────────────────────────────────

    initial begin

        total_errors = 0;
        test_num     = 0;

        $display("");
        $display("================================================================");
        $display("         LINEAR CLASSIFIER — SELF-CHECKING TESTBENCH");
        $display("================================================================");

        // ═══════════════════════════════════════════════════════════
        // TEST 1: Basic classification
        //   W = [[1,2,5,0],[6,0,0,1],[3,4,-1,5],[2,2,6,0]]
        //   x = [8, 2, 15, 0]
        //   y[j] = Σ_i x[i]*W[i][j]
        //   y[0] = 8*1  + 2*6  + 15*3  + 0*2  = 8+12+45+0   = 65
        //   y[1] = 8*2  + 2*0  + 15*4  + 0*2  = 16+0+60+0   = 76
        //   y[2] = 8*5  + 2*0  + 15*(-1)+0*6  = 40+0-15+0   = 25
        //   y[3] = 8*0  + 2*1  + 15*5  + 0*0  = 0+2+75+0    = 77
        //   argmax = 3 (score 77)
        // ═══════════════════════════════════════════════════════════

        test_num = 1;
        test_errors = 0;
        $display("");
        $display("─── TEST %0d: Basic Classification ───", test_num);

        do_reset();

        // Load weights row by row
        write_weight(0, 0, 8'd1);  write_weight(0, 1, 8'd2);
        write_weight(0, 2, 8'd5);  write_weight(0, 3, 8'd0);
        write_weight(1, 0, 8'd6);  write_weight(1, 1, 8'd0);
        write_weight(1, 2, 8'd0);  write_weight(1, 3, 8'd1);
        write_weight(2, 0, 8'd3);  write_weight(2, 1, 8'd4);
        write_weight(2, 2, -8'sd1); write_weight(2, 3, 8'd5);
        write_weight(3, 0, 8'd2);  write_weight(3, 1, 8'd2);
        write_weight(3, 2, 8'd6);  write_weight(3, 3, 8'd0);

        // Load input features
        write_input(0, 8'd8);
        write_input(1, 8'd2);
        write_input(2, 8'd15);
        write_input(3, 8'd0);

        // Run classification
        run_and_wait();

        // Check results
        //                   s0  s1  s2  s3  class
        check_scores(       65,  76,  25,  77,   3);

        total_errors = total_errors + test_errors;

        // ═══════════════════════════════════════════════════════════
        // TEST 2: Identity weight matrix — y = x
        //   W = I4, x = [3, -7, 10, 1]
        //   Expected: y = [3, -7, 10, 1], argmax = 2
        // ═══════════════════════════════════════════════════════════

        test_num = 2;
        test_errors = 0;
        $display("");
        $display("─── TEST %0d: Identity Weight Matrix ───", test_num);

        do_reset();

        // Identity matrix
        write_weight(0, 0, 8'd1);  write_weight(0, 1, 8'd0);
        write_weight(0, 2, 8'd0);  write_weight(0, 3, 8'd0);
        write_weight(1, 0, 8'd0);  write_weight(1, 1, 8'd1);
        write_weight(1, 2, 8'd0);  write_weight(1, 3, 8'd0);
        write_weight(2, 0, 8'd0);  write_weight(2, 1, 8'd0);
        write_weight(2, 2, 8'd1);  write_weight(2, 3, 8'd0);
        write_weight(3, 0, 8'd0);  write_weight(3, 1, 8'd0);
        write_weight(3, 2, 8'd0);  write_weight(3, 3, 8'd1);

        write_input(0,  8'sd3);
        write_input(1, -8'sd7);
        write_input(2,  8'sd10);
        write_input(3,  8'sd1);

        run_and_wait();

        check_scores(3, -7, 10, 1, 2);

        total_errors = total_errors + test_errors;

        // ═══════════════════════════════════════════════════════════
        // TEST 3: Negative weights — verify signed arithmetic
        //   W = [[-1,-2,-3,-4],
        //        [ 2, 3, 4, 5],
        //        [-1, 0, 1, 0],
        //        [ 0,-1, 0, 1]]
        //   x = [4, 2, 6, 3]
        //   y[0] = 4*(-1)+2*2+6*(-1)+3*0   = -4+4-6+0     = -6
        //   y[1] = 4*(-2)+2*3+6*0+3*(-1)   = -8+6+0-3     = -5
        //   y[2] = 4*(-3)+2*4+6*1+3*0      = -12+8+6+0    = 2
        //   y[3] = 4*(-4)+2*5+6*0+3*1      = -16+10+0+3   = -3
        //   argmax = 2
        // ═══════════════════════════════════════════════════════════

        test_num = 3;
        test_errors = 0;
        $display("");
        $display("─── TEST %0d: Negative Weights ───", test_num);

        do_reset();

        write_weight(0, 0, -8'sd1); write_weight(0, 1, -8'sd2);
        write_weight(0, 2, -8'sd3); write_weight(0, 3, -8'sd4);
        write_weight(1, 0,  8'sd2); write_weight(1, 1,  8'sd3);
        write_weight(1, 2,  8'sd4); write_weight(1, 3,  8'sd5);
        write_weight(2, 0, -8'sd1); write_weight(2, 1,  8'sd0);
        write_weight(2, 2,  8'sd1); write_weight(2, 3,  8'sd0);
        write_weight(3, 0,  8'sd0); write_weight(3, 1, -8'sd1);
        write_weight(3, 2,  8'sd0); write_weight(3, 3,  8'sd1);

        write_input(0, 8'sd4);
        write_input(1, 8'sd2);
        write_input(2, 8'sd6);
        write_input(3, 8'sd3);

        run_and_wait();

        check_scores(-6, -5, 2, -3, 2);

        total_errors = total_errors + test_errors;

        // ═══════════════════════════════════════════════════════════
        // TEST 4: Zero input vector — all scores must be 0
        //   W = (same as test 1), x = [0, 0, 0, 0]
        //   Expected: y = [0, 0, 0, 0], argmax = 0 (first max)
        // ═══════════════════════════════════════════════════════════

        test_num = 4;
        test_errors = 0;
        $display("");
        $display("─── TEST %0d: Zero Input Vector ───", test_num);

        do_reset();

        write_weight(0, 0, 8'd1);  write_weight(0, 1, 8'd2);
        write_weight(0, 2, 8'd5);  write_weight(0, 3, 8'd0);
        write_weight(1, 0, 8'd6);  write_weight(1, 1, 8'd0);
        write_weight(1, 2, 8'd0);  write_weight(1, 3, 8'd1);
        write_weight(2, 0, 8'd3);  write_weight(2, 1, 8'd4);
        write_weight(2, 2, -8'sd1); write_weight(2, 3, 8'd5);
        write_weight(3, 0, 8'd2);  write_weight(3, 1, 8'd2);
        write_weight(3, 2, 8'd6);  write_weight(3, 3, 8'd0);

        write_input(0, 8'd0);
        write_input(1, 8'd0);
        write_input(2, 8'd0);
        write_input(3, 8'd0);

        run_and_wait();

        check_scores(0, 0, 0, 0, 0);

        total_errors = total_errors + test_errors;

        // ═══════════════════════════════════════════════════════════
        // TEST 5: Targeted argmax — class 1 dominant
        //   W = [[0, 10, 0, 0],
        //        [0, 10, 0, 0],
        //        [0, 10, 0, 0],
        //        [0, 10, 0, 0]]
        //   x = [1, 1, 1, 1]
        //   y[0]=0, y[1]=40, y[2]=0, y[3]=0
        //   argmax = 1
        // ═══════════════════════════════════════════════════════════

        test_num = 5;
        test_errors = 0;
        $display("");
        $display("─── TEST %0d: Targeted Argmax (Class 1 Dominant) ───", test_num);

        do_reset();

        write_weight(0, 0, 8'd0);  write_weight(0, 1, 8'd10);
        write_weight(0, 2, 8'd0);  write_weight(0, 3, 8'd0);
        write_weight(1, 0, 8'd0);  write_weight(1, 1, 8'd10);
        write_weight(1, 2, 8'd0);  write_weight(1, 3, 8'd0);
        write_weight(2, 0, 8'd0);  write_weight(2, 1, 8'd10);
        write_weight(2, 2, 8'd0);  write_weight(2, 3, 8'd0);
        write_weight(3, 0, 8'd0);  write_weight(3, 1, 8'd10);
        write_weight(3, 2, 8'd0);  write_weight(3, 3, 8'd0);

        write_input(0, 8'd1);
        write_input(1, 8'd1);
        write_input(2, 8'd1);
        write_input(3, 8'd1);

        run_and_wait();

        check_scores(0, 40, 0, 0, 1);

        total_errors = total_errors + test_errors;

        // ═══════════════════════════════════════════════════════════
        // FINAL REPORT
        // ═══════════════════════════════════════════════════════════

        $display("");
        $display("================================================================");
        if (total_errors == 0)
            $display("  ALL %0d TESTS PASSED", test_num);
        else
            $display("  FAILED — %0d error(s) across %0d tests", total_errors, test_num);
        $display("================================================================");
        $display("");

        #20;
        $finish;
    end

endmodule