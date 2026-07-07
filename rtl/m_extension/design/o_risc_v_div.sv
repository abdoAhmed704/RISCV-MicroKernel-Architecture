module o_risc_v_div
#(
    parameter XLEN = 32
)
(
    input  logic [1:0]        o_div_ctrl,
    input  logic              o_srcAsing, //dividend
    input  logic              o_srcBsign, //divisor
    input  logic [XLEN-1 : 0] o_div_rem,
    input  logic [XLEN-1 : 0] o_div_Qoutient,
    output logic [XLEN-1 : 0] o_div_result
);

    logic Quotient_sign_testing;
    assign Quotient_sign_testing = o_srcAsing ^ o_srcBsign; 

    localparam DIV  = 2'b00;
    localparam DIVU = 2'b01;
    localparam REM  = 2'b10;
    localparam REMU = 2'b11;

    always_comb begin
        case(o_div_ctrl)
            DIV:
                begin
                    if (Quotient_sign_testing == 1'b1 )
                        o_div_result = ~o_div_Qoutient + 1;
                    else 
                        o_div_result = o_div_Qoutient;
                end
            DIVU:
                begin
                    o_div_result = o_div_Qoutient;
                end
            REM:
                begin
                    if(o_srcAsing == 1)
                        o_div_result = ~o_div_rem + 1;
                    else
                        o_div_result = o_div_rem;
                end
            REMU:
                begin
                    o_div_result = o_div_rem;
                end
        endcase                
    end
endmodule