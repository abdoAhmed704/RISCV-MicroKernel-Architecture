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
    
    wire [7:0] fetch_index;
    wire [7:0] write_index;
    
    integer i;

    // ??? ??? Indexing  ???? ????????
    assign fetch_index = fetch_pc[9:2];
    assign write_index = exe_pc[9:2];
    
   
    assign predicted_target_pc = btb_mem[fetch_index];

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            
            for (i = 0; i < 256; i = i + 1) begin
                btb_mem[i] <= 32'b0;
            end
        end else begin
            // Execute
            if (write_en) begin
                btb_mem[write_index] <= actual_target_pc;
            end
        end
    end

endmodule
