module full_mul 
#(
    parameter XLEN = 32
) 
(
    input logic [XLEN-1 : 0] srcA,
    input logic [XLEN-1 : 0] srcB,
    input logic              clk,
    input logic              rstn,
    input logic              en,
    input logic [1:0]        fucnct3,
    output logic[XLEN-1 : 0] rslt,
    output logic             dne
);

//intermediate siganals
logic [XLEN-1 : 0] multiplier;
logic [XLEN-1 : 0] multiplicand;
logic [2*XLEN-1 : 0] product;
logic dne_wire; //i/p o/p
logic signBwire;
logic signAwire;
logic IDLE_wire;



Risc_core_mul_in
#(
    .XLEN(XLEN)
)
R1
(
    .i_mul_in_srcA(srcA),
    .i_mul_in_srcB(srcB),
    .i_mul_in_ctrl(fucnct3),
    .o_mul_in_multiplier(multiplier),
    .o_mul_in_multiplicand(multiplicand)
);

risc_v_core_Booth_product
#(
    .XLEN(XLEN) 
)
R2
(
    .i_booth_multiplicand(multiplicand),
    .i_booth_multiplier(multiplier),
    .i_booth_clk(clk),
    .i_booth_rstn(rstn),
    .i_booth_en(en),
    .o_booth_product(product),
    .o_booth_done(dne_wire),
    .o_IDLE_FLAG(IDLE_wire)
);


sign_mngmnt R4
(
    .i_signA(srcA[XLEN-1]),
    .i_signB(srcB[XLEN-1]),
    .i_rstn(rstn),
    .i_dne(dne_wire),
    .i_IDLE_flag(IDLE_wire),
    .o_signA(signAwire),
    .o_signB(signBwire)
);

Risc_core_mul_out
#(
    .XLEN(XLEN)
)
R3
(
    .i_mul_out_booth_product(product), // the result of the product is 2*XLEN
    .i_mul_out_srcAsign(signAwire),
    .i_mul_out_srcBsign(signBwire),
    .i_mul_out_ctrl(fucnct3),
    .o_mul_out_rslt(rslt)              // RISC dest only has XLEN bits
);

assign dne = dne_wire;

    
endmodule