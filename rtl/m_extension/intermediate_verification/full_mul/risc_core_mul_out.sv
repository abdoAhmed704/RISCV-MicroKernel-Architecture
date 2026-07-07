module Risc_core_mul_out
#(
    parameter XLEN = 32
)
(
input  logic [2*XLEN-1 : 0] i_mul_out_booth_product, // the result of the product is 2*XLEN
input  logic                i_mul_out_srcAsign,
input  logic                i_mul_out_srcBsign,
input  logic [1 : 0]        i_mul_out_ctrl,
output logic [XLEN-1 : 0]   o_mul_out_rslt              // RISC dest only has XLEN bits
);

logic [2*XLEN-1 : 0] i_mul_out_booth_product_comb;
assign i_mul_out_booth_product_comb = ~i_mul_out_booth_product + 1'b1;

localparam MUL    = 2'b00;      //   signed (multiplicand)rs1 *   signed (multiplier)rs2
localparam MULH   = 2'b01;      //   signed (multiplicand)rs1 *   signed (multiplier)rs2
localparam MULHSU  = 2'b10;      //   signed (multiplicand)rs1 * unsigned (multiplier)rs2
localparam MULHU = 2'b11;      // unsigned (multiplicand)rs1 * unsigned (multiplier)rs2

always_comb begin : final_result
    case(i_mul_out_ctrl)
        MUL:
            begin
                if(i_mul_out_srcAsign ^ i_mul_out_srcBsign)
                    begin
                        o_mul_out_rslt = i_mul_out_booth_product_comb[XLEN-1:0];
                    end
                else
                    begin
                        o_mul_out_rslt = i_mul_out_booth_product[XLEN-1 : 0];
                    end
            end

        MULH : 
            begin
                if(i_mul_out_srcAsign ^ i_mul_out_srcBsign)
                    begin
                        o_mul_out_rslt = i_mul_out_booth_product_comb[2*XLEN-1 : XLEN];
                    end
                else 
                    begin
                        o_mul_out_rslt = i_mul_out_booth_product[2*XLEN-1 : XLEN];
                    end
            end
            
        MULHU :
            begin
                o_mul_out_rslt = i_mul_out_booth_product[2*XLEN-1 : XLEN];
            end

        MULHSU :
            begin
                if(i_mul_out_srcAsign)
                    begin
                        o_mul_out_rslt = i_mul_out_booth_product_comb[2*XLEN-1 : XLEN];
                    end
                else
                    begin
                        o_mul_out_rslt = i_mul_out_booth_product[2*XLEN-1 : XLEN];
                    end
            end
    endcase
    
end
endmodule
