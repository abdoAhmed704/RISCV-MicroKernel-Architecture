module btb_table (
    input  wire        clk,
    input  wire        rst_n,
    
    // (Fetch Stage)
    input  wire [31:0] fetch_pc,
    output wire [31:0] predicted_target_pc,
    
    // (Execute Stage)
    input  wire        write_en,
    input  wire [31:0] exe_pc,
    input  wire [31:0] actual_target_pc 
);

    reg [31:0] btb_mem [0:255];
    reg [21:0] btb_tags [0:255];
    reg        btb_valid [0:255];
    
    wire [7:0] fetch_index;
    wire [7:0] write_index;
    wire       btb_hit;
    
    integer i;

    // Indexing using PC[9:2]
    assign fetch_index = fetch_pc[9:2];
    assign write_index = exe_pc[9:2];
    
    // Tag matches PC[31:10] and entry must be valid
    assign btb_hit = btb_valid[fetch_index] && (btb_tags[fetch_index] == fetch_pc[31:10]);
    assign predicted_target_pc = btb_hit ? btb_mem[fetch_index] : 32'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 256; i = i + 1) begin
                btb_mem[i]   <= 32'b0;
                btb_tags[i]  <= 22'b0;
                btb_valid[i] <= 1'b0;
            end
        end else begin
            // Execute write
            if (write_en) begin
                btb_mem[write_index]   <= actual_target_pc;
                btb_tags[write_index]  <= exe_pc[31:10];
                btb_valid[write_index] <= 1'b1;
            end
        end
    end

endmodule
