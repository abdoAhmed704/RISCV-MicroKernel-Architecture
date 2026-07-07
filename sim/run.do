vlib work

vlog ../rtl/compresed_decoder/riscv_core_compressed_decoder.sv ../rtl/riscv32_dynamicbranchprediction/*.v ../rtl/tinyInferenceChip/control/*.v ../rtl/tinyInferenceChip/registers/*.sv ../rtl/tinyInferenceChip/compute/pe.sv ../rtl/tinyInferenceChip/compute/systolic_4x4.sv ../rtl/tinyInferenceChip/compute/linear_classifier.sv ../rtl/RV32I/riscv_*.sv

# simulate
vsim -voptargs=+acc work.riscv_top_tb

# add waves
add wave *

add wave -position insertpoint  \
sim:/riscv_top_tb/top_ins/PCD \
sim:/riscv_top_tb/top_ins/PCE \
sim:/riscv_top_tb/top_ins/PCPlus4D \
sim:/riscv_top_tb/top_ins/PCPlus4E \
sim:/riscv_top_tb/top_ins/PCPlus4M \
sim:/riscv_top_tb/top_ins/PCPlus4W

# run simulation
run -all