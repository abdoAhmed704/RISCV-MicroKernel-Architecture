vlib work

vlog \
    ../compressed_decoder/riscv_core_compressed_decoder.sv \
    ../dynamic_branch_prediction/risc_bht.sv \
    ../dynamic_branch_prediction/risc_btb.sv \
    ../dynamic_branch_prediction/risc_execute.sv \
    ../dynamic_branch_prediction/risc_fetch.sv \
    ../dynamic_branch_prediction/risc_top_branch.sv \
    ../tiny_inference_chip/control/controller_fsm.sv \
    ../tiny_inference_chip/registers/input_reg.sv \
    ../tiny_inference_chip/registers/output_reg.sv \
    ../tiny_inference_chip/registers/weight_reg.sv \
    ../tiny_inference_chip/compute/pe.sv \
    ../tiny_inference_chip/compute/systolic_4x4.sv \
    ../tiny_inference_chip/compute/linear_classifier.sv \
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
