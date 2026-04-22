vlib work
vlog control_unit.sv
vlog control_unit_tb.sv


vsim -voptargs=+acc work.control_unit_tb

add wave *

run -all

