module Hazard_Unit(
    input logic [4:0] Rs1E, Rs2E, RdM, RdW,
    input logic RegWriteM, RegWriteW,
    input logic ResultSrcE_0, 
    input logic [4:0] RdE,
    input logic [4:0] Rs1D, Rs2D,
    input logic PCSrcE,

    output logic FlushE, StallD, StallF,
    output logic [1:0] ForwardAE, ForwardBE,
    output logic FlushD
);

logic lwStall;

always @(*) begin
    if (((Rs1E == RdM) & (RegWriteM)) & (Rs1E != 0)) // Forward from Memory stage
        ForwardAE = 2'b10;
    else if (((Rs1E == RdW) & (RegWriteW)) & (Rs1E != 0)) // Forward from Writeback stage
        ForwardAE = 2'b01;
    else 
        ForwardAE = 2'b00;
    //

     if (((Rs2E == RdM) & (RegWriteM)) & (Rs2E != 0)) // Forward from Memory stage
        ForwardBE = 2'b10;
    else if (((Rs2E == RdW) & (RegWriteW)) & (Rs2E != 0)) // Forward from Writeback stage
        ForwardBE = 2'b01;
    else 
        ForwardBE = 2'b00;
    //


    lwStall = ResultSrcE_0 & ((Rs1D == RdE) | (Rs2D == RdE));
    StallF = lwStall; 
    StallD = lwStall;
    FlushD = PCSrcE;
    FlushE = lwStall | PCSrcE;
end


endmodule