@echo off
rem =====================================================================
rem Vivado xsim Simulation Compilation and Run Script
rem =====================================================================

set VIVADO_BIN=C:\Xilinx\Vivado\2018.2\bin

echo Compiling SystemVerilog files...
call %VIVADO_BIN%\xvlog.bat -sv rtl\RV32I\riscv_pc_target.sv rtl\RV32I\riscv_alu.sv rtl\RV32I\riscv_control_unit.sv rtl\RV32I\riscv_csr_unit.sv rtl\RV32I\riscv_data_mem.sv rtl\RV32I\riscv_extend.sv rtl\RV32I\riscv_hazard_unit.sv rtl\RV32I\riscv_instruction_mem.sv rtl\RV32I\riscv_mux_3_1.sv rtl\RV32I\riscv_mux_4_1.sv rtl\RV32I\riscv_pc_src_controller.sv rtl\RV32I\riscv_register_file.sv rtl\RV32I\riscv_fetch_stage.sv rtl\RV32I\riscv_decode_stage.sv rtl\RV32I\riscv_execute_stage.sv rtl\RV32I\riscv_memory_stage.sv rtl\RV32I\riscv_top_pipeline.sv rtl\RV32I\riscv_top_tb.sv
if %errorlevel% neq 0 (
    echo xvlog compilation failed!
    exit /b %errorlevel%
)

echo Elaborating design...
call %VIVADO_BIN%\xelab.bat -debug typical work.riscv_top_tb -s riscv_sim
if %errorlevel% neq 0 (
    echo xelab elaboration failed!
    exit /b %errorlevel%
)

echo Starting Vivado simulation...
call %VIVADO_BIN%\xsim.bat riscv_sim -runall
