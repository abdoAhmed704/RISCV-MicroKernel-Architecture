
`timescale 1ns/1ps

module tb_riscv_core_compressed_decoder;

    // ----------------------------------------------------------------
    // DUT instances: one RV32C, one RV64C
    // ----------------------------------------------------------------
    logic [31:0] instr_in;

    logic [31:0] instr_out_32, instr_out_64;
    logic        is_comp_32,   is_comp_64;
    logic        illegal_32,   illegal_64;

    riscv_core_compressed_decoder #(.XLEN(32)) dut32 (
        .i_compressed_decoder_instr        (instr_in),
        .o_compressed_decoder_instr        (instr_out_32),
        .o_compressed_decoder_is_compressed(is_comp_32),
        .o_compressed_decoder_illegal_instr(illegal_32)
    );

    riscv_core_compressed_decoder #(.XLEN(64)) dut64 (
        .i_compressed_decoder_instr        (instr_in),
        .o_compressed_decoder_instr        (instr_out_64),
        .o_compressed_decoder_is_compressed(is_comp_64),
        .o_compressed_decoder_illegal_instr(illegal_64)
    );

    // ----------------------------------------------------------------
    // Golden reference model (mirrors the RTL bit-for-bit)
    // ----------------------------------------------------------------
    task automatic golden_decode
        (input  logic [15:0] c,
         input  int          xlen,
         output logic [31:0] exp_instr,
         output logic        exp_is_comp,
         output logic        exp_illegal);

        logic [31:0] o;
        logic        comp, ill;
        begin
            comp = 1'b1;
            ill  = 1'b0;
            o    = {16'b0, c};

            case (c[1:0])
                2'b00 : begin // Q0
                    case (c[15:13])
                        3'b000 : begin // C_ADDI4SPN
                            o = {2'b00, c[10:7], c[12:11], c[5], c[6],
                                 2'b00, 5'h02, 3'b000, 2'b01, c[4:2], 7'b0010011};
                            if (c[12:5] == 8'b0) ill = 1'b1;
                        end
                        default: ill = 1'b1;
                    endcase
                end

                2'b01 : begin // Q1
                    case (c[15:13])
                        3'b000 : begin // C_ADDI_NOP
                            o = {{6{c[12]}}, c[12], c[6:2], c[11:7], 3'b0, c[11:7], 7'b0010011};
                        end
                        3'b010 : begin // C_LI
                            o = {{6{c[12]}}, c[12], c[6:2], 5'b0, 3'b0, c[11:7], 7'b0010011};
                        end
                        3'b011 : begin // C_ADDI16SP_LUI
                            if (c[11:7] == 5'h02) begin
                                o = {{3{c[12]}}, c[4:3], c[5], c[2], c[6],
                                     4'b0, 5'h02, 3'b0, 5'h02, 7'b0010011};
                            end else begin
                                o = {{14{c[12]}}, c[12], c[6:2], c[11:7], 7'b0110111};
                                if (c[12] == 1'b0 && c[6:2] == 5'b0) ill = 1'b1;
                            end
                        end
                        3'b100 : begin // C_ARTH_LOGIC
                            case (c[11:10])
                                2'b00 : begin // SRLI
                                    if (xlen == 32 && c[12] == 1'b1) ill = 1'b1;
                                    else o = {6'b000000, c[12], c[6:2], 2'b01, c[9:7],
                                              3'b101, 2'b01, c[9:7], 7'b0010011};
                                end
                                2'b01 : begin // SRAI
                                    if (xlen == 32 && c[12] == 1'b1) ill = 1'b1;
                                    else o = {6'b010000, c[12], c[6:2], 2'b01, c[9:7],
                                              3'b101, 2'b01, c[9:7], 7'b0010011};
                                end
                                2'b10 : begin // ANDI
                                    o = {{6{c[12]}}, c[12], c[6:2], 2'b01, c[9:7],
                                         3'b111, 2'b01, c[9:7], 7'b0010011};
                                end
                                2'b11 : begin // ALU / SUBW-ADDW
                                    if (c[12] == 1'b0) begin
                                        case (c[6:5])
                                            2'b00 : o = {2'b01, 5'b0, 2'b01, c[4:2], 2'b01, c[9:7],
                                                         3'b0, 2'b01, c[9:7], 7'b0110011}; // SUB
                                            2'b01 : o = {7'b0, 2'b01, c[4:2], 2'b01, c[9:7],
                                                         3'b100, 2'b01, c[9:7], 7'b0110011}; // XOR
                                            2'b10 : o = {7'b0, 2'b01, c[4:2], 2'b01, c[9:7],
                                                         3'b110, 2'b01, c[9:7], 7'b0110011}; // OR
                                            2'b11 : o = {7'b0, 2'b01, c[4:2], 2'b01, c[9:7],
                                                         3'b111, 2'b01, c[9:7], 7'b0110011}; // AND
                                        endcase
                                    end else begin
                                        if (xlen == 64) begin
                                            case (c[6:5])
                                                2'b00 : o = {2'b01, 5'b0, 2'b01, c[4:2], 2'b01, c[9:7],
                                                             3'b0, 2'b01, c[9:7], 7'b0111011}; // SUBW
                                                2'b01 : o = {7'b0, 2'b01, c[4:2], 2'b01, c[9:7],
                                                             3'b0, 2'b01, c[9:7], 7'b0111011}; // ADDW
                                                default: ill = 1'b1;
                                            endcase
                                        end else begin
                                            ill = 1'b1; // reserved on RV32C
                                        end
                                    end
                                end
                            endcase
                        end
                        default: ill = 1'b1; // C.J / C.BEQZ / C.BNEZ - out of scope
                    endcase
                end

                2'b10 : begin // Q2
                    case (c[15:13])
                        3'b000 : begin // C_SLLI
                            if (xlen == 32 && c[12] == 1'b1) ill = 1'b1;
                            else o = {6'b0, c[12], c[6:2], c[11:7], 3'b001, c[11:7], 7'b0010011};
                        end
                        3'b100 : begin // C_MV_ADD_EBREAK
                            if (c[12] == 1'b0) begin
                                if (c[6:2] == 5'b0) begin
                                    ill = 1'b1; // would be C.JR, out of scope
                                end else begin
                                    o = {7'b0, c[6:2], 5'b0, 3'b0, c[11:7], 7'b0110011}; // MV
                                    if (c[11:7] == 5'b0) ill = 1'b1;
                                end
                            end else begin
                                if (c[11:2] == 10'b0) begin
                                    o = 32'h00100073; // EBREAK
                                end else if (c[11:7] != 5'b0 && c[6:2] == 5'b0) begin
                                    ill = 1'b1; // would be C.JALR, out of scope
                                end else if (c[11:2] != 10'b0) begin
                                    o = {7'b0, c[6:2], c[11:7], 3'b0, c[11:7], 7'b0110011}; // ADD
                                end else begin
                                    ill = 1'b1;
                                end
                            end
                        end
                        default: ill = 1'b1;
                    endcase
                end

                default: comp = 1'b0; // 2'b11 : uncompressed
            endcase

            if (ill) o = {16'b0, c};

            exp_instr   = o;
            exp_is_comp = comp;
            exp_illegal = ill;
        end
    endtask

    // ----------------------------------------------------------------
    // Scoreboard bookkeeping
    // ----------------------------------------------------------------
    int total_checks  = 0;
    int failed_checks = 0;

    task automatic check_one(input int xlen, input string name, input logic [15:0] c);
        logic [31:0] exp_instr, dut_instr;
        logic        exp_comp,  dut_comp;
        logic        exp_ill,   dut_ill;
        begin
            golden_decode(c, xlen, exp_instr, exp_comp, exp_ill);

            instr_in = {16'b0, c};
            #1; // settle the combinational DUTs

            if (xlen == 32) begin
                dut_instr = instr_out_32;
                dut_comp  = is_comp_32;
                dut_ill   = illegal_32;
            end else begin
                dut_instr = instr_out_64;
                dut_comp  = is_comp_64;
                dut_ill   = illegal_64;
            end

            total_checks++;
            if (dut_instr !== exp_instr || dut_comp !== exp_comp || dut_ill !== exp_ill) begin
                failed_checks++;
                $display("FAIL [XLEN=%0d] %-28s c=0x%04h : DUT(instr=0x%08h comp=%0b ill=%0b)  EXP(instr=0x%08h comp=%0b ill=%0b)",
                          xlen, name, c, dut_instr, dut_comp, dut_ill, exp_instr, exp_comp, exp_ill);
            end else begin
                $display("PASS [XLEN=%0d] %-28s c=0x%04h : instr=0x%08h comp=%0b ill=%0b",
                          xlen, name, c, dut_instr, dut_comp, dut_ill);
            end
        end
    endtask

    // Run a directed vector on both XLEN=32 and XLEN=64 instances
    task automatic check_both(input string name, input logic [15:0] c);
        begin
            check_one(32, name, c);
            check_one(64, name, c);
        end
    endtask

    // ----------------------------------------------------------------
    // Stimulus: directed vectors covering every branch
    // ----------------------------------------------------------------
    initial begin
        $display("================================================================");
        $display(" Starting testbench for riscv_core_compressed_decoder_28_5");
        $display("================================================================");

        // ---------------- Q0 : quadrant 00 -------------------------
        // C.ADDI4SPN legal (nzuimm != 0): funct3=000, imm bits != 0, rd'=x9
        check_both("C.ADDI4SPN legal",
                    {3'b000, 8'b00100001, 1'b1, 1'b0, 3'b001, 2'b00});
        // C.ADDI4SPN illegal: all-zero immediate field [12:5]
        check_both("C.ADDI4SPN illegal(zero)",
                    {3'b000, 8'b00000000, 1'b0, 1'b0, 3'b010, 2'b00});
        // Q0 unknown funct3 -> illegal
        check_both("Q0 unknown funct3",
                    {3'b001, 11'b0, 2'b00});

        // ---------------- Q1 : quadrant 01 --------------------------
        // C.ADDI / C.NOP : rd=0 (NOP)
        check_both("C.NOP (rd=0)",
                    {1'b0, 2'b00, 5'b00000, 5'b00000, 2'b01});
        // C.ADDI : rd != 0
        check_both("C.ADDI (rd!=0)",
                    {1'b0, 2'b01, 5'b00101, 5'b01010, 2'b01});

        // C.LI
        check_both("C.LI",
                    {1'b1, 2'b10, 5'b10101, 5'b01011, 2'b01});

        // C.ADDI16SP : rd==2
        check_both("C.ADDI16SP",
                    {1'b0, 2'b11, 5'h02, 5'b01001, 2'b01});
        // C.LUI : rd != 2, nzimm != 0
        check_both("C.LUI (rd!=0, nzimm!=0)",
                    {1'b1, 2'b11, 5'b01111, 5'b10101, 2'b01});
        // C.LUI : rd == 0 (HINT case, must still expand, not pass through)
        check_both("C.LUI (rd=0 HINT)",
                    {1'b1, 2'b11, 5'b00000, 5'b10101, 2'b01});
        // C.LUI : nzimm == 0 -> illegal (reserved)
        check_both("C.LUI illegal(nzimm=0)",
                    {1'b0, 2'b11, 5'b01111, 5'b00000, 2'b01});

        // C.SRLI : RV32 legal (shamt[5]=0)
        check_one(32, "C.SRLI RV32 legal",
                    {1'b0, 2'b00, 5'b00101, 5'b01001, 2'b01});
        // C.SRLI : RV32 illegal (shamt[5]=1)
        check_one(32, "C.SRLI RV32 illegal(shamt5)",
                    {1'b1, 2'b00, 5'b00101, 5'b01001, 2'b01});
        // C.SRLI : RV64 legal with shamt[5]=1
        check_one(64, "C.SRLI RV64 legal(shamt5)",
                    {1'b1, 2'b00, 5'b00101, 5'b01001, 2'b01});

        // C.SRAI : RV32 legal (shamt[5]=0)
        check_one(32, "C.SRAI RV32 legal",
                    {1'b0, 2'b01, 5'b00101, 5'b01001, 2'b01});
        // C.SRAI : RV32 illegal (shamt[5]=1)
        check_one(32, "C.SRAI RV32 illegal(shamt5)",
                    {1'b1, 2'b01, 5'b00101, 5'b01001, 2'b01});
        // C.SRAI : RV64 legal with shamt[5]=1
        check_one(64, "C.SRAI RV64 legal(shamt5)",
                    {1'b1, 2'b01, 5'b00101, 5'b01001, 2'b01});

        // C.ANDI
        check_both("C.ANDI",
                    {1'b1, 2'b10, 5'b01010, 5'b01101, 2'b01});

        // C.SUB / C.XOR / C.OR / C.AND  (bit12=0, [11:10]=11)
        check_both("C.SUB",
                    {1'b0, 2'b11, 5'b01000, {2'b00, 3'b010}, 2'b01});
        check_both("C.XOR",
                    {1'b0, 2'b11, 5'b01000, {2'b01, 3'b011}, 2'b01});
        check_both("C.OR",
                    {1'b0, 2'b11, 5'b01000, {2'b10, 3'b011}, 2'b01});
        check_both("C.AND",
                    {1'b0, 2'b11, 5'b01000, {2'b11, 3'b011}, 2'b01});

        // C.SUBW / C.ADDW : RV64 only legal, RV32 reserved-illegal
        check_one(64, "C.SUBW RV64 legal",
                    {1'b1, 2'b11, 5'b01000, {2'b00, 3'b010}, 2'b01});
        check_one(64, "C.ADDW RV64 legal",
                    {1'b1, 2'b11, 5'b01000, {2'b01, 3'b011}, 2'b01});
        check_one(64, "C.SUBW/ADDW RV64 unknown",
                    {1'b1, 2'b11, 5'b01000, {2'b10, 3'b011}, 2'b01});
        check_one(32, "C.SUBW/ADDW RV32 reserved",
                    {1'b1, 2'b11, 5'b01000, {2'b00, 3'b010}, 2'b01});

        // Q1 unknown funct3 (C.J/C.BEQZ/C.BNEZ out of scope) -> illegal
        check_both("Q1 unknown funct3(C.J)",
                    {3'b101, 11'b0, 2'b01});
        check_both("Q1 unknown funct3(C.BEQZ)",
                    {3'b110, 11'b0, 2'b01});
        check_both("Q1 unknown funct3(C.BNEZ)",
                    {3'b111, 11'b0, 2'b01});

        // ---------------- Q2 : quadrant 10 --------------------------
        // C.SLLI : RV32 legal (shamt[5]=0)
        check_one(32, "C.SLLI RV32 legal",
                    {1'b0, 2'b00, 5'b00101, 5'b01001, 2'b10});
        // C.SLLI : RV32 illegal (shamt[5]=1)
        check_one(32, "C.SLLI RV32 illegal(shamt5)",
                    {1'b1, 2'b00, 5'b00101, 5'b01001, 2'b10});
        // C.SLLI : RV64 legal with shamt[5]=1
        check_one(64, "C.SLLI RV64 legal(shamt5)",
                    {1'b1, 2'b00, 5'b00101, 5'b01001, 2'b10});

        // C.MV/ADD/EBREAK group, bit12=0:
        //   rs2==0 -> would be C.JR (out of scope) -> illegal
        check_both("would-be C.JR (illegal)",
                    {1'b0, 2'b00, 5'b01001, 5'b00000, 2'b10});
        //   rs2!=0, rd!=0 -> C.MV
        check_both("C.MV",
                    {1'b0, 2'b00, 5'b01001, 5'b00101, 2'b10});
        //   rs2!=0, rd==0 -> illegal (HINT, flagged illegal here)
        check_both("C.MV illegal(rd=0)",
                    {1'b0, 2'b00, 5'b00000, 5'b00101, 2'b10});

        // bit12=1:
        //   [11:2] all zero -> C.EBREAK
        check_both("C.EBREAK",
                    {1'b1, 2'b00, 5'b00000, 5'b00000, 2'b10});
        //   rd!=0, rs2==0 -> would be C.JALR (out of scope) -> illegal
        check_both("would-be C.JALR (illegal)",
                    {1'b1, 2'b00, 5'b01001, 5'b00000, 2'b10});
        //   [11:2]!=0 (rd!=0,rs2!=0) -> C.ADD
        check_both("C.ADD",
                    {1'b1, 2'b00, 5'b01001, 5'b00101, 2'b10});
        //   [11:2]!=0 (rd==0,rs2!=0) -> C.ADD (rd=0 variant)
        check_both("C.ADD (rd=0 variant)",
                    {1'b1, 2'b00, 5'b00000, 5'b00101, 2'b10});

        // Q2 unknown funct3
        check_both("Q2 unknown funct3(001)",
                    {3'b001, 11'b0, 2'b10});
        check_both("Q2 unknown funct3(010)",
                    {3'b010, 11'b0, 2'b10});
        check_both("Q2 unknown funct3(011)",
                    {3'b011, 11'b0, 2'b10});
        check_both("Q2 unknown funct3(101)",
                    {3'b101, 11'b0, 2'b10});
        check_both("Q2 unknown funct3(110)",
                    {3'b110, 11'b0, 2'b10});
        check_both("Q2 unknown funct3(111)",
                    {3'b111, 11'b0, 2'b10});

        // ---------------- Quadrant 11 : uncompressed -----------------
        check_both("uncompressed instr (Q=11)",
                    16'hFFFF);
        check_both("uncompressed instr (Q=11, zero)",
                    {14'b0, 2'b11});

        // ---------------- All-zero encoding ---------------------------
        // 16'h0000 -> Q0, funct3=000 (C_ADDI4SPN) with all-zero imm -> illegal
        check_both("all-zero encoding (illegal)", 16'h0000);

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("================================================================");
        if (failed_checks == 0)
            $display(" ALL %0d CHECKS PASSED", total_checks);
        else
            $display(" %0d / %0d CHECKS FAILED", failed_checks, total_checks);
        $display("================================================================");

        if (failed_checks != 0) $fatal(1, "Testbench reported failures");
        $finish;
    end

endmodule
