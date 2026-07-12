module riscv_top_tb();

logic clk, reset_n; 
logic [31:0] result;
logic        irq_ack;   // HIGH for one cycle when core accepts an interrupt
localparam bit ENABLE_TRAP_TRACE = 1'b0;
localparam bit ENABLE_BRANCH_TRACE = 1'b0;
localparam int MAX_SIM_CYCLES = 1200; // Default to 1200 cycles for self-checking tests

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
    if (reset_n) begin
        cycle++;

        // ── Success Condition ──
        if (top_ins.decode_stage_inst.regfile.registers[31] === 32'hFEEDDEED) begin
            $display("\n[ 1. Base ALU & Branching ]");
            $display("x01 (Base Operand x1)                     = 0x%h (Expected: 0x0000000a)", top_ins.decode_stage_inst.regfile.registers[1]);
            $display("x02 (Base Operand x2)                     = 0x%h (Expected: 0xfffffffb)", top_ins.decode_stage_inst.regfile.registers[2]);
            $display("When 10 + -5 to x03:");
            $display("x03 (add x3, x1, x2)                      = 0x%h (Expected: 0x00000005)", top_ins.decode_stage_inst.regfile.registers[3]);
            $display("When 10 - -5 to x04:");
            $display("x04 (sub x4, x1, x2)                      = 0x%h (Expected: 0x0000000f)", top_ins.decode_stage_inst.regfile.registers[4]);
            $display("When 10 & -5 to x05:");
            $display("x05 (and x5, x1, x2)                      = 0x%h (Expected: 0x0000000a)", top_ins.decode_stage_inst.regfile.registers[5]);
            $display("When 10 | -5 to x06:");
            $display("x06 (or x6, x1, x2)                       = 0x%h (Expected: 0xfffffffb)", top_ins.decode_stage_inst.regfile.registers[6]);

            $display("\n[ 2. Caches & Memory Consistency ]");
            $display("When load word from RAM[0x2000] to x21:");
            $display("x21 (lw x21, 0(x15))                      = 0x%h (Expected: 0x0000000a)", top_ins.decode_stage_inst.regfile.registers[21]);
            $display("When load half-word from RAM[0x2004] to x22:");
            $display("x22 (lh x22, 4(x15))                      = 0x%h (Expected: 0xfffffffb)", top_ins.decode_stage_inst.regfile.registers[22]);
            $display("When load byte from RAM[0x2008] to x23:");
            $display("x23 (lb x23, 8(x15))                      = 0x%h (Expected: 0x00000005)", top_ins.decode_stage_inst.regfile.registers[23]);

            $display("\n[ 3. CSR Instructions (Zicsr) ]");
            $display("When write 10 and read old mscratch to x26:");
            $display("x26 (csrrw x26, mscratch, x12)            = 0x%h (Expected: 0x00000000)", top_ins.decode_stage_inst.regfile.registers[26]);
            $display("When bit-set 4 and read old mscratch to x27:");
            $display("x27 (csrrs x27, mscratch, x13)            = 0x%h (Expected: 0x0000000a)", top_ins.decode_stage_inst.regfile.registers[27]);
            $display("When bit-clear 10 and read old mscratch to x28:");
            $display("x28 (csrrc x28, mscratch, x12)            = 0x%h (Expected: 0x0000000e)", top_ins.decode_stage_inst.regfile.registers[28]);
            $display("When read final mscratch value to x29:");
            $display("x29 (csrr x29, mscratch)                  = 0x%h (Expected: 0x00000004)", top_ins.decode_stage_inst.regfile.registers[29]);

            $display("\n[ 4. M-Extension (Multiplication & Division) ]");
            $display("When 10 * -5 to x13:");
            $display("x13 (mul x13, x1, x2)                     = 0x%h (Expected: 0xffffffce)", top_ins.decode_stage_inst.regfile.registers[13]);
            $display("When high-half signed 10 * -5 to x14:");
            $display("x14 (mulh x14, x1, x2)                    = 0x%h (Expected: 0xffffffff)", top_ins.decode_stage_inst.regfile.registers[14]);
            $display("When 10 / -5 to x16:");
            $display("x16 (div x16, x1, x2)                     = 0x%h (Expected: 0xfffffffe)", top_ins.decode_stage_inst.regfile.registers[16]);
            $display("When 10 %% -5 to x17:");
            $display("x17 (rem x17, x1, x2)                     = 0x%h (Expected: 0x00000000)", top_ins.decode_stage_inst.regfile.registers[17]);

            $display("\n[ 5. C-Extension (RVC) ]");
            $display("When load compressed immediate 15 to x10:");
            $display("x10 (c.li x10, 15)                        = 0x%h (Expected: 0x0000000f)", top_ins.decode_stage_inst.regfile.registers[10]);
            $display("When RVC add 10 to 10 (15 - 5 + 10) to x11:");
            $display("x11 (c.add x11, x15)                      = 0x%h (Expected: 0x00000014)", top_ins.decode_stage_inst.regfile.registers[11]);

            $display("\n[ 6. Branch Prediction & History ]");
            $display("When dynamic branch alternating finishes:");
            $display("x10 (Loop counter alt_done)               = 0x%h (Expected: 0x00000004)", top_ins.decode_stage_inst.regfile.registers[10]);
            $display("x11 (Odd/Even checker status)             = 0x%h (Expected: 0x00000001)", top_ins.decode_stage_inst.regfile.registers[11]);

            $display("\n[ 7. Tiny Inference Chip (Linear Classifier Unit) ]");
            $display("When read Custom-0 classification status done flag to x24:");
            $display("x24 (lc.read done)                        = 0x%h (Expected: 0x00000001)", top_ins.decode_stage_inst.regfile.registers[24]);
            $display("When read predicted argmax class to x25:");
            $display("x25 (lc.read class)                       = 0x%h (Expected: 0x00000000)", top_ins.decode_stage_inst.regfile.registers[25]);
            $display("When read computed Score[0] (10*2 + 4*3) to x18:");
            $display("x18 (lc.read Score[0])                    = 0x%h (Expected: 0x00000020)", top_ins.decode_stage_inst.regfile.registers[18]);
            $display("When read computed Score[1] (10*1 + 4*5) to x19:");
            $display("x19 (lc.read Score[1])                    = 0x%h (Expected: 0x0000001e)", top_ins.decode_stage_inst.regfile.registers[19]);

            $display("\n[ Status ]");
            $display("x31 (Test Success Code)                   = 0x%h (Expected: 0xfeeddeed)", top_ins.decode_stage_inst.regfile.registers[31]);
            $display("Current PCF                               = 0x%h", top_ins.new_fet.PCF_out);
            $display("Current PCE                               = 0x%h", top_ins.PCE);
            $display("CSR mcause                                = 0x%h", top_ins.csr_unit.mcause_q);
            $display("CSR mepc                                  = 0x%h", top_ins.csr_unit.mepc_q);
            $display("===============================================\n");
            $display(">>> SUCCESS: ALL RV32I PROCESSOR INSTRUCTIONS PASSED! <<<\n");
            $stop;
        end

        // ── Failure Condition ──
        if ((top_ins.decode_stage_inst.regfile.registers[31] & 32'hFFFF0000) === 32'hDEAD0000) begin
            $display("\n================ TEST FAILURE =================");
            $display("Failing Check Code: 0x%h", top_ins.decode_stage_inst.regfile.registers[31]);
            $display("Failed Check Index: %0d", top_ins.decode_stage_inst.regfile.registers[31] & 32'h0000FFFF);
            $display("Cycles run         : %0d", cycle);
            $display("===============================================\n");
            $display(">>> FAILURE: PROCESSOR INSTRUCTION VERIFICATION FAILED! <<<\n");
            $stop;
        end

        // ── Timeout Condition ──
        if (MAX_SIM_CYCLES > 0 && cycle >= MAX_SIM_CYCLES) begin
            $display("\n================ SIMULATION TIMEOUT =================");
            $display("Timeout at cycle count: %0d", cycle);
            $display("x31 (Result Register) = 0x%h", top_ins.decode_stage_inst.regfile.registers[31]);
            $display("=====================================================\n");
            $display(">>> FAILURE: TIMEOUT EXCEEDED! <<<\n");
            $stop;
        end
    end

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
