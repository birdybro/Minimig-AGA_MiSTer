GHDL ?= ghdl
PYTHON := env PYTHONDONTWRITEBYTECODE=1 python3
GHDL_FLAGS := --std=08 --ieee=synopsys
GHDL_RUN_FLAGS := --ieee-asserts=disable
BUILD_DIR := build
RTL := ../TG68K_MMU_Pack.vhd ../TG68K_MMU_Fault_Frame.vhd \
	../TG68K_MMU_Instruction_Decoder.vhd \
	../TG68K_MMU_Instruction_Controller.vhd \
	../TG68K_MMU_Decoder.vhd \
	../TG68K_MMU_ATC.vhd ../TG68K_MMU_Transparent.vhd \
	../TG68K_MMU_Walker.vhd ../TG68K_MMU.vhd ../TG68K_Pack.vhd \
	../TG68K_MMU_Translation.vhd \
	../TG68K_MMU_System.vhd \
	../TG68K_FPU_Pack.vhd ../TG68K_FPU_Decoder.vhd \
	../TG68K_FPU_Convert.vhd ../TG68K_FPU_Round.vhd \
	../TG68K_FPU_Store_Convert.vhd ../TG68K_FPU_Move_Controller.vhd \
	../TG68K_FPU_Control_Controller.vhd \
	../TG68K_FPU_Movem_Controller.vhd \
	../TG68K_FPU_Extract.vhd \
	../TG68K_FPU_Unary_Controller.vhd \
	../TG68K_FPU_Add_Subtract.vhd ../TG68K_FPU_Multiply.vhd \
	../TG68K_FPU_Divide.vhd ../TG68K_FPU_Square_Root.vhd \
	../TG68K_FPU_Integer.vhd \
	../TG68K_FPU_Binary_Controller.vhd \
	../TG68K_FPU.vhd ../TG68K_FPU_System.vhd \
	../TG68K_ALU.vhd ../TG68KdotC_Kernel.vhd ../TG68KdotC_MMU.vhd ../TG68K.vhd

.PHONY: all analyze smoke mmu_wrapper_smoke mmu_wrapper mmu_fault_frame mmu_fault_integration mmu_fault_rte mmu_state mmu_instruction_decoder mmu_instruction_controller mmu_dispatch mmu_system mmu_translation mmu_descriptor mmu_atc mmu_transparent mmu_walker fpu_state fpu_decoder fpu_convert fpu_round fpu_store_convert fpu_move_controller fpu_control_controller fpu_movem_controller fpu_extract fpu_extract_differential fpu_unary_controller fpu_integer fpu_integer_differential fpu_add_subtract fpu_add_differential fpu_multiply fpu_multiply_differential fpu_divide fpu_divide_differential fpu_square_root fpu_square_root_differential fpu_binary_controller fpu_system fpu_wrapper synth clean

all: smoke mmu_wrapper_smoke mmu_wrapper mmu_fault_frame mmu_fault_integration mmu_fault_rte mmu_state mmu_instruction_decoder mmu_instruction_controller mmu_dispatch mmu_system mmu_translation mmu_descriptor mmu_atc mmu_transparent mmu_walker fpu_state fpu_decoder fpu_convert fpu_round fpu_store_convert fpu_move_controller fpu_control_controller fpu_movem_controller fpu_extract fpu_extract_differential fpu_unary_controller fpu_integer fpu_integer_differential fpu_add_subtract fpu_add_differential fpu_multiply fpu_multiply_differential fpu_divide fpu_divide_differential fpu_square_root fpu_square_root_differential fpu_binary_controller fpu_system fpu_wrapper synth

analyze:
	mkdir -p $(BUILD_DIR)
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(RTL) \
		tb_tg68k_smoke.vhd tb_tg68k_mmu_state.vhd \
		tb_tg68k_mmu_instruction_decoder.vhd \
		tb_tg68k_mmu_instruction_controller.vhd \
		tb_tg68k_mmu_dispatch.vhd tb_tg68k_mmu_wrapper_smoke.vhd \
		tb_tg68k_mmu_wrapper.vhd \
		tb_tg68k_mmu_fault_frame.vhd \
		tb_tg68k_mmu_fault_integration.vhd \
		tb_tg68k_mmu_fault_rte.vhd tb_tg68k_rte_validation.vhd \
		tb_tg68k_mmu_system.vhd \
		tb_tg68k_mmu_translation.vhd \
		tb_tg68k_mmu_descriptor.vhd tb_tg68k_mmu_atc.vhd \
		tb_tg68k_mmu_transparent.vhd tb_tg68k_mmu_walker.vhd \
		tb_tg68k_fpu_state.vhd tb_tg68k_fpu_decoder.vhd \
		tb_tg68k_fpu_convert.vhd tb_tg68k_fpu_round.vhd \
		tb_tg68k_fpu_store_convert.vhd tb_tg68k_fpu_move_controller.vhd \
		tb_tg68k_fpu_control_controller.vhd \
		tb_tg68k_fpu_movem_controller.vhd \
		tb_tg68k_fpu_extract.vhd \
		tb_tg68k_fpu_unary_controller.vhd \
		tb_tg68k_fpu_integer.vhd \
		tb_tg68k_fpu_add_subtract.vhd tb_tg68k_fpu_multiply.vhd \
		tb_tg68k_fpu_divide.vhd tb_tg68k_fpu_square_root.vhd \
		tb_tg68k_fpu_binary_controller.vhd \
		tb_tg68k_fpu_system.vhd tb_tg68k_fpu_wrapper.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_state
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_instruction_decoder
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_instruction_controller
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_dispatch
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_wrapper_smoke
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_wrapper
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_frame
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_rte
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_rte_validation
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_system
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_translation
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_descriptor
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_atc
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_transparent
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_walker
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_state
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_decoder
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_convert
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_round
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_store_convert
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_move_controller
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_control_controller
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_movem_controller
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_extract
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_unary_controller
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_integer
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_add_subtract
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_multiply
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_divide
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_square_root
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_binary_controller
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_system
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_wrapper

