module riscv_top_tb();

logic clk, reset_n; 
logic [31:0] result;
logic        irq_ack;   // HIGH for one cycle when core accepts an interrupt
localparam bit ENABLE_TRAP_TRACE = 1'b0;
localparam bit ENABLE_BRANCH_TRACE = 1'b0;
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

    // Run for 1200 cycles to complete the test suite and self-checks
    repeat(1200) @(negedge clk);
    
    $display("\n================ TEST RESULTS =================");
    $display("x00 = 0x%h (Expected: 0x00000000)", top_ins.decode_stage_inst.regfile.registers[0]);
    $display("x01 = 0x%h (Expected: 0x11111111)", top_ins.decode_stage_inst.regfile.registers[1]);
    $display("x02 = 0x%h (Expected: 0x22222222)", top_ins.decode_stage_inst.regfile.registers[2]);
    $display("x03 = 0x%h (Expected: 0x00000005)", top_ins.decode_stage_inst.regfile.registers[3]);
    $display("x04 = 0x%h (Expected: 0x0000000f)", top_ins.decode_stage_inst.regfile.registers[4]);
    $display("x05 = 0x%h (Expected: 0x0000000a)", top_ins.decode_stage_inst.regfile.registers[5]);
    $display("x06 = 0x%h (Expected: 0xfffffffb)", top_ins.decode_stage_inst.regfile.registers[6]);
    $display("x07 = 0x%h (Expected: 0x00000140)", top_ins.decode_stage_inst.regfile.registers[7]);
    $display("x08 = 0x%h (Expected: 0xffffffff)", top_ins.decode_stage_inst.regfile.registers[8]);
    $display("x09 = 0x%h (Expected: 0x0000000c)", top_ins.decode_stage_inst.regfile.registers[9]);
    $display("x10 = 0x%h (Expected: 0x00000003)", top_ins.decode_stage_inst.regfile.registers[10]);
    $display("x11 = 0x%h (Expected: 0x00000064)", top_ins.decode_stage_inst.regfile.registers[11]);
    $display("x12 = 0x%h (Expected: 0x0000006e)", top_ins.decode_stage_inst.regfile.registers[12]);
    $display("x13 = 0x%h (Expected: 0x00000078)", top_ins.decode_stage_inst.regfile.registers[13]);
    $display("x14 = 0x%h (Expected: 0x00000082)", top_ins.decode_stage_inst.regfile.registers[14]);
    $display("x15 = 0x%h (Expected: 0xdeadb7ff)", top_ins.decode_stage_inst.regfile.registers[15]);
    $display("x16 = 0x%h (Expected: 0x0000007f)", top_ins.decode_stage_inst.regfile.registers[16]);
    $display("x17 = 0x%h (Expected: 0x0000007f)", top_ins.decode_stage_inst.regfile.registers[17]);
    $display("x18 = 0x%h (Expected: 0x00008765)", top_ins.decode_stage_inst.regfile.registers[18]);
    $display("x19 = 0x%h (Expected: 0x00008765)", top_ins.decode_stage_inst.regfile.registers[19]);
    $display("x20 = 0x%h (Expected: 0x0000007f)", top_ins.decode_stage_inst.regfile.registers[20]);
    $display("x21 = 0x%h (Expected: 0x0000000c)", top_ins.decode_stage_inst.regfile.registers[21]);
    $display("x22 = 0x%h (Expected: 0x0000000c)", top_ins.decode_stage_inst.regfile.registers[22]);
    $display("x23 = 0x%h (Expected: 0x00000006)", top_ins.decode_stage_inst.regfile.registers[23]);
    $display("x24 = 0x%h (Expected: 0x00000006)", top_ins.decode_stage_inst.regfile.registers[24]);
    $display("x25 = 0x%h (Expected: 0x0000010e)", top_ins.decode_stage_inst.regfile.registers[25]);
    $display("x26 = 0x%h (Expected: 0x0badcafe)", top_ins.decode_stage_inst.regfile.registers[26]);
    $display("x27 = 0x%h (Expected: 0x13579bdf)", top_ins.decode_stage_inst.regfile.registers[27]);
    $display("x28 = 0x%h (Expected: 0x00000001)", top_ins.decode_stage_inst.regfile.registers[28]);
    $display("x29 = 0x%h (Expected: 0x00000005)", top_ins.decode_stage_inst.regfile.registers[29]);
    $display("x30 = 0x%h (Expected: 0x00000082)", top_ins.decode_stage_inst.regfile.registers[30]);
    $display("x31 = 0x%h (Expected: 0xfeeddeed)", top_ins.decode_stage_inst.regfile.registers[31]);
    $display("Current PCF      = 0x%h", top_ins.new_fet.PCF_out);
    $display("Current PCE      = 0x%h", top_ins.PCE);
    $display("CSR mcause       = 0x%h", top_ins.csr_unit.mcause_q);
    $display("CSR mepc         = 0x%h", top_ins.csr_unit.mepc_q);
    $display("CSR mtval        = 0x%h", top_ins.csr_unit.mtval_q);
    $display("StallF           = %b", top_ins.hu.StallF);
    $display("StallD           = %b", top_ins.hu.StallD);
    $display("FlushD           = %b", top_ins.hu.FlushD);
    $display("FlushE           = %b", top_ins.hu.FlushE);
    $display("PCSrcE           = %b", top_ins.PCSrcE);
    $display("mispredictionE   = %b", top_ins.mispredictionE);
    $display("predict_takenE   = %b", top_ins.predict_takenE);
    $display("target_taken     = %b", top_ins.target_taken);
    $display("===============================================\n");
    
    if (top_ins.decode_stage_inst.regfile.registers[31] === 32'hFEEDDEED) begin
        $display(">>> SUCCESS: ALL RV32I PROCESSOR INSTRUCTIONS PASSED! <<<\n");
    end else begin
        $display(">>> FAILURE: PROCESSOR INSTRUCTION VERIFICATION FAILED! <<<\n");
    end
    
    $stop;
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

    if (ENABLE_BRANCH_TRACE && cycle < 120 &&
        (top_ins.new_fet.PCF >= 32'h00000070 && top_ins.new_fet.PCF <= 32'h00000080)) begin
        $display("BR cycle=%0d PCF=%h instrD=%h PCD=%h PCE=%h a1=%0d a2=%0d predF=%b predD=%b predE=%b pcsrc=%b tgt=%b mis=%b corr=%h",
            cycle,
            top_ins.new_fet.PCF,
            top_ins.instrD,
            top_ins.PCD,
            top_ins.PCE,
            top_ins.decode_stage_inst.regfile.registers[11],
            top_ins.decode_stage_inst.regfile.registers[12],
            top_ins.predict_takenF,
            top_ins.predict_takenD,
            top_ins.predict_takenE,
            top_ins.PCSrcE,
            top_ins.target_taken,
            top_ins.mispredictionE,
            top_ins.bp_corrected_pc
        );
    end
end

endmodule
