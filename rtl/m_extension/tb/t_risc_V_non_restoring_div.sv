module T_RISC_V_non_restoring_div();

    parameter XLEN = 32;

    logic start_from_majoar_FSM;
    logic non_restoring_clk;
    logic non_restoring_rstn;
    logic [XLEN-1 : 0] dividend;
    logic [XLEN-1 : 0] divisor;
    logic [XLEN-1 : 0] non_restoring_Qoutient;
    logic [XLEN-1 : 0] non_restoring_remainder;
    logic non_restoring_div_dne_for_major_machine;

    RISC_V_non_restoring_div
    #(
        .XLEN(XLEN)
    )
    DIV_1
    (
        .start_from_majoar_FSM(start_from_majoar_FSM),
        .non_restoring_clk(non_restoring_clk),
        .non_restoring_rstn(non_restoring_rstn),
        .dividend(dividend),
        .divisor(divisor),
        .non_restoring_Qoutient(non_restoring_Qoutient),
        .non_restoring_remainder(non_restoring_remainder),
        .non_restoring_div_dne_for_major_machine(non_restoring_div_dne_for_major_machine)
    );

    initial 
        begin
            non_restoring_clk = 0;
            forever begin
                #5;
                non_restoring_clk = ~non_restoring_clk;
            end
        end

    initial begin
        #1000 $finish;
    end

    initial begin
        dividend = 12;
        divisor = 3;

        non_restoring_rstn = 0;
        #10;
        non_restoring_rstn = 1;
        #10;
         non_restoring_rstn = 0;
        #10;
        non_restoring_rstn = 1;
        #10;

        start_from_majoar_FSM = 0;

        #10;

        start_from_majoar_FSM = 1;

    end
endmodule


