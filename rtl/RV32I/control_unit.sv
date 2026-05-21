module control_unit (
    input  logic [6:0] opcode, 
    input  logic [2:0] funct3,
    input  logic       funct7_5,

    output logic [1:0] ResultSrc,    // Control signal for ALU result source
    output logic [2:0] ALUControl,   // Control signal for ALU operation
    output logic       ALUSrc,       // Control signal for ALU RD2 source
    output logic [2:0] ImmSrc,       // Control signal for immediate value source
    output logic       RegWrite,     // Control signal for register write enable
    output logic       MemWrite,     // Control signal for memory write enable
    output logic       jump,
    output logic [2:0] Branch_taken,
    output logic       Branch,
    output logic [1:0] ImmPass,
    output logic       inst_type,
    output logic       jalr_pc,
    output logic is_system_instr
);

    logic [1:0] ALUOp; // Control signal for ALU Decoder (Updated to SystemVerilog logic)

    always_comb begin
        // --- Grand Default Values (Prevents Latch Generation) ---
        ResultSrc    = 2'b00; 
        ALUSrc       = 1'b0;  
        ImmSrc       = 3'b000;
        RegWrite     = 1'b0;  
        MemWrite     = 1'b0;  
        ALUOp        = 2'b00; 
        inst_type    = 1'b0;
        Branch       = 1'b0;
        Branch_taken = 3'b000;
        jalr_pc      = 1'b0;
        jump         = 1'b0;
        ImmPass      = 2'b00;
        ALUControl   = 3'b000;
        is_system_instr = 1'b0;


        // --- Main Opcode Decoder ---
        case (opcode)
            7'b0110011: begin // R-type instructions
                RegWrite   = 1'b1; 
                ALUOp      = 2'b10; 
                ImmSrc     = 3'bxxx; 
            end
            
            7'b0010011: begin // I-type immediate arithmetic (ADDI, etc.)
                ALUSrc     = 1'b1; 
                RegWrite   = 1'b1; 
                ALUOp      = 2'b10; 
            end
            
            7'b1100011: begin // B-type conditional branches
                ResultSrc  = 2'bxx; 
                ImmSrc     = 3'b010; 
                ALUOp      = 2'b01; 
                Branch     = 1'b1;
            end
            
            7'b0000011: begin // I-type Load instructions (LW)
                ALUSrc     = 1'b1; 
                RegWrite   = 1'b1; 
                ResultSrc  = 2'b01; 
            end
            
            7'b0100011: begin // S-type Store instructions (SW)
                ALUSrc     = 1'b1; 
                ImmSrc     = 3'b001; 
                MemWrite   = 1'b1; 
                ResultSrc  = 2'bxx; 
            end
            
            7'b1101111: begin // J-type Unconditional Jump (JAL)
                ALUSrc     = 1'bx; 
                ImmSrc     = 3'b100; 
                RegWrite   = 1'b1; 
                ALUOp      = 2'bxx; 
                ResultSrc  = 2'b10; 
                jump       = 1'b1;
            end
            
            7'b1100111: begin // I-type Unconditional Jump (JALR)
                ALUSrc     = 1'b1; 
                RegWrite   = 1'b1; 
                ResultSrc  = 2'b10; 
                jump       = 1'b1;
                jalr_pc    = 1'b1;
            end
            
            7'b0110111: begin // U-type Load Upper Immediate (LUI)
                ALUSrc     = 1'b1; 
                ImmSrc     = 3'b011; 
                RegWrite   = 1'b1; 
                ImmPass    = 2'b01;
            end
            
            7'b0010111: begin // U-type Add Upper Immediate to PC (AUIPC)
                ALUSrc     = 1'b1; 
                ImmSrc     = 3'b011; 
                RegWrite   = 1'b1; 
                ImmPass    = 2'b10;
            end
            
            7'b1110011: begin // SYSTEM Instructions (ECALL, EBREAK, CSRs)
                is_system_instr = 1'b1;
                ALUSrc     = 1'bx;
                ImmSrc     = 3'b0xx;
                ALUOp      = 2'bxx;
                ResultSrc  = 2'bxx;
            end

            7'b0001111: begin // FENCE instruction
                // Left intentionally for future expansion / safety
            end

            default: ; // Keeps grand defaults intact securely
        endcase

        // --- Hardware ALU Decoder ---
        case (ALUOp)
            2'b00: begin // Load/Store address generation (Forces ADD)
                ALUControl = 3'b000; 
                inst_type  = 1'b0;
            end
            
            2'b01: begin // Branch handling
                inst_type    = 1'b1;
                Branch_taken = funct3;

                unique case (funct3[2:1])
                    2'b00:   ALUControl = 3'b000; // BEQ, BNE
                    2'b10:   ALUControl = 3'b101; // BLT, BGE
                    2'b11:   ALUControl = 3'b111; // BLTU, BGEU
                    default: ALUControl = 3'b000;
                endcase
            end
            
            2'b10: begin // R-type & I-type Arithmetic/Logic
                case (funct3)
                    3'b000: begin // ADD / SUB / ADDI
                        ALUControl = 3'b000;
                        if (funct7_5 && (opcode == 7'b0110011)) 
                            inst_type = 1'b1; // Flag for Subtract
                        else
                            inst_type = 1'b0; // Flag for Add
                    end
                    3'b001: ALUControl = 3'b110; // SLL / SLLI (Shift Left Logical)
                    3'b010: ALUControl = 3'b101; // SLT / SLTI (Set Less Than)
                    3'b011: ALUControl = 3'b111; // SLTU / SLTIU (Set Less Than Unsigned)
                    3'b100: ALUControl = 3'b100; // XOR / XORI
                    3'b101: begin                // SRL / SRA / SRLI / SRAI
                        ALUControl = 3'b001; 
                        inst_type  = funct7_5;   // 0: Logical (SRL), 1: Arithmetic (SRA)
                    end
                    3'b110: ALUControl = 3'b011; // OR / ORI
                    3'b111: ALUControl = 3'b010; // AND / ANDI
                endcase
            end
            
            default: ALUControl = 3'b000; 
        endcase
    end
endmodule