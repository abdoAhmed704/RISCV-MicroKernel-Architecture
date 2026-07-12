##==============================================================================
## Project : RISC-V MicroKernel Architecture
## Target  : Xilinx Virtex-7  xc7v585tffg1157-1
## File    : riscv_fpga.xdc
## Purpose : Physical I/O and timing constraints for FPGA implementation
##
## IMPORTANT: xc7v585tffg1157-1 is a bare FPGA in the 1157-pin BGA package.
## Pin assignments depend entirely on YOUR PCB/BOARD schematic.
##
## INSTRUCTIONS:
##   1. Replace every <BOARD_PIN_xxx> placeholder with the actual pad name
##      from your board schematic (e.g., AA8, K19, AB12, ...).
##   2. Match IOSTANDARD to the VCCO voltage of the bank on your board.
##      HP banks (14,15,24,25,34,35) -> typically 1.8V -> LVCMOS18
##      HR banks (12,13,16,32,33,36) -> typically 3.3V -> LVCMOS33
##   3. After synthesis in Vivado: Open Synthesized Design -> I/O Planning
##      view to visualize banks and pick valid clock-capable pins.
##   4. Run Report Timing Summary after implementation to verify closure.
##
## FFG1157 Package Quick Reference (UG475):
##   Total user I/O  : ~600 pins across HR and HP banks
##   HP banks (1.8V) : 14, 15, 24, 25, 34, 35
##   HR banks (3.3V) : 12, 13, 16, 32, 33, 36
##   Each bank       : 2x MRCC differential pairs + 2x SRCC pairs
##   GTX transceivers: Quads 112-119, 216-219 (for high-speed serial)
##==============================================================================


##==============================================================================
## SECTION 1 : SYSTEM CLOCK
##
## You MUST connect the clock to a Clock-Capable (MRCC or SRCC) pin.
## In Vivado I/O Planner these pins are shown with a hexagon symbol.
##
## Example MRCC pins in FFG1157 package (verify with your board schematic):
##   Bank 13 MRCC_P: IO_L12P_T1_MRCC_13  -> common for 3.3V clock input
##   Bank 14 MRCC_P: IO_L12P_T1_MRCC_14  -> common for 1.8V clock input
##   Bank 33 MRCC_P: IO_L12P_T1_MRCC_33  -> common for 3.3V clock input
##==============================================================================

## System clock (single-ended, e.g., 100 MHz oscillator on board)
set_property PACKAGE_PIN  <BOARD_PIN_CLK>    [get_ports clk]
set_property IOSTANDARD   LVCMOS33            [get_ports clk]

## Primary timing constraint: 100 MHz (10.000 ns period)
## Adjust the period to match your board oscillator frequency.
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

## Alternative: Differential LVDS clock (uncomment if board uses diff clock)
## set_property PACKAGE_PIN  <BOARD_PIN_CLK_P>   [get_ports clk_p]
## set_property PACKAGE_PIN  <BOARD_PIN_CLK_N>   [get_ports clk_n]
## set_property IOSTANDARD   LVDS_25              [get_ports clk_p]
## set_property IOSTANDARD   LVDS_25              [get_ports clk_n]
## create_clock -period 10.000 -name sys_clk [get_ports clk_p]


##==============================================================================
## SECTION 2 : RESET (active-low)
##
## rst_n is the global synchronous active-low reset for the entire CPU.
## Connect to a push-button (active-low with pull-up) or power-on-reset IC.
## The button signal is treated as asynchronous (false path).
##==============================================================================

set_property PACKAGE_PIN  <BOARD_PIN_RST_N>    [get_ports rst_n]
set_property IOSTANDARD   LVCMOS33              [get_ports rst_n]
set_property PULLUP       TRUE                  [get_ports rst_n]

## Reset is asynchronous to clock domain; declare as false path to avoid
## incorrect timing violations on the reset net
set_false_path -from [get_ports rst_n]


##==============================================================================
## SECTION 3 : EXTERNAL INTERRUPT INPUTS
##
## mexternal : Machine external interrupt (tie to GND if not used)
## sexternal : Supervisor external interrupt (tie to GND if not used)
##
## In the top module these default to 1'b0 so they can be left unconnected
## in simulation. For FPGA, connect to buttons, GPIO expander, or PLIC output.
##==============================================================================

set_property PACKAGE_PIN  <BOARD_PIN_MEXT>     [get_ports mexternal]
set_property IOSTANDARD   LVCMOS33              [get_ports mexternal]
set_property PULLDOWN     TRUE                  [get_ports mexternal]

set_property PACKAGE_PIN  <BOARD_PIN_SEXT>     [get_ports sexternal]
set_property IOSTANDARD   LVCMOS33              [get_ports sexternal]
set_property PULLDOWN     TRUE                  [get_ports sexternal]

