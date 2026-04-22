vlib work
vlog insruction_mem.sv
vlog instruction_tb.sv


vsim -voptargs=+acc work.instruction_mem_tb

add wave *

run -all

