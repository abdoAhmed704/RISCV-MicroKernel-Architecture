module Risc_core_mul_in
#(
    parameter XLEN = 32
)
(
    input  logic [XLEN-1 : 0] i_mul_in_srcA,
    input  logic [XLEN-1 : 0] i_mul_in_srcB,
    input  logic [1:0]        i_mul_in_ctrl,
    output logic [XLEN-1 : 0] o_mul_in_multiplier,
    output logic [XLEN-1 : 0] o_mul_in_multiplicand 
);

logic [XLEN-1 : 0] i_mul_in_srcA_comb;
logic [XLEN-1 : 0] i_mul_in_srcB_comb;
logic [1:0]i_mul_in_sign;

localparam MUL    = 2'b00;      //   signed (multiplicand)rs1 *   signed (multiplier)rs2
localparam MULH   = 2'b01;      //   signed (multiplicand)rs1 *   signed (multiplier)rs2
localparam MULHSU  = 2'b10;      //   signed (multiplicand)rs1 * unsigned (multiplier)rs2
localparam MULHU = 2'b11;      // unsigned (multiplicand)rs1 * unsigned (multiplier)rs2

assign i_mul_in_srcA_comb = ~i_mul_in_srcA + 1'b1;
assign i_mul_in_srcB_comb = ~i_mul_in_srcB + 1'b1;

assign i_mul_in_sign = {i_mul_in_srcA[XLEN-1] , i_mul_in_srcB[XLEN-1]};

always_comb begin : multiplication_cases
    case(i_mul_in_ctrl)

        MUL:
            begin
                case(i_mul_in_sign)
                    0:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB ;
                        end
                    1:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB_comb ;
                        end
                    2:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA_comb ;
                            o_mul_in_multiplier   = i_mul_in_srcB ; 
                        end
                    3:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA_comb ;
                            o_mul_in_multiplier   = i_mul_in_srcB_comb ;
                        end
                endcase
            end

        MULH:
            begin
                case(i_mul_in_sign)
                    0:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB ;
                        end
                    1:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB_comb ;
                        end
                    2:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA_comb ;
                            o_mul_in_multiplier   = i_mul_in_srcB ; 
                        end
                    3:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA_comb ;
                            o_mul_in_multiplier   = i_mul_in_srcB_comb ;
                        end
                endcase
            end
           
        MULHU:
            begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB ;
            end
            
        MULHSU:
            begin
                case(i_mul_in_sign)
                    0:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB ;
                        end
                    1:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA ;
                            o_mul_in_multiplier   = i_mul_in_srcB ;
                        end
                    2:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA_comb ;
                            o_mul_in_multiplier   = i_mul_in_srcB ; 
                        end
                    3:
                        begin
                            o_mul_in_multiplicand = i_mul_in_srcA_comb ;
                            o_mul_in_multiplier   = i_mul_in_srcB ;
                        end
                endcase
            end
    endcase

end
endmodule