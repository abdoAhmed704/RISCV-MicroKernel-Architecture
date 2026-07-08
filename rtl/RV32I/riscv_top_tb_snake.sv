module riscv_top_tb_snake();

logic clk, reset_n; 
logic [31:0] result;
logic        irq_ack;

// instantiate DUT
riscv_top_pipeline top_ins (
    .clk(clk),
    .rst_n(reset_n),
    .mexternal(1'b0),
    .sexternal(1'b0),
    .result(result),
    .irq_ack(irq_ack)
);

// ================= CLOCK =================
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// ================= INIT =================
initial begin
    $display("Starting RISC-V Snake Game Simulation...");
    $display("Use the python keyboard feeder (play_game.py) to control the snake.");
    $display("Simulation running... Press Ctrl+C in this terminal to stop.");
    reset_n = 0;
    repeat(2) @(negedge clk);
    reset_n = 1;
end

endmodule
