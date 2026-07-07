module i_risc_v_div 
#(
    parameter XLEN = 32 
) 
(
    input  logic [XLEN-1 : 0]   i_div_in_srcA,
    input  logic [XLEN-1 : 0]   i_div_in_srcB,
    input  logic [1:0]          i_div_ctrl,
    output logic [2*XLEN-1 : 0] o_div_divindend,
    output logic [XLEN-1 : 0]   o_div_divisor
);

    logic [1:0] srcAsign_srcBsign;
    assign srcAsign_srcBsign = {i_div_in_srcA[XLEN-1] , i_div_in_srcB[XLEN-1]};

    logic [XLEN-1 : 0] i_div_in_srcA_comb;
    assign i_div_in_srcA_comb = ~i_div_in_srcA + 1;

    logic [XLEN-1 : 0] i_div_in_srcB_comb;
    assign i_div_in_srcB_comb = ~i_div_in_srcB + 1; 

    localparam DIV   = 2'b00 ;
    localparam DIVU  = 2'b01 ;
    localparam REM   = 2'b10 ;
    localparam REMU  = 2'b11 ;

    always_comb  begin
        case(i_div_ctrl)
            DIV:
                case(srcAsign_srcBsign)
                    2'b00:
                        begin
                            o_div_divindend = i_div_in_srcA;
                            o_div_divisor   = i_div_in_srcB;
                        end
                    2'b01:
                        begin
                            o_div_divindend = i_div_in_srcA;
                            o_div_divisor   = i_div_in_srcB_comb;
                        end
                    2'b10:
                        begin
                            o_div_divindend = i_div_in_srcA_comb;
                            o_div_divisor   = i_div_in_srcA;
                        end
                    2'b11:
                        begin
                            o_div_divindend = i_div_in_srcA_comb;
                            o_div_divisor   = i_div_in_srcB_comb;
                        end
                endcase
            DIVU:
                begin
                    o_div_divindend = i_div_in_srcA;
                    o_div_divisor   = i_div_in_srcB;
                end 
            REM:
                case(srcAsign_srcBsign)
                    2'b00:
                        begin
                            o_div_divindend = i_div_in_srcA;
                            o_div_divisor = i_div_in_srcB;
                        end
                    2'b01:
                        begin
                            o_div_divindend = i_div_in_srcA;
                            o_div_divisor = i_div_in_srcB_comb;
                        end 
                    2'b10:
                        begin
                            o_div_divindend = i_div_in_srcA_comb;
                            o_div_divisor = i_div_in_srcB;
                        end
                    2'b11:
                        begin
                            o_div_divindend = i_div_in_srcA_comb;
                            o_div_divisor = i_div_in_srcB_comb;
                        end
                endcase
            REMU:
                begin
                    o_div_divindend = i_div_in_srcA;
                    o_div_divisor = i_div_in_srcB;
                end
        endcase
    end
endmodule
            















    
    
