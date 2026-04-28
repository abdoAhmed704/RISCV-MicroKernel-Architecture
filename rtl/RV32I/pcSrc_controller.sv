module pcSrc_controller(
    input logic ZeroE,
    input logic BranchE,
    input logic [2:0] Branch_takenE,

    output logic target_taken
);

always @(*) begin
    if (BranchE)
    begin
        
        case(Branch_takenE)
        3'b000: 
            target_taken = ZeroE;
        3'b001: 
            target_taken = !ZeroE;
        3'b100: 
            target_taken = !ZeroE;
        3'b101: 
            target_taken = ZeroE;
        3'b110: 
            target_taken = !ZeroE;
        3'b111: 
            target_taken = ZeroE;
        default:
            target_taken = 1'b0;
        endcase
    end
    else
        target_taken = 1'b0;
end

endmodule