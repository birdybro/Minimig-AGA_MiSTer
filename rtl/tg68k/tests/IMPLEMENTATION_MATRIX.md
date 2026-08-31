# TG68K MMU/FPU implementation matrix

| Feature | Motorola reference | RTL | Directed verification |
| --- | --- | --- | --- |
| MMU control state and reset | MC68030UM 9.2.2, 9.7 | `TG68K_MMU*.vhd` | `tb_tg68k_mmu_state.vhd` |
| MMU descriptor decoding | MC68030UM 9.1.2, 9.5.1 | `TG68K_MMU_Decoder.vhd` | `tb_tg68k_mmu_descriptor.vhd` |
| MMU table search | MC68030UM 9.5.2-9.5.4 | `TG68K_MMU_Walker.vhd` | `tb_tg68k_mmu_walker.vhd` |
| MMU ATC | MC68030UM 9.4 | `TG68K_MMU_ATC.vhd` | `tb_tg68k_mmu_atc.vhd` |
| MMU transparent translation and FC | MC68030UM 9.2.1, 9.3, 9.5.2 | `TG68K_MMU_Transparent.vhd`, `TG68K_MMU_Walker.vhd` | `tb_tg68k_mmu_transparent.vhd`, `tb_tg68k_mmu_walker.vhd` |
| MMU instruction encoding | M68000PM 6.32-6.67, 8.22-8.24 | `TG68K_MMU_Instruction_Decoder.vhd` | exhaustive `tb_tg68k_mmu_instruction_decoder.vhd` |
| MMU instruction transactions | MC68030UM 9.7.4-9.8; M68000PM 6.32-6.67 | `TG68K_MMU_Instruction_Controller.vhd` | `tb_tg68k_mmu_instruction_controller.vhd` |
| MMU instruction execution | MC68030UM 9.7.5, 9.8; M68000PM PMMU instructions | `TG68K_MMU_Instruction_Controller.vhd`, `TG68KdotC_Kernel.vhd`, `TG68KdotC_MMU.vhd` | `tb_tg68k_mmu_instruction_controller.vhd`, `tb_tg68k_mmu_dispatch.vhd`, `tb_tg68k_mmu_wrapper.vhd` |
| MMU access-fault frame layout and SSW | MC68030UM 8.2.4, figs. 8-14 and 8-15 | `TG68K_MMU_Fault_Frame.vhd`, `TG68K_MMU_Pack.vhd` | exhaustive `tb_tg68k_mmu_fault_frame.vhd` |
| MMU access-fault sequencing | MC68030UM 8.1.2, 8.2, 8.4 | `TG68KdotC_Kernel.vhd`, `TG68KdotC_MMU.vhd` | format A/B, descriptor-read BERR, descriptor-update BERR, and cycle order in `tb_tg68k_mmu_fault_integration.vhd` |
| MMU access-fault restart and RTE | MC68030UM 8.1.13, 8.2.3 | `TG68KdotC_Kernel.vhd`, `TG68KdotC_MMU.vhd` | format A/B deallocation and repaired-cycle replay in `tb_tg68k_mmu_fault_rte.vhd`; invalid-format/version validation pending |
| FPU state, formats, and exceptions | MC68881UM 1, 3, 4, 5, 6 | planned in `TG68K_FPU*.vhd` | FPU module tests |
| FPU arithmetic and constants | MC68881UM 3, 4, 5; M68000PM FPU instructions | planned in FPU RTL | MPFR-generated vectors |
| FPU conditional and transfer instructions | MC68881UM 3, 4, 5 | planned in FPU and kernel RTL | instruction and bus tests |
| FPU save/restore and timing | MC68881UM 6, 10 | planned in FPU timing RTL | frame and cycle tests |
| Integrated MMU/FPU bus and exception behavior | MC68030UM 7, 8, 9; MC68881UM 7, 8 | planned in wrapper/kernel RTL | combined instruction and timing tests |
