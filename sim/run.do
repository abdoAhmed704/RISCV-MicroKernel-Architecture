vlib work

vlog ../rtl/RV32I/*.sv

# simulate
vsim -voptargs=+acc work.top_tb

# add waves

add wave *

add wave -position insertpoint  \
sim:/top_tb/top_ins/PCD \
sim:/top_tb/top_ins/PCE \
sim:/top_tb/top_ins/PCPlus4D \
sim:/top_tb/top_ins/PCPlus4E \
sim:/top_tb/top_ins/PCPlus4M \
sim:/top_tb/top_ins/PCPlus4W

# run simulation
run -all