module();
    // testbech for input_reg
    // Signal Declaration
    wire [3:0] data;
    wire [3:0] data_address;
    wire [3:0] pc;
    reg [3:0] data_mem;

    // Module Declaration
    input_reg input_dui(
        .data(data),
        .data_address(data_address),
        .pc(pc),
        .data_mem(data_mem)
    );

    // test signals
    initial begin
        address = 0;
        pc = 0;
        data = A;
        #1;
        address = 1;
        pc = 1;
        data = 1;
        #1;
        address = A;
        pc = A;
        data = 3;
        #1;

        $stop;
    end
endmodule