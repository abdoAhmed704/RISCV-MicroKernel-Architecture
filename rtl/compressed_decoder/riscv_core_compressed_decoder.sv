module riscv_core_compressed_decoder #(
    parameter int XLEN = 32          // 32 = RV32C, 64 = RV64C
) (
    input logic  [31:0] i_compressed_decoder_instr,
    output logic [31:0] o_compressed_decoder_instr,
    output logic        o_compressed_decoder_is_compressed,
    output logic        o_compressed_decoder_illegal_instr
);

localparam Q0 = 2'b00; // Quadrant 0
localparam Q1 = 2'b01; // Quadrant 1
localparam Q2 = 2'b10; // Quadrant 2
localparam C_ADDI4SPN = 3'b000;
localparam C_ADDI_NOP = 3'b000;
localparam C_LI = 3'b010;
localparam C_ADDIL6SP_LUI = 3'b011;
localparam C_ARTH_LOGIC = 3'b100;
localparam C_SLLI = 3'b000;
localparam C_MV_ADD_EBREAK = 3'b100;

always_comb begin
    // default
    o_compressed_decoder_is_compressed = 1'b1;
    o_compressed_decoder_illegal_instr = 1'b0;
    o_compressed_decoder_instr         = i_compressed_decoder_instr;

    unique case (i_compressed_decoder_instr[1:0])
       Q0 : begin
        unique case (i_compressed_decoder_instr[15:13])
           C_ADDI4SPN : begin
              o_compressed_decoder_instr = {
                2'b00,
                i_compressed_decoder_instr[10:7],
                i_compressed_decoder_instr[12:11],
                i_compressed_decoder_instr[5],
                i_compressed_decoder_instr[6],
                2'b00,
                5'h02,
                3'b000,
                2'b01,
                i_compressed_decoder_instr[4:2],
                7'b0010011
              };
              if (i_compressed_decoder_instr[12:5] == 8'b0) o_compressed_decoder_illegal_instr = 1'b1;
           end 
            default: o_compressed_decoder_illegal_instr = 1'b1;
        endcase
       end
       Q1 : begin
        unique case (i_compressed_decoder_instr[15:13])
           C_ADDI_NOP : begin
                o_compressed_decoder_instr = {
                    {6{i_compressed_decoder_instr[12]}},
                    i_compressed_decoder_instr[12],
                    i_compressed_decoder_instr[6:2],
                    i_compressed_decoder_instr[11:7],
                    3'b0,
                    i_compressed_decoder_instr[11:7],
                    7'b0010011
                };
           end
           C_LI : begin
                o_compressed_decoder_instr = {
                    {6{i_compressed_decoder_instr[12]}},
                    i_compressed_decoder_instr[12],
                    i_compressed_decoder_instr[6:2],
                    5'b0,
                    3'b0,
                    i_compressed_decoder_instr[11:7],
                    7'b0010011
                };
           end
           C_ADDIL6SP_LUI : begin
            if (i_compressed_decoder_instr[11:7] == 5'h02) begin
                o_compressed_decoder_instr = {
                    {3{i_compressed_decoder_instr[12]}},
                    i_compressed_decoder_instr[4:3],
                    i_compressed_decoder_instr[5],
                    i_compressed_decoder_instr[2],
                    i_compressed_decoder_instr[6],
                    4'b0,
                    5'h02,
                    3'b0,
                    5'h02,
                    7'b0010011
                };
            end
            else begin
                o_compressed_decoder_instr = {
                    {14{i_compressed_decoder_instr[12]}},
                    i_compressed_decoder_instr[12],
                    i_compressed_decoder_instr[6:2],
                    i_compressed_decoder_instr[11:7],
                    7'b0110111
                };
                if (i_compressed_decoder_instr[12] == 1'b0 &&
                    i_compressed_decoder_instr[6:2] == 5'b0) begin
                    o_compressed_decoder_illegal_instr = 1'b1;
                end
            end
           end
           C_ARTH_LOGIC : begin
               unique case (i_compressed_decoder_instr[11:10])
               2'b00 : begin // --SRLI
                    if (XLEN == 32 && i_compressed_decoder_instr[12] == 1'b1) begin
                        o_compressed_decoder_illegal_instr = 1'b1;
                    end else begin
                        o_compressed_decoder_instr = {
                            6'b000000,
                            i_compressed_decoder_instr[12],
                            i_compressed_decoder_instr[6:2],
                            2'b01,
                            i_compressed_decoder_instr[9:7],
                            3'b101,
                            2'b01,
                            i_compressed_decoder_instr[9:7],
                            7'b0010011
                       };
                    end
               end
               2'b01 : begin // --SRAI
                    if (XLEN == 32 && i_compressed_decoder_instr[12] == 1'b1) begin
                        o_compressed_decoder_illegal_instr = 1'b1;
                    end else begin
                        o_compressed_decoder_instr = {
                            6'b010000,
                            i_compressed_decoder_instr[12],
                            i_compressed_decoder_instr[6:2],
                            2'b01,
                            i_compressed_decoder_instr[9:7],
                            3'b101,
                            2'b01,
                            i_compressed_decoder_instr[9:7],
                            7'b0010011
                       };
                    end
               end
               2'b10 : begin // --ANDI
                    o_compressed_decoder_instr = {
                        {6{i_compressed_decoder_instr[12]}},
                        i_compressed_decoder_instr[12],
                        i_compressed_decoder_instr[6:2],
                        2'b01,
                        i_compressed_decoder_instr[9:7],
                        3'b111,
                        2'b01,
                        i_compressed_decoder_instr[9:7],
                        7'b0010011
                   };
               end
               2'b11 : begin // --ALU
                   if (i_compressed_decoder_instr[12] == 1'b0) begin
                        unique case (i_compressed_decoder_instr[6:5])
                           2'b00 : begin // --SUB
                                o_compressed_decoder_instr = {
                                    2'b01,
                                    5'b0,
                                    2'b01,
                                    i_compressed_decoder_instr[4:2],
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    3'b0,
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    7'b0110011
                                };
                           end
                           2'b01 : begin // --XOR
                                o_compressed_decoder_instr = {
                                    7'b0,
                                    2'b01,
                                    i_compressed_decoder_instr[4:2],
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    3'b100,
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    7'b0110011
                                };
                           end
                           2'b10 : begin // --OR
                                o_compressed_decoder_instr = {
                                    7'b0,
                                    2'b01,
                                    i_compressed_decoder_instr[4:2],
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    3'b110,
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    7'b0110011
                                };
                           end
                           2'b11 : begin // --AND
                                o_compressed_decoder_instr = {
                                    7'b0,
                                    2'b01,
                                    i_compressed_decoder_instr[4:2],
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    3'b111,
                                    2'b01,
                                    i_compressed_decoder_instr[9:7],
                                    7'b0110011
                                };
                           end 
                        endcase
                   end
                   else begin
                        if (XLEN == 64) begin
                            unique case (i_compressed_decoder_instr[6:5])
                               2'b00 : begin // --SUBW
                                    o_compressed_decoder_instr = {
                                        2'b01,
                                        5'b0,
                                        2'b01,
                                        i_compressed_decoder_instr[4:2],
                                        2'b01,
                                        i_compressed_decoder_instr[9:7],
                                        3'b0,
                                        2'b01,
                                        i_compressed_decoder_instr[9:7],
                                        7'b0111011
                                    };
                               end
                               2'b01 : begin // --ADDW
                                    o_compressed_decoder_instr = {
                                        7'b0,
                                        2'b01,
                                        i_compressed_decoder_instr[4:2],
                                        2'b01,
                                        i_compressed_decoder_instr[9:7],
                                        3'b0,
                                        2'b01,
                                        i_compressed_decoder_instr[9:7],
                                        7'b0111011
                                    };
                               end
                                default: o_compressed_decoder_illegal_instr = 1'b1;
                            endcase
                        end else begin
                            o_compressed_decoder_illegal_instr = 1'b1; // RES on RV32C
                        end
                   end
               end 
               endcase
           end
          
            default: o_compressed_decoder_illegal_instr = 1'b1;
        endcase
       end
       Q2 : begin
            unique case (i_compressed_decoder_instr[15:13])
               C_SLLI : begin
                  
                    if (XLEN == 32 && i_compressed_decoder_instr[12] == 1'b1) begin
                        o_compressed_decoder_illegal_instr = 1'b1;
                    end else begin
                        o_compressed_decoder_instr = {
                            6'b0,
                            i_compressed_decoder_instr[12],     // shamt[5], RV64C only
                            i_compressed_decoder_instr[6:2],     // shamt[4:0]
                            i_compressed_decoder_instr[11:7],
                            3'b001,
                            i_compressed_decoder_instr[11:7],
                            7'b0010011
                        };
                    end
               end
               
               C_MV_ADD_EBREAK : begin
                    if (i_compressed_decoder_instr[12] == 1'b0) begin
                        if (i_compressed_decoder_instr[6:2] == 5'b0) begin
                            o_compressed_decoder_illegal_instr = 1'b1;
                        end
                        else begin 
                            o_compressed_decoder_instr = {
                                7'b0,
                                i_compressed_decoder_instr[6:2],
                                5'b0,
                                3'b0,
                                i_compressed_decoder_instr[11:7],
                                7'b0110011
                            };
                            if (i_compressed_decoder_instr[11:7] == 5'b0) begin
                                o_compressed_decoder_illegal_instr = 1'b1;
                            end
                        end
                    end
                    else begin
                        if (i_compressed_decoder_instr[11:2] == 5'b0) begin 
                            o_compressed_decoder_instr = {
                                32'h00_10_00_73
                            };
                        end
                        else if (i_compressed_decoder_instr[11:7] != 5'b0 && i_compressed_decoder_instr[6:2] == 5'b0) begin
                            o_compressed_decoder_illegal_instr = 1'b1;
                        end
                        else if (i_compressed_decoder_instr[11:2] != 5'b0) begin 
                            o_compressed_decoder_instr = {
                                7'b0,
                                i_compressed_decoder_instr[6:2],
                                i_compressed_decoder_instr[11:7],
                                3'b0,
                                i_compressed_decoder_instr[11:7],
                                7'b0110011
                            };
                        end
                        else begin
                            o_compressed_decoder_illegal_instr = 1'b1;
                        end
                    end
               end
                default: o_compressed_decoder_illegal_instr = 1'b1;
            endcase
       end
        default: begin
            o_compressed_decoder_is_compressed = 1'b0;
        end
    endcase

    // Illegal instruction handling
    if (o_compressed_decoder_illegal_instr) begin
        o_compressed_decoder_instr = i_compressed_decoder_instr;
    end
end

endmodule