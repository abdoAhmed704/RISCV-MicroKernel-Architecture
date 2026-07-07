module risc_v_core_Booth_product
#(
    parameter XLEN = 32 
)
(
    input  logic [XLEN-1 : 0]   i_booth_multiplicand,
    input  logic [XLEN-1 : 0]   i_booth_multiplier,
    input  logic                i_booth_clk,
    input  logic                i_booth_rstn,
    input  logic                i_booth_en,
    output logic [2*XLEN-1 : 0] o_booth_product,
    output logic                o_booth_done
);

typedef enum logic {IDLE , MUL} state;

state                      state_reg , nxt_state;
logic [XLEN-1 : 0]         CS_accum, NS_accum;
logic [XLEN-1 : 0]         CS_multiplier , NS_multiplier;
logic                      CS_Q_n_minus_one , NS_Q_n_minus_one;
logic [$clog2(XLEN) : 0] CS_counter,NS_counter;


always_ff @( posedge i_booth_clk , negedge i_booth_rstn ) begin 
    if (!(i_booth_rstn)) 
        begin
            state_reg        <= IDLE;
            CS_accum         <= 0;
            CS_multiplier    <= 0;
            CS_Q_n_minus_one <= 0;
            CS_counter       <= XLEN;
        end
    else 
        begin
            state_reg        <= nxt_state ;
            CS_accum         <= NS_accum ;
            CS_multiplier    <= NS_multiplier ;
            CS_Q_n_minus_one <= NS_Q_n_minus_one ;
            CS_counter       <= NS_counter;
        end
    
end

always_comb begin 

// basically this algorithm is a sequential circuit but as we implement it in combinational logic in this state machine we need to help the combinational circuit 
// remembers the old values and start from where it ends 
// i did it through the next 5 lines of codes

    nxt_state        = state_reg;
    NS_accum         = CS_accum;
    NS_multiplier    = CS_multiplier;
    NS_Q_n_minus_one = CS_Q_n_minus_one;
    NS_counter       = CS_counter;



    case(state_reg)
        IDLE:
            begin
                NS_multiplier    = i_booth_multiplier;
                NS_counter       = XLEN;
                NS_accum         = 0;
                NS_Q_n_minus_one = 0;
                o_booth_done     = 0;
                o_booth_product  = 0;

               if(i_booth_en)
                    nxt_state = MUL;
                else 
                    nxt_state = IDLE;
           end

        MUL:
            begin
    
                case ({NS_multiplier[0] , NS_Q_n_minus_one})
                2'b00 :
                    begin
                        {NS_accum , NS_multiplier , NS_Q_n_minus_one} = {CS_accum , CS_multiplier , CS_Q_n_minus_one} >> 1 ; 
                    end

                2'b01 :
                    begin
                        NS_accum = CS_accum + i_booth_multiplicand;
                        {NS_accum , NS_multiplier , NS_Q_n_minus_one} = {NS_accum , CS_multiplier , CS_Q_n_minus_one} >> 1 ; 
                    end

                2'b10 :
                    begin
                        NS_accum = CS_accum + ~(i_booth_multiplicand) + 1;
                        {NS_accum , NS_multiplier , NS_Q_n_minus_one} = {NS_accum , CS_multiplier , CS_Q_n_minus_one} >> 1 ; 
                    end

                2'b11 :
                    begin
                        {NS_accum , NS_multiplier , NS_Q_n_minus_one} = {CS_accum , CS_multiplier , CS_Q_n_minus_one} >> 1 ; 
                    end
                endcase 

                NS_counter = CS_counter - 1 ; 

                if(NS_counter == 0)
                    begin
                        o_booth_done    = 1;
                        o_booth_product = {NS_accum >> 1 , NS_multiplier}; // without the shift in this line the counter will count 32 time but only we get 31 shift
                        nxt_state       = IDLE ;
                    end
                else 
                    begin
                        o_booth_done    = 0;
                        o_booth_product = 0;
                        nxt_state       = MUL ;
                    end
            end
    endcase
        

end

endmodule