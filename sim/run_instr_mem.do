vlib work
vlog ../rtl/RV32I/riscv_instruction_mem.sv

# Note: The testbench instruction_tb.sv is not in this repository.
# To simulate the instruction memory separately, create a testbench and run:
# vlog ../rtl/RV32I/riscv_instruction_mem_tb.sv
# vsim -voptargs=+acc work.riscv_instruction_mem_tb
# add wave *
# run -all
