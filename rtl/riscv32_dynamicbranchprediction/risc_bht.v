module bht_table (
    input  wire        clk,
    input  wire        rst_n,
    

    input  wire [31:0] fetch_pc,
    output wire        predict_taken,
    
    //(Execute Stage)
    input  wire        write_en,
    input  wire [31:0] exe_pc,
    input  wire [1:0]  write_counter,
    output wire [1:0]  exe_current_counter  
);

   
    reg [1:0] bht_mem [0:255];
    
    wire [7:0] fetch_index;
    wire [7:0] write_index;
    
    integer i;

    
    assign fetch_index = fetch_pc[9:2];
    assign write_index = exe_pc[9:2];
    
    
    assign predict_taken = bht_mem[fetch_index][1];

    assign exe_current_counter = bht_mem[write_index];

   
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            
            for (i = 0; i < 256; i = i + 1) begin
                bht_mem[i] <= 2'b01;
            end
        end else begin
            if (write_en) begin
                bht_mem[write_index] <= write_counter;
            end
        end
    end

endmodule

