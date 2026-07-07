module riscv_execute_stage (
    input logic clk,
    input logic rst_n, CLR,
    input logic [31:0] PCE,
    input logic [31:0] PCPlus4E,
    input logic RegWriteE,
    input logic [1:0] ResultSrcE,
    input logic MemWriteE,
    input logic jumpE,
    input logic [2:0] ALUControlE,
    input logic ALUSrcE,
    input logic [31:0] RD1E,
    input logic [31:0] RD2E,
    input logic [31:0] ImmExtE,
    input logic [4:0] RdE,
    input logic [2:0] funct3E,
    input logic [1:0] ImmPassE,
    input logic inst_typeE,
    input logic jalr_pcE,
    input logic [31:0] instrE,
    input logic [1:0]  csr_opE,
    input logic [11:0] csr_addrE,
    input logic        csr_wenE,
    input logic [4:0]  csr_uimmE,
    input logic        csr_imm_selE,
    input logic        illegal_instr_id_E,
    input logic        ecallE,
    input logic        ebreakE,
    input logic        mretE,
    input logic        sretE,
    input logic        is_system_instrE,
    input logic        PCSrcE,
    input logic        custom_result_validE,
    input logic [31:0] custom_resultE,

    output logic  RegWriteM,
    output logic  [1:0] ResultSrcM,
    output logic  MemWriteM,
    output logic  [31:0] ALUResultM,
    output logic  [31:0] WriteDataM,
    output logic  [4:0] RdM,
    output logic  [31:0] PCTargetE_new,
    output logic  [31:0] PCPlus4M,
    output logic ZeroE,
    output logic [2:0] funct3M,
    output logic [31:0] PCM,
    output logic [31:0] instrM,
    output logic [1:0]  csr_opM,
    output logic [11:0] csr_addrM,
    output logic        csr_wenM,
    output logic [31:0] csr_srcM,
    output logic        illegal_instr_id_M,
    output logic        illegal_instr_exe_M,
    output logic        instr_addr_misaligned_M,
    output logic        ecallM,
    output logic        ebreakM,
    output logic        mretM,
    output logic        sretM,
    output logic        is_system_instrM
);

    wire [31:0] SrcBE;
    wire [31:0] WriteDataE;

    wire [31:0] ALUResultE;
    logic  [31:0] PCTargetE;
    logic         m_ext_validE;
    logic [31:0]  m_ext_resultE;
    logic signed [63:0] mul_ss_E;
    logic        [63:0] mul_uu_E;
    logic signed [64:0] mul_su_E;

    assign WriteDataE = RD2E; // Data to be written to memory (used in the memory stage)

    // SrcBE is the second operand for the ALU, which can be either RD2E or ImmExtE based on the ALUSrcE control signal
    assign SrcBE = (!ALUSrcE) ? RD2E: ImmExtE;
    // ALU instantiation
    riscv_alu aluE (
        .src_a(RD1E), // Source operand A
        .src_b(SrcBE), // Source operand B (either RD2E or ImmExtE based on ALUSrcE)
        .inst_typeE(inst_typeE),
        .alu_control(ALUControlE), // ALU control signal
        .Zero(ZeroE), // Zero flag output from ALU
        .result(ALUResultE) // ALU result (not used in this stage)
    );

    assign m_ext_validE = (instrE[6:0] == 7'b0110011) && (instrE[31:25] == 7'b0000001);
    assign mul_ss_E = $signed(RD1E) * $signed(RD2E);
    assign mul_uu_E = $unsigned(RD1E) * $unsigned(RD2E);
    assign mul_su_E = $signed({{33{RD1E[31]}}, RD1E}) * $signed({33'b0, RD2E});

    always_comb begin
        unique case (instrE[14:12])
            3'b000: m_ext_resultE = mul_ss_E[31:0];                  // MUL
            3'b001: m_ext_resultE = mul_ss_E[63:32];                 // MULH
            3'b010: m_ext_resultE = mul_su_E[63:32];                 // MULHSU
            3'b011: m_ext_resultE = mul_uu_E[63:32];                 // MULHU
            3'b100: begin                                           // DIV
                if (RD2E == 32'b0)
                    m_ext_resultE = 32'hFFFF_FFFF;
                else if (RD1E == 32'h8000_0000 && RD2E == 32'hFFFF_FFFF)
                    m_ext_resultE = 32'h8000_0000;
                else
                    m_ext_resultE = $signed(RD1E) / $signed(RD2E);
            end
            3'b101: begin                                           // DIVU
                if (RD2E == 32'b0)
                    m_ext_resultE = 32'hFFFF_FFFF;
                else
                    m_ext_resultE = $unsigned(RD1E) / $unsigned(RD2E);
            end
            3'b110: begin                                           // REM
                if (RD2E == 32'b0)
                    m_ext_resultE = RD1E;
                else if (RD1E == 32'h8000_0000 && RD2E == 32'hFFFF_FFFF)
                    m_ext_resultE = 32'b0;
                else
                    m_ext_resultE = $signed(RD1E) % $signed(RD2E);
            end
            3'b111: begin                                           // REMU
                if (RD2E == 32'b0)
                    m_ext_resultE = RD1E;
                else
                    m_ext_resultE = $unsigned(RD1E) % $unsigned(RD2E);
            end
            default: m_ext_resultE = 32'b0;
        endcase
    end

    // instantiate PCTarget unit
    riscv_pc_target pc_targetE (
        .PC(PCE), // PC + 4 input
        .ImmExt(ImmExtE), // Extended immediate input
        .PC_Target(PCTargetE) // Calculated PC target output
    );

    // PCSrcE is determined by the branch condition (BranchE && ZeroE) or the jump signal (jumpE)
    
    assign PCTargetE_new = (jalr_pcE)? ALUResultE: PCTargetE;

    logic instr_addr_misaligned_E;
    assign instr_addr_misaligned_E = PCSrcE && (PCTargetE_new[0] != 1'b0);

    // Pipeline register for the execute stage to memory stage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || CLR) begin
            RegWriteM  <= 0;
            ResultSrcM <= 0;
            MemWriteM  <= 0;
            WriteDataM <= 0;
            RdM        <= 0;
            PCPlus4M   <= 0;
            funct3M    <= 0;
            ALUResultM <= 0;
            PCM        <= 0;
            instrM     <= 0;
            csr_opM    <= 0;
            csr_addrM  <= 0;
            csr_wenM   <= 0;
            csr_srcM   <= 0;
            illegal_instr_id_M   <= 0;
            illegal_instr_exe_M  <= 0;
            instr_addr_misaligned_M <= 0;
            ecallM     <= 0;
            ebreakM    <= 0;
            mretM      <= 0;
            sretM      <= 0;
            is_system_instrM <= 0;
        end else begin
            RegWriteM <= RegWriteE; // Pass register write enable signal to memory stage
            ResultSrcM <= ResultSrcE; // Pass ALU result source control signal to memory stage
            MemWriteM <= MemWriteE; // Pass memory write enable signal to memory stage
            WriteDataM <= WriteDataE; // Pass data to be written to memory to memory stage
            RdM <= RdE; // Pass destination register address to memory stage
            PCPlus4M <= PCPlus4E; // Pass PC + 4 to memory stage
            funct3M <= funct3E;
            PCM        <= PCE;
            instrM     <= instrE;
            csr_opM    <= csr_opE;
            csr_addrM  <= csr_addrE;
            csr_wenM   <= csr_wenE;
            csr_srcM   <= csr_imm_selE ? {27'b0, csr_uimmE} : RD1E;
            illegal_instr_id_M   <= illegal_instr_id_E;
            illegal_instr_exe_M  <= 1'b0; // No execute-stage illegal instruction logic here
            instr_addr_misaligned_M <= instr_addr_misaligned_E;
            ecallM     <= ecallE;
            ebreakM    <= ebreakE;
            mretM      <= mretE;
            sretM      <= sretE;
            is_system_instrM <= is_system_instrE;

            if (custom_result_validE) begin
                ALUResultM <= custom_resultE;
            end else if (m_ext_validE) begin
                ALUResultM <= m_ext_resultE;
            end else begin
                case(ImmPassE)
                    2'b01: ALUResultM <= ImmExtE;
                    2'b10: ALUResultM <= PCTargetE;
                    default: ALUResultM <= ALUResultE;
                endcase
            end
            // $display("mux signal = %h, ImmExtE=%h, PCTargetE =%h, ALUResultM=%h", ImmPassE, ImmExtE, PCTargetE, ALUResultM);
        end
    end

endmodule
