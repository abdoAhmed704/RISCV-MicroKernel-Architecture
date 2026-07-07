module risc_v_mul_div_ctrl #(
    parameter XLEN = 32
) (
    input  logic i_mul_div_ctrl_clk,
    input  logic i_mul_div_ctrl_rstn,
    input  logic i_mul_div_ctrl_en,
    input  logic i_mul_div_ctrl_div_dne,
    input  logic i_mul_div_ctrl_mul_dne,
    input  logic [2:0] i_mul_div_ctrl_funct_3,
    input  logic [XLEN-1 : 0] i_mul_div_ctrl_srcA,
    input  logic [XLEN-1 : 0] i_mul_div_ctrl_srcB,
    output logic o_mul_div_ctrl_mul_start,
    output logic o_mul_div_ctrl_div_start,
    output logic o_mul_div_ctrl_dne,
    output logic o_mul_div_ctrl_busy,
    output logic o_mul_div_ctrl_overflow,
    output logic o_mul_div_ctrl_div_by_zero,
    output logic o_mul_div_ctrl_selector_btween_mul_div,
    output logic o_mul_div_ctrl_selector_btween_fast_MulDiv,
    output logic [XLEN-1 : 0] o_mul_div_ctrl_fast_rslt
);


typedef enum logic [1:0] { IDLE , FAST , MUL , DIV } STATE;
STATE cs_state , ns_state;

logic [XLEN-1 : 0] fast_out;
logic [7:0]        fast_register;
logic              fast_sel; //control signal for mux
logic              divbyzero;
logic              overflow;

assign fast_register = 
{
                        i_mul_div_ctrl_srcB==-1,
                        i_mul_div_ctrl_srcB==1,
                        i_mul_div_ctrl_srcB==0,
                        i_mul_div_ctrl_srcA==-1,
                        i_mul_div_ctrl_srcA==1,
                        i_mul_div_ctrl_srcA==0,
                        (i_mul_div_ctrl_srcA == {1'b1,{(XLEN-1){1'b0}}}) && (i_mul_div_ctrl_srcB == -1) && (i_mul_div_ctrl_funct_3 == 3'b1x0)
};

/////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////    FAST LOGIC     ////////////////////////////////////////////

