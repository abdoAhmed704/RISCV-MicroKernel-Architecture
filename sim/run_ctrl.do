vlib work
vlog ../rtl/RV32I/riscv_control_unit.sv

# Note: The testbench control_unit_tb.sv is not in this repository.
# To simulate the control unit separately, create a testbench and run:
# vlog ../rtl/RV32I/riscv_control_unit_tb.sv
# vsim -voptargs=+acc work.riscv_control_unit_tb
# add wave *
# run -all