smoke: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke -gCPU_MODE=0 $(GHDL_RUN_FLAGS)
	mv $(BUILD_DIR)/bus_trace.log $(BUILD_DIR)/bus_trace_68000.log
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke -gCPU_MODE=1 $(GHDL_RUN_FLAGS)
	mv $(BUILD_DIR)/bus_trace.log $(BUILD_DIR)/bus_trace_68010.log
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke -gCPU_MODE=3 $(GHDL_RUN_FLAGS)
	mv $(BUILD_DIR)/bus_trace.log $(BUILD_DIR)/bus_trace_68020.log

mmu_wrapper_smoke: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_wrapper_smoke -gMMU_ACTIVE=0 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_wrapper_smoke -gMMU_ACTIVE=1 $(GHDL_RUN_FLAGS)

mmu_wrapper: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_wrapper $(GHDL_RUN_FLAGS)

mmu_fault_frame: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_frame $(GHDL_RUN_FLAGS)

mmu_fault_integration: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration -gFAULT_KIND=0 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration -gFAULT_KIND=1 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration -gFAULT_KIND=2 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration -gFAULT_KIND=3 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration -gFAULT_KIND=4 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_integration -gFAULT_KIND=5 $(GHDL_RUN_FLAGS)

mmu_fault_rte: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_rte -gFAULT_KIND=0 $(GHDL_RUN_FLAGS)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_fault_rte -gFAULT_KIND=1 $(GHDL_RUN_FLAGS)
	set -e; for validation_kind in 0 1 2 3 4 5 6 7 8 9 10; do \
		$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) \
			tb_tg68k_rte_validation -gVALIDATION_KIND=$$validation_kind \
			$(GHDL_RUN_FLAGS); \
	done

mmu_state: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_state $(GHDL_RUN_FLAGS)

mmu_instruction_decoder: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_instruction_decoder $(GHDL_RUN_FLAGS)

mmu_instruction_controller: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_instruction_controller $(GHDL_RUN_FLAGS)

mmu_dispatch: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_dispatch $(GHDL_RUN_FLAGS)

mmu_system: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_system $(GHDL_RUN_FLAGS)

mmu_translation: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_translation $(GHDL_RUN_FLAGS)

mmu_descriptor: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_descriptor $(GHDL_RUN_FLAGS)

mmu_atc: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_atc $(GHDL_RUN_FLAGS)

mmu_transparent: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_transparent $(GHDL_RUN_FLAGS)

mmu_walker: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_walker $(GHDL_RUN_FLAGS)

fpu_state: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_state $(GHDL_RUN_FLAGS)

fpu_decoder: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_decoder $(GHDL_RUN_FLAGS)

fpu_convert: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_convert $(GHDL_RUN_FLAGS)

fpu_round: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_round $(GHDL_RUN_FLAGS)

fpu_store_convert: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_store_convert $(GHDL_RUN_FLAGS)

fpu_move_controller: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_move_controller $(GHDL_RUN_FLAGS)

fpu_control_controller: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_control_controller $(GHDL_RUN_FLAGS)

fpu_movem_controller: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_movem_controller $(GHDL_RUN_FLAGS)

fpu_extract: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_extract $(GHDL_RUN_FLAGS)

fpu_extract_differential: analyze generate_fpu_extract_vectors.py fpu_exact_reference.py
	$(PYTHON) generate_fpu_extract_vectors.py > $(BUILD_DIR)/tb_tg68k_fpu_extract_differential.vhd
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(BUILD_DIR)/tb_tg68k_fpu_extract_differential.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_extract_differential
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_extract_differential $(GHDL_RUN_FLAGS)

fpu_unary_controller: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_unary_controller $(GHDL_RUN_FLAGS)

fpu_integer: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_integer $(GHDL_RUN_FLAGS)

