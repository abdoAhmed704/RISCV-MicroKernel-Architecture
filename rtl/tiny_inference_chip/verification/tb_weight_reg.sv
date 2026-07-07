module();
    // testbech for input_reg
    // Signal Declaration
    wire [3:0] weight;
    wire [3:0] weight_address;
    wire [3:0] pc;
    reg [3:0] weight_mem;

    // Module Declaration
    weight_reg weight_dui(
        .weight(weight),
        .weight_address(weight_address),
        .pc(pc),
        .weight_mem(weight_mem)
    );

    // test signals
    initial begin
        weight_address = 0;
        pc = 0;
        weight = 3;
        #1;
        weight_address = 1;
        pc = 1;
        weight = 5;
        #1;
        weight_address = A;
        pc = A;
        weight = C;
        #1;

        $stop;
    end
endmodule