## External interrupts are asynchronous to the CPU clock
set_false_path -from [get_ports mexternal]
set_false_path -from [get_ports sexternal]


##==============================================================================
## SECTION 4 : UART SERIAL INTERFACE
##
## The RISC-V Snake OS uses a memory-mapped UART at 0x3FF0.
## For FPGA: the simulation $fwrite/$fgetc model in riscv_data_mem.sv must be
## replaced with a synthesizable UART RTL module. See Section 10 for details.
##
## Standard 8N1 UART at 115200 baud connected to USB-UART bridge on board.
##   uart_tx : FPGA transmits -> host PC receives
##   uart_rx : host PC transmits -> FPGA receives
##==============================================================================

## UART Transmit output (CPU character output to terminal)
set_property PACKAGE_PIN  <BOARD_PIN_UART_TX>  [get_ports uart_tx]
set_property IOSTANDARD   LVCMOS33              [get_ports uart_tx]
set_property DRIVE        8                     [get_ports uart_tx]
set_property SLEW         SLOW                  [get_ports uart_tx]

## UART Receive input (host PC keyboard input to CPU)
set_property PACKAGE_PIN  <BOARD_PIN_UART_RX>  [get_ports uart_rx]
set_property IOSTANDARD   LVCMOS33              [get_ports uart_rx]

## UART signals cross async domain -> declare false paths
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports uart_tx]


##==============================================================================
## SECTION 5 : RESULT OUTPUT BUS (32-bit CPU writeback)
##
## result[31:0] is the CPU register writeback data bus exposed at top-level.
## For FPGA observation, connect lower bits to LEDs or a logic analyzer header.
##
## Below: result[7:0] mapped to 8 status LEDs (common on Virtex-7 eval boards).
## result[31:8] can be connected to PMOD headers, FMC connectors, or ILA probes.
##==============================================================================

## LED bank: result[7:0] -> LED[7:0]
set_property PACKAGE_PIN <BOARD_PIN_LED0>  [get_ports {result[0]}]
set_property PACKAGE_PIN <BOARD_PIN_LED1>  [get_ports {result[1]}]
set_property PACKAGE_PIN <BOARD_PIN_LED2>  [get_ports {result[2]}]
set_property PACKAGE_PIN <BOARD_PIN_LED3>  [get_ports {result[3]}]
set_property PACKAGE_PIN <BOARD_PIN_LED4>  [get_ports {result[4]}]
set_property PACKAGE_PIN <BOARD_PIN_LED5>  [get_ports {result[5]}]
set_property PACKAGE_PIN <BOARD_PIN_LED6>  [get_ports {result[6]}]
set_property PACKAGE_PIN <BOARD_PIN_LED7>  [get_ports {result[7]}]

