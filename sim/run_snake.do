vlib work

vlog ../rtl/compressed_decoder/riscv_core_compressed_decoder.sv ^
  ../rtl/dynamic_branch_prediction/risc_bht.sv ^
  ../rtl/dynamic_branch_prediction/risc_btb.sv ^
  ../rtl/dynamic_branch_prediction/risc_fetch.sv ^
  ../rtl/dynamic_branch_prediction/risc_execute.sv ^
  ../rtl/dynamic_branch_prediction/risc_top_branch.sv ^
  ../rtl/tiny_inference_chip/compute/pe.sv ^
  ../rtl/tiny_inference_chip/compute/systolic_4x4.sv ^
  ../rtl/tiny_inference_chip/registers/weight_reg.sv ^
  ../rtl/tiny_inference_chip/registers/input_reg.sv ^
  ../rtl/tiny_inference_chip/registers/output_reg.sv ^
  ../rtl/tiny_inference_chip/control/controller_fsm.sv ^
  ../rtl/tiny_inference_chip/compute/linear_classifier.sv ^
  ../rtl/RV32I/riscv_pc_target.sv ^
  ../rtl/RV32I/riscv_alu.sv ^
  ../rtl/RV32I/riscv_control_unit.sv ^
  ../rtl/RV32I/riscv_csr_unit.sv ^
  ../rtl/RV32I/riscv_data_mem.sv ^
  ../rtl/RV32I/riscv_extend.sv ^
  ../rtl/RV32I/riscv_hazard_unit.sv ^
  ../rtl/RV32I/riscv_instruction_mem.sv ^
  ../rtl/RV32I/riscv_mux_3_1.sv ^
  ../rtl/RV32I/riscv_mux_4_1.sv ^
  ../rtl/RV32I/riscv_pc_src_controller.sv ^
  ../rtl/RV32I/riscv_register_file.sv ^
  ../rtl/RV32I/riscv_fetch_stage.sv ^
  ../rtl/RV32I/riscv_decode_stage.sv ^
  ../rtl/RV32I/riscv_execute_stage.sv ^
  ../rtl/RV32I/riscv_memory_stage.sv ^
  ../rtl/RV32I/riscv_top_pipeline.sv ^
  ../rtl/RV32I/riscv_top_tb_snake.sv

# simulate
vsim -voptargs=+acc work.riscv_top_tb_snake

# add waves
add wave *

add wave -position insertpoint  \
sim:/riscv_top_tb_snake/top_ins/PCD \
sim:/riscv_top_tb_snake/top_ins/PCE \
sim:/riscv_top_tb_snake/top_ins/PCPlus4D \
sim:/riscv_top_tb_snake/top_ins/PCPlus4E \
sim:/riscv_top_tb_snake/top_ins/PCPlus4M \
sim:/riscv_top_tb_snake/top_ins/PCPlus4W

# run simulation
run -all
