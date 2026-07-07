// pe.sv — Systolic Array Processing Element (Weight-Stationary)
module pe #(parameter DW=8, AW=32)(
  input  wire              clk, rst_n,
  input  wire              load_weight,    // load weight this cycle
  input  wire signed [DW-1:0] weight_in,  // weight value
  input  wire signed [DW-1:0] act_in,     // activation from left
  input  wire signed [AW-1:0] psum_in,    // partial sum from above
  output reg  signed [DW-1:0] act_out,    // activation to right (registered)
  output reg  signed [AW-1:0] psum_out    // partial sum to below
);
  reg signed [DW-1:0] weight;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight   <= 0;
      act_out  <= 0;
      psum_out <= 0;
    end else begin
      if (load_weight) weight <= weight_in;  // one-time weight setup
      act_out  <= act_in;                    // pass activation right
      psum_out <= psum_in + ({{(AW-DW){act_in[DW-1]}}, act_in}
                           * {{(AW-DW){weight[DW-1]}}, weight});
    end
  end
endmodule