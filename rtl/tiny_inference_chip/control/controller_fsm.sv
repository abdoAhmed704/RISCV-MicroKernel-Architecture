// controller_fsm.v — Linear Classifier Controller FSM
// Sequences the datapath: weight load → input setup → compute → capture → done
//
// States:
//   IDLE         — waiting for 'start' pulse
//   LOAD_WEIGHTS — asserts load_weight for 1 cycle (weights already in weight_reg)
//   COMPUTE      — waits N+N-1 cycles for systolic array pipeline to flush
//   CAPTURE      — asserts capture for 1 cycle to latch output scores
//   DONE         — asserts 'done' flag, returns to IDLE

module controller_fsm #(
    parameter N = 4         // systolic array dimension
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // begin classification
    output reg         load_weight,    // pulse: load weights into systolic PEs
    output reg         capture,        // pulse: latch output scores
    output reg         done            // flag: classification complete
);

    // State encoding
    localparam [2:0] S_IDLE         = 3'd0,
                     S_LOAD_WEIGHTS = 3'd1,
                     S_COMPUTE      = 3'd2,
                     S_CAPTURE      = 3'd3,
                     S_DONE         = 3'd4;

    reg [2:0] state, next_state;

    // Cycle counter for compute phase
    // Need N rows + (N-1) column propagation = 2N-1 cycles for full pipeline flush
    localparam COMPUTE_CYCLES = 2 * N - 1;
    reg [$clog2(COMPUTE_CYCLES+1)-1:0] cycle_cnt;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:         if (start)                       next_state = S_LOAD_WEIGHTS;
            S_LOAD_WEIGHTS:                                  next_state = S_COMPUTE;
            S_COMPUTE:      if (cycle_cnt == COMPUTE_CYCLES) next_state = S_CAPTURE;
            S_CAPTURE:                                       next_state = S_DONE;
            S_DONE:         if (start)                       next_state = S_LOAD_WEIGHTS;
            default:                                         next_state = S_IDLE;
        endcase
    end

    // Cycle counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_cnt <= 0;
        else if (state == S_COMPUTE)
            cycle_cnt <= cycle_cnt + 1;
        else
            cycle_cnt <= 0;
    end

    // Output logic
    always @(*) begin
        load_weight = (state == S_LOAD_WEIGHTS);
        capture     = (state == S_CAPTURE);
        done        = (state == S_DONE);
    end

endmodule
