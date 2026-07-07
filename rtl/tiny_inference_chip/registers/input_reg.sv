// input_reg.v — 4-element signed INT8 input activation register file
// Stores the feature vector that feeds the systolic array's act_in port.
//
// Write interface: one element at a time via wr_en / wr_addr / wr_data
// Read interface:  bulk output of all 4 elements (directly to systolic array)

module input_reg #(
    parameter DW = 8,       // data width (INT8)
    parameter N  = 4        // number of elements
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    wr_en,          // write enable
    input  wire [1:0]              wr_addr,        // which element to write
    input  wire signed [DW-1:0]    wr_data,        // data to write
    output wire signed [DW-1:0]    data_out [0:N-1] // bulk read to systolic array
);

    reg signed [DW-1:0] mem [0:N-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1)
                mem[i] <= {DW{1'b0}};
        end else if (wr_en) begin
            mem[wr_addr] <= wr_data;
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