fpu_integer_differential: analyze generate_fpu_integer_vectors.py fpu_exact_reference.py
	$(PYTHON) generate_fpu_integer_vectors.py > $(BUILD_DIR)/tb_tg68k_fpu_integer_differential.vhd
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(BUILD_DIR)/tb_tg68k_fpu_integer_differential.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_integer_differential
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_integer_differential $(GHDL_RUN_FLAGS)

fpu_add_subtract: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_add_subtract $(GHDL_RUN_FLAGS)

fpu_add_differential: analyze generate_fpu_add_vectors.py fpu_exact_reference.py
	$(PYTHON) generate_fpu_add_vectors.py > $(BUILD_DIR)/tb_tg68k_fpu_add_differential.vhd
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(BUILD_DIR)/tb_tg68k_fpu_add_differential.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_add_differential
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_add_differential $(GHDL_RUN_FLAGS)

fpu_multiply: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_multiply $(GHDL_RUN_FLAGS)

fpu_multiply_differential: analyze generate_fpu_multiply_vectors.py fpu_exact_reference.py
	$(PYTHON) generate_fpu_multiply_vectors.py > $(BUILD_DIR)/tb_tg68k_fpu_multiply_differential.vhd
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(BUILD_DIR)/tb_tg68k_fpu_multiply_differential.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_multiply_differential
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_multiply_differential $(GHDL_RUN_FLAGS)

fpu_divide: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_divide $(GHDL_RUN_FLAGS)

fpu_divide_differential: analyze generate_fpu_divide_vectors.py fpu_exact_reference.py
	$(PYTHON) generate_fpu_divide_vectors.py > $(BUILD_DIR)/tb_tg68k_fpu_divide_differential.vhd
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(BUILD_DIR)/tb_tg68k_fpu_divide_differential.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_divide_differential
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_divide_differential $(GHDL_RUN_FLAGS)

fpu_square_root: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_square_root $(GHDL_RUN_FLAGS)

fpu_square_root_differential: analyze generate_fpu_square_root_vectors.py fpu_exact_reference.py
	$(PYTHON) generate_fpu_square_root_vectors.py > $(BUILD_DIR)/tb_tg68k_fpu_square_root_differential.vhd
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(BUILD_DIR)/tb_tg68k_fpu_square_root_differential.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_square_root_differential
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_square_root_differential $(GHDL_RUN_FLAGS)

fpu_binary_controller: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_binary_controller $(GHDL_RUN_FLAGS)

fpu_system: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_system $(GHDL_RUN_FLAGS)

fpu_wrapper: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_fpu_wrapper $(GHDL_RUN_FLAGS)

synth: analyze
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU > $(BUILD_DIR)/TG68K_MMU_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Fault_Frame > $(BUILD_DIR)/TG68K_MMU_Fault_Frame_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Instruction_Decoder > $(BUILD_DIR)/TG68K_MMU_Instruction_Decoder_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Instruction_Controller > $(BUILD_DIR)/TG68K_MMU_Instruction_Controller_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Decoder > $(BUILD_DIR)/TG68K_MMU_Decoder_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_ATC > $(BUILD_DIR)/TG68K_MMU_ATC_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Transparent > $(BUILD_DIR)/TG68K_MMU_Transparent_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Walker > $(BUILD_DIR)/TG68K_MMU_Walker_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_Translation > $(BUILD_DIR)/TG68K_MMU_Translation_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU_System > $(BUILD_DIR)/TG68K_MMU_System_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Decoder > $(BUILD_DIR)/TG68K_FPU_Decoder_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Convert > $(BUILD_DIR)/TG68K_FPU_Convert_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Round > $(BUILD_DIR)/TG68K_FPU_Round_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Store_Convert > $(BUILD_DIR)/TG68K_FPU_Store_Convert_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Move_Controller > $(BUILD_DIR)/TG68K_FPU_Move_Controller_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Control_Controller > $(BUILD_DIR)/TG68K_FPU_Control_Controller_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Movem_Controller > $(BUILD_DIR)/TG68K_FPU_Movem_Controller_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Extract > $(BUILD_DIR)/TG68K_FPU_Extract_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Unary_Controller > $(BUILD_DIR)/TG68K_FPU_Unary_Controller_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Add_Subtract > $(BUILD_DIR)/TG68K_FPU_Add_Subtract_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Multiply > $(BUILD_DIR)/TG68K_FPU_Multiply_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Divide > $(BUILD_DIR)/TG68K_FPU_Divide_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Square_Root > $(BUILD_DIR)/TG68K_FPU_Square_Root_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Integer > $(BUILD_DIR)/TG68K_FPU_Integer_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_Binary_Controller > $(BUILD_DIR)/TG68K_FPU_Binary_Controller_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU > $(BUILD_DIR)/TG68K_FPU_synth.vhd
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_FPU_System > $(BUILD_DIR)/TG68K_FPU_System_synth.vhd
	$(GHDL) synth --latches $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68KdotC_MMU > $(BUILD_DIR)/TG68KdotC_MMU_synth.vhd

clean:
	rm -r $(BUILD_DIR)
