// output_reg.v — 4-element signed 32-bit output capture register
// Captures the systolic array's psum_out values on the 'capture' pulse.
//
// Capture interface: when 'capture' is high, latches all N psum values
// Read interface:    bulk output of all N captured scores

module output_reg #(
    parameter AW = 32,      // accumulator width
    parameter N  = 4        // number of output elements
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    capture,        // latch all outputs this cycle
    input  wire signed [AW-1:0]    data_in [0:N-1], // from systolic array psum_out
    output wire signed [AW-1:0]    data_out [0:N-1]  // captured scores
);

    reg signed [AW-1:0] mem [0:N-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1)
                mem[i] <= {AW{1'b0}};
        end else if (capture) begin
            for (i = 0; i < N; i = i + 1)
                mem[i] <= data_in[i];
        end
    end

    // Continuous bulk read
    genvar k;
    generate
        for (k = 0; k < N; k = k + 1) begin : out_assign
            assign data_out[k] = mem[k];
        end
    endgenerate

endmodule