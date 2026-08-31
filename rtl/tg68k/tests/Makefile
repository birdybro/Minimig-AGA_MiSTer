GHDL ?= ghdl
GHDL_FLAGS := --std=08 --ieee=synopsys
GHDL_RUN_FLAGS := --ieee-asserts=disable
BUILD_DIR := build
RTL := ../TG68K_MMU_Pack.vhd ../TG68K_MMU.vhd ../TG68K_Pack.vhd \
	../TG68K_ALU.vhd ../TG68KdotC_Kernel.vhd

.PHONY: all analyze smoke mmu_state synth clean

all: smoke mmu_state synth

analyze:
	mkdir -p $(BUILD_DIR)
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(RTL) \
		tb_tg68k_smoke.vhd tb_tg68k_mmu_state.vhd
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_state

smoke: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke -gCPU_MODE=0 $(GHDL_RUN_FLAGS)
	mv $(BUILD_DIR)/bus_trace.log $(BUILD_DIR)/bus_trace_68000.log
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke -gCPU_MODE=1 $(GHDL_RUN_FLAGS)
	mv $(BUILD_DIR)/bus_trace.log $(BUILD_DIR)/bus_trace_68010.log
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_smoke -gCPU_MODE=3 $(GHDL_RUN_FLAGS)
	mv $(BUILD_DIR)/bus_trace.log $(BUILD_DIR)/bus_trace_68020.log

mmu_state: analyze
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) tb_tg68k_mmu_state $(GHDL_RUN_FLAGS)

synth: analyze
	$(GHDL) synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) TG68K_MMU > $(BUILD_DIR)/TG68K_MMU_synth.vhd

clean:
	rm -r $(BUILD_DIR)
