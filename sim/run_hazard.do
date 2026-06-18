vlib work
vlog ../rtl/RV32I/riscv_hazard_unit.sv

# Note: The testbench hazard_unit_tb.sv is not in this repository.
# To simulate the hazard unit separately, create a testbench and run:
# vlog ../rtl/RV32I/riscv_hazard_unit_tb.sv
# vsim -voptargs=+acc work.riscv_hazard_unit_tb
# add wave *
# run -all
