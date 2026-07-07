// weight_reg.v — 4×4 signed INT8 weight matrix register file
// Stores the weight matrix that feeds the systolic array's weights port.
//
// Write interface: one element at a time via wr_en / wr_row / wr_col / wr_data
// Read interface:  bulk 2D output of the full 4×4 matrix (directly to systolic array)

module weight_reg #(
    parameter DW = 8,       // data width (INT8)
    parameter N  = 4        // matrix dimension
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    wr_en,          // write enable
    input  wire [1:0]              wr_row,         // row address
    input  wire [1:0]              wr_col,         // column address
    input  wire signed [DW-1:0]    wr_data,        // data to write
    output wire signed [DW-1:0]    data_out [0:N-1][0:N-1] // bulk read to systolic array
);

    reg signed [DW-1:0] mem [0:N-1][0:N-1];

    integer i, j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1)
                    mem[i][j] <= {DW{1'b0}};
        end else if (wr_en) begin
            mem[wr_row][wr_col] <= wr_data;
        end
    end

    // Continuous bulk 2D read
    genvar r, c;
    generate
        for (r = 0; r < N; r = r + 1) begin : row_out
            for (c = 0; c < N; c = c + 1) begin : col_out
                assign data_out[r][c] = mem[r][c];
            end
        end
    endgenerate

endmodule