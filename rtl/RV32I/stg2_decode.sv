module decode (
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
    output logic jalr_pcE
);

    logic RegWriteD;
    logic [1:0] ResultSrcD;
    logic MemWriteD;
    logic jumpD;
    logic BranchD;
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
    register_file regfile (
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
    control_unit cu (
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
        .jalr_pc(jalr_pc)
    );


    // Immediate extension unit
    extend immext (
        .Instr(instrD), // Instruction input
        .imm_Src(ImmSrcD), // Control signal for immediate value source
        .imm_extend(ImmExtD) // Extended immediate output
    );

    // for the hazard unit:
    assign Rs1D = instrD[19:15]; // Source register 1 address
    assign Rs2D = instrD[24:20]; // Source register 2 address


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
        end
        else begin
            PCE <= PCD; 
            PCPlus4E <= PCPlus4D;
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
        end
    end


endmodule




