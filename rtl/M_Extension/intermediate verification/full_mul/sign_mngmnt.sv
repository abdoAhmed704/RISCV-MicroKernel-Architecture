module sign_mngmnt 
(
    input logic i_signA,
    input logic i_signB,
    input logic i_rstn,
    input logic i_dne,
    input logic i_IDLE_flag,
    output logic o_signA,
    output logic o_signB
);

    logic signA_reg;
    logic signB_reg;

    assign signA_reg = i_signA;
    assign signB_reg = i_signB;

    always_latch begin
        if(!i_rstn || i_IDLE_flag)
            begin
                o_signA = i_signA;
                o_signB = i_signB;
            end
        else if(i_dne)
            begin
                o_signA = signA_reg;
                o_signB = signB_reg;
            end
    end
endmodule
