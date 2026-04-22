module control_unit (
    input logic[6:0] opcode, // 6-bit opcode from instruction
    input logic [2:0] funct3,  // 3-bit function code for R-type and I-type instructions
    // input Zero, // Zero flag from ALU
    output logic [1:0]ResultSrc, // Control signal for ALU result source
    output logic [2:0] ALUControl, // Control signal for ALU operation
    output logic ALUSrc, // Control signal for ALU RD2 source .. Extended or not
    output logic [1:0] ImmSrc, // Control signal for immediate value source
    output logic RegWrite, // Control signal for register write enable
    output logic MemWrite, // Control signal for memory write enable
    output logic jump,
    output logic Branch,
    output logic ImmPass
);
    reg [1:0] ALUOp; // Control signal for ALU Decoder

    always @(*) begin

        // PC Logic

        // Default values for control signals
        ResultSrc = 2'b00; // Default to ALU result
        ALUSrc = 0; // Default to register source
        ImmSrc = 2'b00; // Default to no immediate
        RegWrite = 0; // Default to no register write
        MemWrite = 0; // Default to no memory write
        ALUOp = 2'b00; // Default to R-type operation

        case (opcode)
            7'b0110011: begin // R-type instructions
                ResultSrc = 2'b00; // Default to ALU result
                ALUSrc = 0; // Default to register source
                ImmSrc = 2'bxx; // Default to no immediate
                RegWrite = 1; // Default to no register write
                MemWrite = 0; // Default to no memory write
                ALUOp = 2'b10; // Default to R-type operation
                Branch = 0;
                jump=0;
                ImmPass=0;
            end
            7'b0010011: begin // I-type instructions (ADDI)
                ResultSrc = 2'b00; // Default to ALU result
                ALUSrc = 1; // Use immediate value for ALU source
                ImmSrc = 2'b00; // Use I-type immediate for address calculation
                RegWrite = 1; // Enable register write for I-type instructions
                MemWrite = 0; // Disable memory write for I-type instructions
                ALUOp = 2'b10; // Set ALU operation type for I-type instructions
                Branch = 0;
                jump=0;
                ImmPass=0;
            end
            7'b1100011: begin // B Type - beq instruction
                ResultSrc = 2'bxx; // Default to ALU result
                ALUSrc = 0; // Default to register source
                ImmSrc = 2'b10; // Use B-type immediate for branch address calculation
                RegWrite = 0; // Disable register write for branch instructions
                MemWrite = 0; // Disable memory write for branch instructions
                ALUOp = 2'b01; // Set ALU operation type for branch instructions
                Branch = 1; 
                jump = 0;
                ImmPass=0;
            end
            7'b0000011: begin // Load instructions ( LW)
                ALUSrc = 1; // Use immediate value for address calculation
                ImmSrc = 2'b00; // Use I-type immediate for load instructions
                RegWrite = 1; // Enable register write for load instructions
                MemWrite = 0; // Disable memory write for load instructions
                ALUOp = 2'b00; // Set ALU operation type for load instructions
                ResultSrc = 2'b01; // Use memory data as result for load instructions
                Branch = 0;
                jump=0;
                ImmPass=0;

            end
            7'b0100011: begin // Store instructions (SW)
                ALUSrc = 1; // Use immediate value for address calculation
                ImmSrc = 2'b01; // Use S-type immediate for store instructions
                RegWrite = 0; // Disable register write for store instructions
                MemWrite = 1; // Enable memory write for store instructions
                ALUOp = 2'b00; // Set ALU operation type for store instructions
                ResultSrc = 2'bxx; // Use ALU result for store instructions
                Branch = 0;
                jump=0;
                ImmPass=0;

            end
            7'b1101111: begin // JAL instruction
                ALUSrc = 1'bx; // Use register source for address calculation
                ImmSrc = 2'b11; // Use J-type immediate for jump address calculation
                RegWrite = 1; // Enable register write for JAL instruction
                MemWrite = 0; // Disable memory write for JAL instruction
                ALUOp = 2'bxx; // Set ALU operation type for JAL instruction
                ResultSrc = 2'b10; // Use memory data as result for JAL instruction
                Branch = 0;
                jump=0;
                ImmPass=0;
            end
            7'b1100111: begin // JALR instruction
                ALUSrc = 1; // Use immediate value for address calculation
                ImmSrc = 2'b00; // Use I-type immediate for JALR instruction
                RegWrite = 1; // Enable register write for JALR instruction
                MemWrite = 0; // Disable memory write for JALR instruction
                ALUOp = 2'bxx; // Set ALU operation type for JALR instruction
                ResultSrc = 2'b10; // Use memory data as result for JALR instruction
                Branch = 0;
                jump=1;
                ImmPass=0;
            end
            7'b0110111: begin // LUI instruction
                ALUSrc = 1; // Use immediate value for address calculation
                ImmSrc = 2'b11; // Use U-type immediate for LUI instruction
                RegWrite = 1; // Enable register write for LUI instruction
                MemWrite = 0; // Disable memory write for LUI instruction
                ALUOp = 2'b00; // Set ALU operation type for LUI instruction
                ResultSrc = 2'b00; // Use memory data as result for LUI instruction
                Branch = 0;
                jump=0;
                ImmPass=1;
            end
            7'b0010111: begin // AUIPC instruction
                ALUSrc = 1; // Use immediate value for address calculation
                ImmSrc = 2'b11; // Use U-type immediate for AUIPC instruction
                RegWrite = 1; // Enable register write for AUIPC instruction
                MemWrite = 0; // Disable memory write for AUIPC instruction
                ALUOp = 2'b00; // Set ALU operation type for AUIPC instruction
                ResultSrc = 2'b11; // Use memory data as result for AUIPC instruction
                Branch = 0;
                jump=0;
                ImmPass=1;
            end
            7'b1110011: begin // ECALL instruction ane EBREAK instruction
                ALUSrc = 1'bx; // Don't care for ECALL
                ImmSrc = 2'bxx; // Don't care for ECALL
                RegWrite = 0; // Disable register write for ECALL instruction
                MemWrite = 0; // Disable memory write for ECALL instruction
                ALUOp = 2'bxx; // Don't care for ECALL instruction
                ResultSrc = 2'bxx; // Don't care for ECALL instruction
                Branch = 0;
                jump=0;
                ImmPass=0;
            end
            7'b0001111: begin
                // fence instruction
            end
            default: begin 
                Branch = 0;
                jump=0;
                ImmPass=0;
            end
        endcase
        
        case (ALUOp) // ALU Decoder
            2'b00: begin // Load/Store instructions
                ALUControl = 3'b000; // Use ADD operation for address calculation
            end
            2'b01: begin // Branch instructions
                ALUControl = 3'b001; // Use SUB operation for branch comparison
            end
            2'b10: begin // R-type instructions
                case (funct3)
                    3'b000: begin // ADD/SUB
                        ALUControl = 3'b000;
                    end
                    3'b001: begin
                        ALUControl = 3'b110;        // Shift left logical
                    end
                    3'b010: begin
                        ALUControl = 3'b101;        // Set Less Than
                    end
                    3'b011: begin
                        ALUControl = 3'b111;        // Set Less Than U
                    end
                    3'b100: begin
                        ALUControl = 3'b100;        // XOR
                    end
                    3'b101: begin
                        ALUControl = 3'b001;        // Shift right Logical w Arithematic
                    end
                    3'b110: begin
                        ALUControl = 3'b011;        // OR
                    end
                    3'b111: begin
                        ALUControl = 3'b010;        // AND
                    end
                endcase
            end
            default: ALUControl = 3'b000; // Invalid ALUOp code    
        endcase
    end
endmodule