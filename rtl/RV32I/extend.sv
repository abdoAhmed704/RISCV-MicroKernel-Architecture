module extend (input [2:0] imm_Src, input [31:0] Instr, output reg [31:0] imm_extend);

always @(*) begin
    case(imm_Src)
    3'b000:  begin // For I type
        imm_extend = {{20{Instr[31]}}, Instr[31:20]};
    end
    3'b001: begin // For S type
        imm_extend = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};
    end
    3'b010: begin // For B type
        imm_extend = {{19{Instr[31]}}, Instr[31], Instr[7], Instr[30:25], Instr[11:8], 1'b0};
    end
    3'b011: begin // U Type
        imm_extend = {{Instr[31:12], 12'b0}}; 
    end
    3'b100: begin // FOr J type
        imm_extend = { {12{Instr[31]}}, Instr[19:12], Instr[20], Instr[30:21], 1'b0 };
    end
    
    
    endcase



end


endmodule