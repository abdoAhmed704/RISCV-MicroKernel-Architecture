// linear_classifier.sv — Top-level Linear Classifier Module
// Computes y = x · W using a 4×4 weight-stationary systolic array,
// captures output scores, and determines the predicted class (argmax).
//
// Dataflow:
//   1. External controller writes weights into weight_reg (element by element)
//   2. External controller writes input features into input_reg (element by element)
//   3. 'start' pulse triggers the FSM:
//        - Loads weights from weight_reg into systolic PEs
//        - Systolic array computes y[j] = Σ_i x[i] * W[i][j]
//        - Output register captures the 4 class scores
//        - Argmax logic selects the predicted class
//   4. 'done' goes high — scores[] and predicted_class are valid

module linear_classifier #(
    parameter DW = 8,       // data width (INT8 signed)
    parameter AW = 32,      // accumulator width
    parameter N  = 4        // array dimension
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Weight write interface
    input  wire                    wr_weight,
    input  wire [1:0]              wr_w_row,
    input  wire [1:0]              wr_w_col,
    input  wire signed [DW-1:0]    wr_w_data,

    // Input write interface
    input  wire                    wr_input,
    input  wire [1:0]              wr_i_addr,
    input  wire signed [DW-1:0]    wr_i_data,

    // Control
    input  wire                    start,

    // Output
    output wire signed [AW-1:0]    scores [0:N-1],
    output wire [1:0]              predicted_class,
    output wire                    done
);

    // ─── Internal wires ───────────────────────────────────────────

    wire signed [DW-1:0] w_matrix [0:N-1][0:N-1];  // weight_reg → systolic
    wire signed [DW-1:0] x_vector [0:N-1];          // input_reg  → systolic
    wire signed [AW-1:0] psum_raw [0:N-1];          // systolic   → output_reg
    wire signed [AW-1:0] scores_captured [0:N-1];   // output_reg → argmax

    wire load_weight;   // FSM → systolic
    wire capture;       // FSM → output_reg

    // ─── Weight Register File ─────────────────────────────────────

    weight_reg #(.DW(DW), .N(N)) u_weight_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_weight),
        .wr_row   (wr_w_row),
        .wr_col   (wr_w_col),
        .wr_data  (wr_w_data),
        .data_out (w_matrix)
    );

    // ─── Input Register File ──────────────────────────────────────

    input_reg #(.DW(DW), .N(N)) u_input_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_input),
        .wr_addr  (wr_i_addr),
        .wr_data  (wr_i_data),
        .data_out (x_vector)
    );

    // ─── 4×4 Weight-Stationary Systolic Array ─────────────────────

    systolic_4x4 #(.DW(DW), .AW(AW), .N(N)) u_systolic (
        .clk         (clk),
        .rst_n       (rst_n),
        .load_weight (load_weight),
        .weights     (w_matrix),
        .act_in      (x_vector),
        .psum_out    (psum_raw)
    );

    // ─── Output Capture Register ──────────────────────────────────

    output_reg #(.AW(AW), .N(N)) u_output_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .capture  (capture),
        .data_in  (psum_raw),
        .data_out (scores_captured)
    );

    // ─── Controller FSM ──────────────────────────────────────────

    controller_fsm #(.N(N)) u_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .load_weight (load_weight),
        .capture     (capture),
        .done        (done)
    );

    // ─── Output Assignments ──────────────────────────────────────

    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : score_assign
            assign scores[k] = scores_captured[k];
        end
    endgenerate

    // ─── Argmax — Predicted Class ────────────────────────────────
    // Purely combinational: finds the index of the maximum score.

    reg [1:0]             arg_max;
    reg signed [AW-1:0]   val_max;

    integer idx;

    always @(*) begin
        arg_max = 2'd0;
        val_max = scores_captured[0];
        for (idx = 1; idx < N; idx = idx + 1) begin
            if (scores_captured[idx] > val_max) begin
                val_max = scores_captured[idx];
                arg_max = idx[1:0];
            end
        end
    end

    assign predicted_class = arg_max;

endmodule