always_comb begin //fast logic
    casex (fast_register)
        7'b001_xxx_0:
            begin
                case(i_mul_div_ctrl_funct_3)
                    3'b000://mul
                        begin
                            fast_out = 0;
                            fast_sel = 1;
                        end
                    3'b101://divu
                        begin
                            fast_out = {XLEN{1'b1}};
                            divbyzero = 1;
                            fast_sel = 1;
                        end
                    3'b100://div
                        begin
                            fast_out = -1;
                            divbyzero =1;
                            fast_sel = 1;
                        end
                    3'b110://rem
                        begin
                            fast_out = i_mul_div_ctrl_srcA;
                            fast_sel = 1;
                        end
                    default:
                        begin
                            fast_out = 0;
                            fast_sel = 0;
                        end
                endcase
            end
        7'b100_000_1:
            begin
                if(i_mul_div_ctrl_funct_3==3'b100)
                    begin
                        fast_out = i_mul_div_ctrl_srcA;
                        overflow = 1;
                        fast_sel = 1;
                    end
                else 
                    begin
                        fast_out = 0;
                        fast_sel = 0;
                    end
            end
        7'b001_0xx_0:
            begin
                if(i_mul_div_ctrl_funct_3==3'b111)
                    begin
                        fast_out = i_mul_div_ctrl_srcA;
                        divbyzero = 1;
                        fast_sel = 1;
                    end 
                else
                    begin
                        fast_out = 0;
                        fast_sel = 0;
                    end
            end
        default: 
            begin
                fast_out  = 0;
                divbyzero = 0;
                overflow  = 0;
                fast_sel  = 0;
            end
    endcase
end
/////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////    CS LOGIC     ////////////////////////////////////////////

always_ff @(posedge i_mul_div_ctrl_clk or negedge i_mul_div_ctrl_rstn) begin  // CS logic
    if (!i_mul_div_ctrl_rstn) 
        begin
            cs_state <= IDLE;
        end 
    else 
        begin
            cs_state <= ns_state;
        end
end

/////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////    NS LOGIC     ////////////////////////////////////////////

always_comb begin // NS logic
    case(cs_state)
    IDLE:
        begin
            if(i_mul_div_ctrl_en && fast_sel)
                begin
                    ns_state = FAST;
                    o_mul_div_ctrl_busy = 0;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 0;
                end
            else if(i_mul_div_ctrl_en && (!i_mul_div_ctrl_funct_3[2]))
                begin
                    ns_state = MUL;
                    o_mul_div_ctrl_busy = 1;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 1;
                end
            else if(i_mul_div_ctrl_en && (i_mul_div_ctrl_funct_3[2]))
                begin
                    ns_state = DIV;
                    o_mul_div_ctrl_busy = 1;
                    o_mul_div_ctrl_div_start = 1;
                    o_mul_div_ctrl_mul_start = 0;
                end
            else
                begin
                    ns_state = IDLE;
                    o_mul_div_ctrl_busy = 0;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 0; 
                end
        end
    FAST:
        begin
                begin
                    ns_state = IDLE;
                    o_mul_div_ctrl_busy = 0;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 0;
                end
        end
    MUL:
        begin
            if(i_mul_div_ctrl_mul_dne)
                begin
                    ns_state = IDLE;
                    o_mul_div_ctrl_busy = 0;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 0;
                end
            else
                begin
                    ns_state = MUL;
                    o_mul_div_ctrl_busy = 1;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 1;
                end
        end
    DIV:
        begin
            if(i_mul_div_ctrl_div_dne)
                begin
                    ns_state = IDLE;
                    o_mul_div_ctrl_busy = 0;
                    o_mul_div_ctrl_div_start = 0;
                    o_mul_div_ctrl_mul_start = 0;
                end
            else
                begin
                    ns_state = DIV;
                    o_mul_div_ctrl_busy = 1;
                    o_mul_div_ctrl_div_start = 1;
                    o_mul_div_ctrl_mul_start = 0;
                end
        end
    default:
        begin
            ns_state = IDLE;
            o_mul_div_ctrl_busy = 0;
            o_mul_div_ctrl_div_start = 0;
            o_mul_div_ctrl_mul_start = 0;
        end
    endcase                    
end

/////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////    OUTPUT LOGIC     ////////////////////////////////////////////

always_comb begin
    case(cs_state)
    IDLE:
        begin
            o_mul_div_ctrl_overflow = 0;
            o_mul_div_ctrl_div_by_zero = 0;
            o_mul_div_ctrl_fast_rslt = 0;
            o_mul_div_ctrl_dne = 0;
        end
    FAST:
        begin
            o_mul_div_ctrl_overflow = overflow;
            o_mul_div_ctrl_div_by_zero = divbyzero;
            o_mul_div_ctrl_fast_rslt = fast_out;
            o_mul_div_ctrl_dne = 1;
        end
    MUL:
        if(i_mul_div_ctrl_mul_dne)
            begin
                o_mul_div_ctrl_overflow = 0;
                o_mul_div_ctrl_div_by_zero = 0;
                o_mul_div_ctrl_fast_rslt = 0;
                o_mul_div_ctrl_dne = 1;
            end
        else
            begin
                o_mul_div_ctrl_overflow = 0;
                o_mul_div_ctrl_div_by_zero = 0;
                o_mul_div_ctrl_fast_rslt = 0;
                o_mul_div_ctrl_dne = 0;
            end
    DIV:
        if(i_mul_div_ctrl_div_dne)
            begin
                o_mul_div_ctrl_overflow = 0;
                o_mul_div_ctrl_div_by_zero = 0;
                o_mul_div_ctrl_fast_rslt = 0;
                o_mul_div_ctrl_dne = 1;
            end
        else
            begin
                o_mul_div_ctrl_overflow = 0;
                o_mul_div_ctrl_div_by_zero = 0;
                o_mul_div_ctrl_fast_rslt = 0;
                o_mul_div_ctrl_dne = 0;
            end
    default:
        begin
            o_mul_div_ctrl_overflow = 0;
            o_mul_div_ctrl_div_by_zero = 0;
            o_mul_div_ctrl_fast_rslt = 0;
            o_mul_div_ctrl_dne = 0;
        end
    endcase
end

assign o_mul_div_ctrl_selector_btween_mul_div = i_mul_div_ctrl_funct_3[2] ;
assign o_mul_div_ctrl_selector_btween_fast_MulDiv = fast_sel ;

endmodule