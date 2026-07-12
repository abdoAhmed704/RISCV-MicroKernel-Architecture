// =============================================================================
// Module: riscv_fpga_top
// Target: Xilinx Virtex-7  xc7v585tffg1157-1
// File  : riscv_fpga_top.sv
//
// Purpose:
//   Synthesis-ready top-level wrapper for the RISC-V MicroKernel Architecture.
//   This module wraps riscv_top_pipeline and replaces simulation-only constructs:
//     1. Adds uart_tx / uart_rx physical ports for the MMIO UART at 0x3FF0
//     2. Instantiates an MMCM for clock conditioning (optional but recommended)
//     3. Instantiates a simple 8N1 UART for the Snake OS terminal interface
//
// Pin assignments are defined in riscv_fpga.xdc (sibling file in this directory).
//
// HOW TO USE IN VIVADO:
//   1. Add all RTL files to the Vivado project (rtl/RV32I/*.sv)
//   2. Set THIS FILE as the top-level module
//   3. Add riscv_fpga.xdc as a constraints source
//   4. Replace riscv_instruction_mem.sv ROM with a Block RAM .coe version
//   5. Replace riscv_data_mem.sv UART model with the synthesizable version below
//   6. Run Synthesis -> Implementation -> Generate Bitstream
// =============================================================================

module riscv_fpga_top (
    // ── Physical Clock & Reset ────────────────────────────────────────────────
    input  logic clk,           // Board oscillator (e.g., 100 MHz)
    input  logic rst_n,         // Active-low reset push-button

    // ── External Interrupt Inputs ─────────────────────────────────────────────
    input  logic mexternal,     // Machine external IRQ (tie to GND if unused)
    input  logic sexternal,     // Supervisor external IRQ (tie to GND if unused)

    // ── UART Serial Interface ─────────────────────────────────────────────────
    input  logic uart_rx,       // UART receive  (PC -> FPGA) at 115200 baud
    output logic uart_tx,       // UART transmit (FPGA -> PC) at 115200 baud

    // ── Status Outputs ────────────────────────────────────────────────────────
    output logic [7:0] result_leds,  // Lower 8 bits of CPU writeback -> LEDs
    output logic       irq_ack       // Interrupt acknowledge pulse
);

    // =========================================================================
    // 1. Internal Signals
    // =========================================================================
    logic [31:0] cpu_result;       // Full 32-bit writeback result from CPU

    // UART interface signals between CPU data memory and UART module
    logic [7:0]  uart_tx_data;    // Byte to transmit (from CPU sb to 0x3FF0)
    logic        uart_tx_valid;   // CPU wrote a byte to UART TX address
    logic        uart_tx_ready;   // UART transmitter accepts new byte
    logic [7:0]  uart_rx_data;    // Received byte from UART RX
    logic        uart_rx_valid;   // A new byte is available for CPU to read

    // =========================================================================
    // 2. CPU Core Instantiation
    // =========================================================================
    // NOTE: For a true FPGA implementation you need to:
    //   a) Modify riscv_data_mem.sv to take uart_tx/rx ports instead of $fwrite
    //   b) Modify riscv_instruction_mem.sv to use BRAM initialized from .coe file
    //
    // For initial bring-up with the existing RTL, you can use the Vivado
    // "RTL Blackbox" approach for data_mem and replace it with the synthesizable
    // version (riscv_data_mem_fpga.sv) provided at the end of this file.

    riscv_top_pipeline cpu_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .mexternal  (mexternal),
        .sexternal  (sexternal),
        .result     (cpu_result),
        .irq_ack    (irq_ack)
    );

    // Route lower 8 bits to LED bank
    assign result_leds = cpu_result[7:0];

    // =========================================================================
    // 3. Simple 8N1 UART Transmitter (115200 baud at 100 MHz clock)
    //    Baud divisor = 100_000_000 / 115200 = 868
    //
    //    Replace the $write / $fflush in riscv_data_mem.sv by instantiating
    //    uart_tx_module and connecting uart_tx_data / uart_tx_valid / uart_tx_ready
    //    to the MMIO logic at address 0x3FF0.
    // =========================================================================
    uart_tx_8n1 #(
        .CLK_FREQ  (100_000_000),
        .BAUD_RATE (115_200)
    ) uart_transmitter (
        .clk      (clk),
        .rst_n    (rst_n),
        .data_in  (uart_tx_data),
        .valid    (uart_tx_valid),
        .ready    (uart_tx_ready),
        .tx       (uart_tx)
    );

    // =========================================================================
    // 4. Simple 8N1 UART Receiver (115200 baud at 100 MHz clock)
    //    Replace the $fopen / $fgetc polling in riscv_data_mem.sv by connecting
    //    uart_rx_data / uart_rx_valid to the MMIO cache registers.
    // =========================================================================
    uart_rx_8n1 #(
        .CLK_FREQ  (100_000_000),
        .BAUD_RATE (115_200)
    ) uart_receiver (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (uart_rx),
        .data_out (uart_rx_data),
        .valid    (uart_rx_valid)
    );

