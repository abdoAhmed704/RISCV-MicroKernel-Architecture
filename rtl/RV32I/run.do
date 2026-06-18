vlib work

vlog riscv_*.sv

vsim -voptargs=+acc work.riscv_top_tb

add wave *

run -all