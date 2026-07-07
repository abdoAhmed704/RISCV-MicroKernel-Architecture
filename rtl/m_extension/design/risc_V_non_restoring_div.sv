module RISC_V_non_restoring_div
#(
    parameter XLEN = 32
)
(
    input  logic start_from_majoar_FSM,
    input  logic non_restoring_clk,
    input  logic non_restoring_rstn,
    input  logic [XLEN-1 : 0] dividend,
    input  logic [XLEN-1 : 0] divisor,
    output logic [XLEN-1 : 0] non_restoring_Qoutient,
    output logic [XLEN-1 : 0] non_restoring_remainder,
    output logic non_restoring_div_dne_for_major_machine
);

typedef enum logic {IDLE , DIV} state;
state CS_state,NS_state;

logic CS_dividend_sign ,NS_dividend_sign;
logic CS_divisor_sign  ,NS_divisor_sign;

logic [XLEN-1 : 0]     CS_Qotient,NS_Qotient;
logic [XLEN-1 : 0]     CS_accum,NS_accum;
logic [$clog2(XLEN):0] CS_counter,NS_counter;

always_ff @(posedge non_restoring_clk or negedge non_restoring_rstn) begin
    if(! non_restoring_rstn)
        begin
            CS_state          <= IDLE ;
            CS_counter        <= XLEN;
            CS_accum          <= 0;
            CS_Qotient        <= dividend;
            CS_dividend_sign  <= 0;
            CS_divisor_sign   <= 0;
        end
    else 
        begin
            CS_state         <= NS_state;
            CS_counter       <= NS_counter;
            CS_accum         <= NS_accum;
            CS_Qotient       <= NS_Qotient;  
            CS_dividend_sign <= NS_dividend_sign;
            CS_divisor_sign  <= NS_divisor_sign;  
        end     
end

always_comb begin
    NS_state         = CS_state;
    NS_counter       = CS_counter;
    NS_accum         = CS_accum;
    NS_Qotient       = CS_Qotient;
    NS_dividend_sign = CS_dividend_sign;
    NS_divisor_sign  = CS_divisor_sign;

    case (CS_state)
        IDLE:
            begin
                NS_accum         = 0;
                NS_counter       = XLEN;
                NS_dividend_sign = 0;
                NS_divisor_sign  = 0;
                NS_Qotient       = dividend;

                if(start_from_majoar_FSM == 0)
                    NS_state = IDLE;
                else
                    NS_state = DIV;
            end
        DIV:
            begin
                non_restoring_div_dne_for_major_machine = 0;

                if(NS_dividend_sign == 0)
                    begin
                        {NS_dividend_sign , NS_accum , NS_Qotient} = {NS_dividend_sign , NS_accum , NS_Qotient} << 1 ;      // shift left
                        {NS_dividend_sign , NS_accum} = {NS_dividend_sign , NS_accum} + ~{NS_divisor_sign , divisor} + 1;   //A = A-x
                    end
                else
                    begin
                        {NS_dividend_sign , NS_accum , NS_Qotient} = {NS_dividend_sign , NS_accum , NS_Qotient} << 1 ;    // shift left 
                        {NS_dividend_sign , NS_accum} = {NS_dividend_sign , NS_accum} + {NS_divisor_sign , divisor} ;     // A = A + x
                    end

                if(NS_dividend_sign == 0)
                    NS_Qotient[0] = 1;
                else
                    NS_Qotient[0] = 0;

                NS_counter = NS_counter - 1;

                if(NS_counter == 0)
                    begin
                        if (NS_dividend_sign == 0)
                            begin
                                non_restoring_Qoutient = NS_Qotient;
                                non_restoring_remainder = NS_accum;
                                non_restoring_div_dne_for_major_machine = 1 ;
                                NS_state = IDLE;
                            end
                        else
                            begin
                                {NS_dividend_sign , NS_accum} = NS_accum + divisor;
                                non_restoring_Qoutient = NS_Qotient;
                                non_restoring_remainder = NS_accum;
                                non_restoring_div_dne_for_major_machine = 1 ;
                                NS_state = IDLE;
                            end
                    end
            end    
    endcase
end
endmodule