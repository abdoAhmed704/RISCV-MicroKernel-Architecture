module riscv_data_mem #(
    parameter DATA_WIDTH = 32, // Width of data
    parameter ADDR_WIDTH = 32, 
    parameter MEM_SIZE = 4096,
    parameter UART_ADDR = 32'h00003FF0,
    parameter PLATFORM_ADDR = 32'h00003FFC
)(
    input logic clk,
    input logic WriteEnable,
    input logic [2:0] funct3,
    input logic [DATA_WIDTH-1:0] WriteData,
    input logic [ADDR_WIDTH-1:0] Address,
    output logic [DATA_WIDTH-1:0] ReadData
);

    reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];

    initial begin
        for (int i = 0; i < MEM_SIZE; i++) memory[i] = 32'h0;
    end

    // ─── UART RX: Sequential file reader with cache ─────────────────────
    // Instead of opening the file on every combinational evaluation (thousands
    // of times per second), we poll the file every POLL_INTERVAL clock cycles
    // and cache the result. The CPU reads the cached value instantly.
    logic [7:0] uart_rx_cache;
    logic       uart_rx_valid;
    int         uart_poll_ctr;

    initial begin
        uart_rx_cache = 8'h00;
        uart_rx_valid = 1'b0;
        uart_poll_ctr = 0;
    end

    always @(posedge clk) begin
        uart_poll_ctr <= uart_poll_ctr + 1;

        // Priority 1: If the CPU just read from UART, consume the cached byte
        if (!WriteEnable && Address == UART_ADDR && uart_rx_valid) begin
            uart_rx_valid <= 1'b0;
            uart_rx_cache <= 8'h00;
        end
        // Priority 2: Poll the input file every 5000 cycles when cache is empty
        else if (uart_poll_ctr >= 5000 && !uart_rx_valid) begin
            uart_poll_ctr <= 0;
            begin
                integer fd, ch, clear_fd;
                fd = $fopen("sw/input.txt", "r");
                if (fd == 0) begin
                    fd = $fopen("../../sw/input.txt", "r");
                end
                if (fd != 0) begin
                    ch = $fgetc(fd);
                    $fclose(fd);
                    if (ch >= 0) begin
                        uart_rx_cache <= ch[7:0];
                        uart_rx_valid <= 1'b1;
                        clear_fd = $fopen("sw/input.txt", "w");
                        if (clear_fd == 0) begin
                            clear_fd = $fopen("../../sw/input.txt", "w");
                        end
                        if (clear_fd != 0) $fclose(clear_fd);
                    end
                end
            end
        end
    end
    // ─────────────────────────────────────────────────────────────────────

    logic [31:0] selected_word;
    assign selected_word = memory[Address[ADDR_WIDTH-1:2]];

    always_comb begin
        if (Address == UART_ADDR) begin
            // Return cached UART byte (no file I/O here!)
            ReadData = {24'b0, uart_rx_cache};
        end else if (Address == PLATFORM_ADDR) begin
            // Return 'QUES' (0x51554553) for the hardware core in Questa
            ReadData = 32'h51554553;
        end else begin
            case (funct3)
                3'b000: begin // LOAD BYTE (signed)
                    case (Address[1:0])
                        2'b00: ReadData = {{24{selected_word[7]}}, selected_word[7:0]};
                        2'b01: ReadData = {{24{selected_word[15]}}, selected_word[15:8]};
                        2'b10: ReadData = {{24{selected_word[23]}}, selected_word[23:16]};
                        2'b11: ReadData = {{24{selected_word[31]}}, selected_word[31:24]};
                    endcase
                end
                3'b001: begin // LOAD HALF (signed)
                    case (Address[1])
                        1'b0: ReadData = {{16{selected_word[15]}}, selected_word[15:0]};
                        1'b1: ReadData = {{16{selected_word[31]}}, selected_word[31:16]};
                    endcase
                end
                3'b010: ReadData = selected_word; // LOAD WORD LW
                3'b100: begin // LOAD BYTE U (unsigned)
                    case (Address[1:0])
                        2'b00: ReadData = {24'b0, selected_word[7:0]};
                        2'b01: ReadData = {24'b0, selected_word[15:8]};
                        2'b10: ReadData = {24'b0, selected_word[23:16]};
                        2'b11: ReadData = {24'b0, selected_word[31:24]};
                    endcase
                end
                3'b101: begin // LOAD HALF U (unsigned)
                    case (Address[1])
                        1'b0: ReadData = {16'b0, selected_word[15:0]};
                        1'b1: ReadData = {16'b0, selected_word[31:16]};
                    endcase
                end
                default: ReadData = 32'b0;
            endcase
        end
    end 

    always @(posedge clk) begin
        if (WriteEnable) begin
            if (Address == UART_ADDR) begin
                $write("%c", WriteData[7:0]);
                $fflush();
            end else begin
                case (funct3)
                    3'b000: begin // STORE BYTE
                        case (Address[1:0])
                            2'b00: memory[Address[ADDR_WIDTH-1:2]][7:0]   <= WriteData[7:0];
                            2'b01: memory[Address[ADDR_WIDTH-1:2]][15:8]  <= WriteData[7:0];
                            2'b10: memory[Address[ADDR_WIDTH-1:2]][23:16] <= WriteData[7:0];
                            2'b11: memory[Address[ADDR_WIDTH-1:2]][31:24] <= WriteData[7:0];
                        endcase
                    end
                    3'b001: begin // STORE HALF
                        case (Address[1])
                            1'b0: memory[Address[ADDR_WIDTH-1:2]][15:0]  <= WriteData[15:0];
                            1'b1: memory[Address[ADDR_WIDTH-1:2]][31:16] <= WriteData[15:0];
                        endcase
                    end
                    3'b010: memory[Address[ADDR_WIDTH-1:2]] <= WriteData[31:0]; // STORE WORD
                    default: ; // Do nothing
                endcase
            end
        end
    end

endmodule