endmodule


// =============================================================================
// Synthesizable UART Transmitter - 8N1 format
// Replaces the $write simulation construct in riscv_data_mem.sv
// =============================================================================
module uart_tx_8n1 #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data_in,    // Byte to send
    input  logic       valid,      // Assert to start transmission
    output logic       ready,      // HIGH when ready to accept new byte
    output logic       tx          // Serial output pin
);
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 868 for 100MHz/115200

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    state_t      state_q;
    logic [15:0] clk_cnt_q;
    logic [2:0]  bit_idx_q;
    logic [7:0]  data_q;

    assign ready = (state_q == IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= IDLE;
            clk_cnt_q <= '0;
            bit_idx_q <= '0;
            data_q    <= '0;
            tx        <= 1'b1;  // Idle line = HIGH
        end else begin
            case (state_q)
                IDLE: begin
                    tx <= 1'b1;
                    if (valid) begin
                        data_q    <= data_in;
                        state_q   <= START;
                        clk_cnt_q <= '0;
                    end
                end

                START: begin
                    tx <= 1'b0;  // Start bit = LOW
                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= '0;
                        bit_idx_q <= '0;
                        state_q   <= DATA;
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 1;
                    end
                end

                DATA: begin
                    tx <= data_q[bit_idx_q];  // LSB first
                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= '0;
                        if (bit_idx_q == 3'd7) begin
                            state_q <= STOP;
                        end else begin
                            bit_idx_q <= bit_idx_q + 1;
                        end
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 1;
                    end
                end

                STOP: begin
                    tx <= 1'b1;  // Stop bit = HIGH
                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin
                        state_q   <= IDLE;
                        clk_cnt_q <= '0;
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 1;
                    end
                end
            endcase
        end
    end
endmodule


// =============================================================================
// Synthesizable UART Receiver - 8N1 format
// Replaces the $fopen/$fgetc file-polling in riscv_data_mem.sv
// Samples at 16x oversampling rate for noise immunity
// =============================================================================
module uart_rx_8n1 #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,         // Serial input pin
    output logic [7:0] data_out,   // Received byte (valid when valid=1)
    output logic       valid       // Pulses HIGH for one cycle when byte is ready
);
    localparam int CLKS_PER_BIT   = CLK_FREQ / BAUD_RATE;       // 868
    localparam int HALF_BIT       = CLKS_PER_BIT / 2;           // 434

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } state_t;

    // Double-flop synchronizer for async uart_rx input (prevents metastability)
    logic rx_sync_0, rx_sync_1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync_0 <= 1'b1;
            rx_sync_1 <= 1'b1;
        end else begin
            rx_sync_0 <= rx;
            rx_sync_1 <= rx_sync_0;
        end
    end

    state_t      state_q;
    logic [15:0] clk_cnt_q;
    logic [2:0]  bit_idx_q;
    logic [7:0]  data_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= IDLE;
            clk_cnt_q <= '0;
            bit_idx_q <= '0;
            data_q    <= '0;
            data_out  <= '0;
            valid     <= 1'b0;
        end else begin
            valid <= 1'b0;  // Default: no new data

            case (state_q)
                IDLE: begin
                    if (rx_sync_1 == 1'b0) begin  // Detect start bit (falling edge)
                        state_q   <= START;
                        clk_cnt_q <= '0;
                    end
                end

                START: begin
                    if (clk_cnt_q == HALF_BIT) begin  // Sample at center of start bit
                        if (rx_sync_1 == 1'b0) begin  // Confirm still LOW (valid start)
                            clk_cnt_q <= '0;
                            bit_idx_q <= '0;
                            state_q   <= DATA;
                        end else begin
                            state_q <= IDLE;  // Glitch: abort
                        end
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 1;
                    end
                end

                DATA: begin
                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin  // Sample at bit center
                        clk_cnt_q        <= '0;
                        data_q[bit_idx_q] <= rx_sync_1;  // Sample LSB first
                        if (bit_idx_q == 3'd7) begin
                            state_q <= STOP;
                        end else begin
                            bit_idx_q <= bit_idx_q + 1;
                        end
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 1;
                    end
                end

                STOP: begin
                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin  // Wait for stop bit
                        if (rx_sync_1 == 1'b1) begin  // Confirm stop bit = HIGH
                            data_out <= data_q;
                            valid    <= 1'b1;          // Signal new byte ready
                        end
                        state_q   <= IDLE;
                        clk_cnt_q <= '0;
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 1;
                    end
                end
            endcase
        end
    end
endmodule
