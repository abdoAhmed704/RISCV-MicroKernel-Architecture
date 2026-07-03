module riscv_top_tb();

logic clk, reset_n; 
logic [31:0] result;
logic        irq_ack;   // HIGH for one cycle when core accepts an interrupt
localparam bit ENABLE_TRAP_TRACE = 1'b0;
localparam int MAX_SIM_CYCLES = 0; // 0 = run forever until the user stops simulation

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
    reset_n = 0;
    repeat(2) @(negedge clk);
    reset_n = 1;

    if (MAX_SIM_CYCLES > 0) begin
        repeat(MAX_SIM_CYCLES) @(negedge clk);
        $stop;
    end
end

// ================= HEADER =================
initial begin
    if (ENABLE_TRAP_TRACE) begin
        $display("\n================ PIPELINE DEBUG =================");
        $display("Cycle |      FETCH (PCF / InstrF)      |    DECODE (InstrD)   |                  EXECUTE (RD1/RD2/ALU/CTRL)                  |   MEMORY        |   WRITEBACK");
        $display("------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------");
    end
end

// ================= MAIN DEBUG =================
int cycle = 0;

always @(posedge clk) begin
    cycle++;

    if (ENABLE_TRAP_TRACE && (top_ins.csr_unit.take_trap || irq_ack)) begin
        $display("Cycle %3d | PC=%h | Mode=%b | mcause=%h | mepc=%h | scause=%h | sepc=%h | trap=%b | irq_ack=%b | RdW=%0d Res=%h",
            cycle,
            top_ins.new_fet.PCF,
            top_ins.csr_unit.priv_mode_q,
            top_ins.csr_unit.mcause_q,
            top_ins.csr_unit.mepc_q,
            top_ins.csr_unit.scause_q,
            top_ins.csr_unit.sepc_q,
            top_ins.csr_unit.take_trap,
            irq_ack,
            top_ins.RdW,
            result
        );
    end
end

endmodule
