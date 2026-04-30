module top_tb();

logic clk, reset_n; 
logic [31:0] result;

// instantiate DUT
top_pipeline top_ins (.clk(clk), .rst_n(reset_n), .result(result));

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

    repeat(50) @(negedge clk);
    $stop;
end

// ================= HEADER =================
initial begin
    $display("\n================ PIPELINE DEBUG =================");
    $display("Cycle |      FETCH (PCF / InstrF)      |    DECODE (InstrD)   |                  EXECUTE (RD1/RD2/ALU/CTRL)                  |   MEMORY        |   WRITEBACK");
    $display("------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------");
end

// ================= MAIN DEBUG =================
int cycle = 0;

always @(posedge clk) begin
    cycle++;

    $display(" (PCSrcE=%b, target_taken=%b, Branch=%b)  ====  %3d   |       %h / %h        |     %h    |         RD1=%h RD2=%h ALU=%h S=%h B=%h J=%h      | %h W=%b | Rd=%0d W=%b Res=%h", //   funct7_5E=%b | funct_7_5=%b | funct3M=%b
    
    // ===== FETCH =====
    top_ins.PCSrcE,
    top_ins.target_taken,
    top_ins.BranchE,
    cycle,
    top_ins.new_fet.PCF,
    top_ins.new_fet.instrF,

    // ===== DECODE =====
    top_ins.instrD,

    // ===== EXECUTE =====
    top_ins.RD1E,
    top_ins.RD2E,
    top_ins.excute_kda_kda.ALUResultE,
    top_ins.ALUSrcE,
    top_ins.BranchE,
    top_ins.jumpE,

    // ===== MEMORY =====
    top_ins.ALUResultM,
    top_ins.MemWriteM,

    // ===== WRITEBACK =====
    top_ins.RdW,
    top_ins.RegWriteW,
    result,
    // top_ins.funct7_5E,
    // top_ins.decode_keda_keda.funct7_5,
    // top_ins.data_mem.funct3M
    );
end

endmodule