vlib work
vlog hazard_unit.sv
vlog hazard_unit_tb.sv


vsim -voptargs=+acc work.hazard_unit_tb

add wave *

run -all

