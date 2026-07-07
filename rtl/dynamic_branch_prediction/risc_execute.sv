module execute_prediction_logic (
    input  wire [31:0] exe_pc,               // ??? PC ?????? ???? ??????? ????
    input  wire        predict_taken_old,    // ?????? ?????? ???? ????? ?? ??? Fetch ??????? ??
    
    // ???????? ??????? ?? ??? ALU ???? Decoder ?? ??? Execute 
    input  wire        exe_is_branch,        
    input  wire        actual_taken,         
    input  wire [31:0] actual_target_pc,     
    
    //  ???????? ??????? ?? ??? BHT 
    input  wire [1:0]  current_counter,      
    
    //     BHT & BTB ?????? 
    output wire        bht_write_en,         //   ??????? ?? ??? BHT
    output wire        btb_write_en,         //   ??????? ?? ??? BTB
    output reg  [1:0]  next_counter,         
    
    output wire        flush_pipeline,       
    output wire [31:0] corrected_pc          
);

    wire misprediction;
    assign misprediction  = exe_is_branch && (predict_taken_old != actual_taken);
    
    assign flush_pipeline = misprediction;

    assign corrected_pc = (actual_taken) ? actual_target_pc : (exe_pc + 32'd4);

    always @(*) begin
        case (current_counter)
            2'b00: next_counter = (actual_taken) ? 2'b01 : 2'b00; 
            2'b01: next_counter = (actual_taken) ? 2'b10 : 2'b00; 
            2'b10: next_counter = (actual_taken) ? 2'b11 : 2'b01; 
            2'b11: next_counter = (actual_taken) ? 2'b11 : 2'b10; 
            default: next_counter = 2'b01; 
        endcase
    end

    assign bht_write_en = exe_is_branch;
    
    assign btb_write_en = exe_is_branch && actual_taken;

endmodule




