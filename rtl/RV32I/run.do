vlib work

vlog \
    ../compresed_decoder/riscv_core_compressed_decoder.sv \
    ../riscv32_dynamicbranchprediction/risc_bht.v \
    ../riscv32_dynamicbranchprediction/risc_btb.v \
    ../riscv32_dynamicbranchprediction/risc_execute.v \
    ../riscv32_dynamicbranchprediction/risc_fetch.v \
    ../riscv32_dynamicbranchprediction/risc_top_branch.v \
    ../tinyInferenceChip/control/controller_fsm.v \
    ../tinyInferenceChip/registers/input_reg.sv \
    ../tinyInferenceChip/registers/output_reg.sv \
    ../tinyInferenceChip/registers/weight_reg.sv \
    ../tinyInferenceChip/compute/pe.sv \
    ../tinyInferenceChip/compute/systolic_4x4.sv \
    ../tinyInferenceChip/compute/linear_classifier.sv \
    riscv_alu.sv \
    riscv_control_unit.sv \
    riscv_csr_unit.sv \
    riscv_data_mem.sv \
    riscv_decode_stage.sv \
    riscv_execute_stage.sv \
    riscv_extend.sv \
    riscv_fetch_stage.sv \
    riscv_hazard_unit.sv \
    riscv_instruction_mem.sv \
    riscv_memory_stage.sv \
    riscv_mux_3_1.sv \
    riscv_mux_4_1.sv \
    riscv_pc_src_controller.sv \
    riscv_pc_target.sv \
    riscv_register_file.sv \
    riscv_top_pipeline.sv \
    riscv_top_tb.sv

vsim -voptargs=+acc work.riscv_top_tb

add wave *

run -all