set_property IOSTANDARD  LVCMOS33 [get_ports {result[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[4]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[5]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[6]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {result[7]}]

set_property DRIVE  12   [get_ports {result[*]}]
set_property SLEW   SLOW [get_ports {result[*]}]

## Output delay for LED outputs (external, no setup/hold requirement)
set_output_delay -clock sys_clk -max  4.000 [get_ports {result[*]}]
set_output_delay -clock sys_clk -min -1.000 [get_ports {result[*]}]


##==============================================================================
## SECTION 6 : INTERRUPT ACKNOWLEDGE OUTPUT
##
## irq_ack pulses HIGH for one cycle when the CPU accepts an interrupt.
## Connect to external PLIC/interrupt controller to de-assert the IRQ line.
## If no external PLIC is used, leave as a test point / ILA probe.
##==============================================================================

set_property PACKAGE_PIN  <BOARD_PIN_IRQ_ACK>  [get_ports irq_ack]
set_property IOSTANDARD   LVCMOS33              [get_ports irq_ack]
set_property DRIVE        4                     [get_ports irq_ack]
set_property SLEW         SLOW                  [get_ports irq_ack]

set_output_delay -clock sys_clk -max  4.000 [get_ports irq_ack]
set_output_delay -clock sys_clk -min -1.000 [get_ports irq_ack]


##==============================================================================
## SECTION 7 : TIMING CONSTRAINTS AND ANALYSIS
##==============================================================================

## ── 7.1 Derived Clock from MMCM (uncomment when MMCM is used) ──────────────
## If you add an MMCM/PLL to condition the clock (recommended for FPGA),
## declare the derived clock output as a new clock constraint:
##
## create_generated_clock -name cpu_clk -source [get_ports clk] \
##   -multiply_by 1 -divide_by 1 [get_pins mmcm_inst/CLKOUT0]

## ── 7.2 Clock Domain Crossing (CDC) ─────────────────────────────────────────
## UART RX -> CPU: Double-flop synchronizer handles this; declare as false path:
## (Already declared above in Section 4)

## ── 7.3 Reset false path (already set in Section 2) ─────────────────────────

## ── 7.4 Expected Timing Closure ─────────────────────────────────────────────
## Virtex-7 -1 speed grade typical achievable frequencies for this design:
##   Critical path: likely through ALU -> forwarding mux -> register file
##   Estimated Fmax: 150-220 MHz (5-stage pipeline, no MMCM)
##   Start conservatively at 100 MHz, use Timing Report to push higher.

## ── 7.5 Instruction Memory (ROM) path ───────────────────────────────────────
## The ROM read address (PC) is registered; output data arrives in same cycle.
## Vivado will automatically handle BRAM output register timing.


##==============================================================================
## SECTION 8 : BITSTREAM AND CONFIGURATION SETTINGS
##==============================================================================

## Enable bitstream compression (reduces file size and programming time)
set_property BITSTREAM.GENERAL.COMPRESS         TRUE    [current_design]

## Configuration mode (uncomment to match your board)
## set_property BITSTREAM.CONFIG.CONFIGFALLBACK  DISABLE [current_design]

## SPI flash configuration interface (if board uses SPI flash)
## set_property BITSTREAM.CONFIG.SPI_BUSWIDTH    4       [current_design]
## set_property BITSTREAM.CONFIG.SPI_FALL_EDGE   YES     [current_design]

## User JTAG code (optional, useful for identifying bitstream in chain)
set_property BITSTREAM.GENERAL.JTAG_USERCODE    32'hC0DEC0DE [current_design]


##==============================================================================
## SECTION 9 : IN-CIRCUIT DEBUG (ILA) - OPTIONAL
##
## Vivado ILA allows real-time probing via JTAG - no extra pins needed.
## The Virtex-7 JTAG port is always available through the config interface.
##
## To add probes:
##   1. Open Synthesized Design in Vivado
##   2. Select nets in Netlist view -> Set as Debug
##   3. Run Set Up Debug wizard
##   4. Tool auto-generates ILA IP and constraints
##
## Recommended probe signals for RISC-V debug:
##   - PCF (fetch program counter)
##   - instrD (instruction in decode stage)
##   - csr_unit/mepc_q (machine exception PC)
##   - csr_unit/mcause_q (trap cause code)
##   - csr_unit/priv_mode_q (privilege level)
##   - uart_tx / uart_rx (serial data)
##==============================================================================

## Mark key signals for ILA probing (uncomment as needed):
## set_property mark_debug true [get_nets {riscv_top_pipeline/new_fet/PCF_out[*]}]
## set_property mark_debug true [get_nets {riscv_top_pipeline/csr_unit/mepc_q[*]}]
## set_property mark_debug true [get_nets {riscv_top_pipeline/csr_unit/mcause_q[*]}]
## set_property mark_debug true [get_nets {riscv_top_pipeline/csr_unit/priv_mode_q[*]}]
## set_property mark_debug true [get_nets {riscv_top_pipeline/instrD[*]}]


##==============================================================================
## SECTION 10 : REQUIRED RTL CHANGES BEFORE FPGA SYNTHESIS
##
## The following simulation-only constructs MUST be replaced:
##
## [1] riscv_data_mem.sv - UART RX:
##     REMOVE:  $fopen / $fgetc / $fclose file-based input
##     REPLACE: Instantiate an 8N1 UART receiver module
##              Receive uart_rx serial bit stream at baud rate
##              Store received byte into uart_rx_cache register
##
## [2] riscv_data_mem.sv - UART TX:
##     REMOVE:  $write("%c", WriteData[7:0]) / $fflush()
##     REPLACE: Instantiate an 8N1 UART transmitter module
##              Buffer WriteData[7:0], serialize on uart_tx pin
##
## [3] riscv_instruction_mem.sv - Firmware ROM:
##     REMOVE:  $readmemh("firmware.hex", mem)
##     REPLACE: Use Vivado Block Memory Generator IP (Single Port ROM)
##              Initialize with firmware .coe file generated from hex
##              elf2coe.py converts firmware.hex to Xilinx .coe format
##
## [4] riscv_data_mem.sv - Platform detection at 0x3FFC:
##     CHANGE:  ReadData = 32'h51554553 (QUES)
##     TO:      ReadData = 32'h46504741 (FPGA)
##              So the Snake game uses FPGA-appropriate delay timing
##
## [5] riscv_top_pipeline.sv - Add uart_tx and uart_rx ports:
##     ADD input  logic uart_rx to the module port list
##     ADD output logic uart_tx to the module port list
##     PASS these through to riscv_data_mem instantiation
##==============================================================================

## End of riscv_fpga.xdc