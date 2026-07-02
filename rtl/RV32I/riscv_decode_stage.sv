module riscv_decode_stage (
    input logic clk,
    input logic rst_n, CLR, // Added
    input logic [31:0] instrD,
    input logic [31:0] PCPlus4D,
    input logic [31:0] PCD,
    input logic RegWriteW, // Comming from the last stage and input to the reg file
    input logic [31:0] ResultW, // Comming from the last stage and input to the reg file to be written in the reg file
    input logic [4:0] RdW, // Comming from the last stage and input to the reg file to be written in the reg file
    output logic [31:0] PCE,
    output logic [31:0] PCPlus4E,
    output logic RegWriteE,
    output logic [1:0] ResultSrcE,
    output logic MemWriteE,
    output logic jumpE,
    
    output logic BranchE,
    output logic [2:0] Branch_takenE,

    output logic [2:0] ALUControlE,
    output logic ALUSrcE,
    output logic [31:0] RD1E,
    output logic [31:0] RD2E,
    output logic [31:0] ImmExtE,
    output logic [4:0] RdE,
    output logic [4:0] Rs1E, // Added for the hazard unit
    output logic [4:0] Rs2E, // Added for the hazard unit
    output logic [4:0] Rs1D, // Added for the hazard unit
    output logic [4:0] Rs2D, // Added for the hazard unit
    output logic [2:0] funct3E,
    output logic [1:0] ImmPassE,  // Added for the control unit to pass the immediate value to the execute stage for LUI and AUIPC instructions
    output logic  inst_typeE,
    output logic jalr_pcE,
    
    // NEW: CSR and Trap outputs
    output logic [31:0] instrE,
    output logic [1:0]  o_csr_opE,
    output logic [11:0] o_csr_addrE,
    output logic        o_csr_wenE,
    output logic [4:0]  o_csr_uimmE,
    output logic        o_csr_imm_selE,
    output logic        o_illegal_instr_id_E,
    output logic        o_ecallE,
    output logic        o_ebreakE,
    output logic        o_mretE,
    output logic        o_sretE,
    output logic        o_is_system_instrE
);

    logic RegWriteD;
    logic [1:0] ResultSrcD;
    logic MemWriteD;
    logic jumpD;
    logic BranchD;

    // NEW: SYSTEM / CSR decode logic
    logic [1:0]  csr_opD;
    logic [11:0] csr_addrD;
    logic        csr_wenD;
    logic [4:0]  csr_uimmD;
    logic        csr_imm_selD;
    logic        illegal_instr_id_D;
    logic        ecallD;
    logic        ebreakD;
    logic        mretD;
    logic        sretD;
    logic        is_system_instrD;
    logic [2:0] Branch_taken;
    logic [2:0] ALUControlD;
    logic ALUSrcD;
    logic [2:0] ImmSrcD;
    logic [31:0] RD1;
    logic [31:0] RD2;
    logic [31:0] ImmExtD;
    logic [4:0] RdD;
    logic [1:0] ImmPassD; // Added for the control unit to pass the immediate value to the execute stage for LUI and AUIPC instructions

    logic funct7_5;
    logic inst_type;
    logic jalr_pc;

    // for the hazard unit:

    assign funct7_5 = instrD[30];


    assign RdD = instrD[11:7]; // Destination register address from the instruction

    // Register file instantiation
    riscv_register_file regfile (
        .clk(clk),
        .w_en(RegWriteW), // Write enable signal from the last stage
        .A1(instrD[19:15]), // Source register 1 address
        .A2(instrD[24:20]), // Source register 2 address
        .A3(RdW),   // Destination register address
        .WD3(ResultW), // Data to write to the register file
        .RD1(RD1),    // Data read from source register 1
        .RD2(RD2)     // Data read from source register 2
    );

    // instantiate control unit
    riscv_control_unit cu (
        .opcode(instrD[6:0]), // Opcode from the instruction
        .funct3(instrD[14:12]),  // funct3 from the instruction
        .funct7_5(funct7_5),
        .ResultSrc(ResultSrcD), // Control signal for ALU result source
        .ALUControl(ALUControlD), // Control signal for ALU operation
        .ALUSrc(ALUSrcD), // Control signal for ALU RD2 source .. Extended or not
        .ImmSrc(ImmSrcD), // Control signal for immediate value source
        .RegWrite(RegWriteD), // Control signal for register write enable
        .MemWrite(MemWriteD), // Control signal for memory write enable
        .jump(jumpD),
        .Branch(BranchD),
        .Branch_taken(Branch_taken),
        .ImmPass(ImmPassD),
        .inst_type(inst_type),
        .jalr_pc(jalr_pc),
        .is_system_instr(is_system_instrD)
    );


    // Immediate extension unit
    riscv_extend immext (
        .Instr(instrD), // Instruction input
        .imm_Src(ImmSrcD), // Control signal for immediate value source
        .imm_extend(ImmExtD) // Extended immediate output
    );

    // for the hazard unit:
    assign Rs1D = instrD[19:15]; // Source register 1 address
    assign Rs2D = instrD[24:20]; // Source register 2 address



    logic opcode_valid;
    always_comb begin
        case (instrD[6:0])
            7'b0110011, 7'b0010011, 7'b1100011, 7'b0000011, 7'b0100011,
            7'b1101111, 7'b1100111, 7'b0110111, 7'b0010111, 7'b1110011,
            7'b0001111: opcode_valid = 1'b1;
            default:    opcode_valid = 1'b0;
        endcase
    end

    logic system_valid;
    always_comb begin
        system_valid = 1'b1;
        if (instrD[6:0] == 7'b1110011) begin
            if (instrD[14:12] == 3'b000) begin
                case (instrD[31:20])
                    12'h000, 12'h001, 12'h302, 12'h102: system_valid = 1'b1;
                    default:                            system_valid = 1'b0;
                endcase
            end else begin
                if (instrD[14:12] == 3'b100)
                    system_valid = 1'b0;
                else
                    system_valid = 1'b1;
            end
        end
    end

    assign illegal_instr_id_D = (instrD != 32'h0) && (!opcode_valid || !system_valid);

    assign ecallD     = (instrD[6:0] == 7'b1110011) && (instrD[14:12] == 3'b000) && (instrD[31:20] == 12'h000);
    assign ebreakD    = (instrD[6:0] == 7'b1110011) && (instrD[14:12] == 3'b000) && (instrD[31:20] == 12'h001);
    assign mretD      = (instrD[6:0] == 7'b1110011) && (instrD[14:12] == 3'b000) && (instrD[31:20] == 12'h302);
    assign sretD      = (instrD[6:0] == 7'b1110011) && (instrD[14:12] == 3'b000) && (instrD[31:20] == 12'h102);
    // Zicsr Write Suppression Rules:
    // 1. CSRRW/CSRRWI always write.
    // 2. CSRRS/CSRRC and CSRRSI/CSRRCI only write if rs1/uimm is non-zero.
    logic is_csrD;
    assign is_csrD = (instrD[6:0] == 7'b1110011) && (instrD[14:12] != 3'b000);
    always_comb begin
        if (is_csrD) begin
            case (instrD[13:12]) // funct3[1:0]
                2'b01:   csr_wenD = 1'b1;                             // CSRRW / CSRRWI (always write)
                2'b10,
                2'b11:   csr_wenD = (instrD[19:15] != 5'b0);          // CSRRS/C or CSRRSI/C (write only if rs1/uimm != 0)
                default: csr_wenD = 1'b0;
            endcase
        end else begin
            csr_wenD = 1'b0;
        end
    end
    assign csr_opD    = ((instrD[6:0] == 7'b1110011) && (instrD[14:12] != 3'b000)) ? instrD[13:12] : 2'b00;
    assign csr_addrD  = instrD[31:20];
    assign csr_uimmD  = instrD[19:15];
    assign csr_imm_selD = instrD[14];

    // Sequential logic to update pipeline registers on the rising edge of the clock
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n || CLR)begin
            PCE <= 0;
            PCPlus4E <= 0;
            RegWriteE <= 0;
            ResultSrcE <= 0;
            MemWriteE <= 0;
            jumpE <= 0;
            BranchE <= 0;
            ALUControlE <= 0;
            ALUSrcE <= 0;
            RD1E <= 0;
            RD2E <= 0;
            ImmExtE <= 0;
            RdE <= 0;
            Rs1E <= 0;
            Rs2E <= 0;
            funct3E <= 0;
            ImmPassE <= 0;
            inst_typeE <= 0;
            BranchE <= 0;
            jalr_pcE <= 0;
            o_csr_opE <= 0;
            o_csr_addrE <= 0;
            o_csr_wenE <= 0;
            o_csr_uimmE <= 0;
            o_csr_imm_selE <= 0;
            o_illegal_instr_id_E <= 0;
            o_ecallE <= 0;
            o_ebreakE <= 0;
            o_mretE <= 0;
            o_sretE <= 0;
            o_is_system_instrE <= 0;
            instrE <= 0;
        end
        else begin
            PCE <= PCD; 
            PCPlus4E <= PCPlus4D;
            instrE <= instrD;
            RegWriteE <= RegWriteD;
            ResultSrcE <= ResultSrcD;
            MemWriteE <= MemWriteD;
            jumpE <= jumpD;
            BranchE <= BranchD;
            Branch_takenE <= Branch_taken;
            ALUControlE <= ALUControlD;
            ALUSrcE <= ALUSrcD;
            RD1E <= RD1;
            RD2E <= RD2;
            ImmExtE <= ImmExtD;
            RdE <= RdD;
            Rs1E <= Rs1D;
            Rs2E <= Rs2D;
            funct3E <= instrD[14:12];
            ImmPassE <= ImmPassD;
            inst_typeE <= inst_type;
            jalr_pcE <= jalr_pc;
            o_csr_opE <= csr_opD;
            o_csr_addrE <= csr_addrD;
            o_csr_wenE <= csr_wenD;
            o_csr_uimmE <= csr_uimmD;
            o_csr_imm_selE <= csr_imm_selD;
            o_illegal_instr_id_E <= illegal_instr_id_D;
            o_ecallE <= ecallD;
            o_ebreakE <= ebreakD;
            o_mretE <= mretD;
            o_sretE <= sretD;
            o_is_system_instrE <= is_system_instrD;
        end
    end

endmodule
