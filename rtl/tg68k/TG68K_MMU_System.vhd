------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2026 TG68K contributors                                    --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU Lesser General Public License as published --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.TG68K_MMU_Pack.all;

entity TG68K_MMU_System is
	port(
		clk : in std_logic;
		nReset : in std_logic;

		opcode : in std_logic_vector(15 downto 0);
		extension_word : in std_logic_vector(15 downto 0);
		supervisor : in std_logic;
		effective_address : in std_logic_vector(31 downto 0);
		fc_data_register_value : in std_logic_vector(2 downto 0);
		sfc : in std_logic_vector(2 downto 0);
		dfc : in std_logic_vector(2 downto 0);
		instruction_start : in std_logic;
		instruction_match : out std_logic;
		instruction_valid : out std_logic;
		instruction_requires_effective_address : out std_logic;
		fc_data_register_select : out std_logic_vector(2 downto 0);
		instruction_busy : out std_logic;
		instruction_done : out std_logic;
		unimplemented_exception : out std_logic;
		privilege_exception : out std_logic;
		bus_error_exception : out std_logic;
		configuration_exception : out std_logic;
		address_register_write : out std_logic;
		address_register_select : out std_logic_vector(2 downto 0);
		address_register_data : out std_logic_vector(31 downto 0);

		operand_bus_ready : in std_logic;
		operand_bus_error : in std_logic;
		operand_bus_read_data : in std_logic_vector(15 downto 0);
		operand_bus_request : out std_logic;
		operand_bus_write : out std_logic;
		operand_bus_address : out std_logic_vector(31 downto 0);
		operand_bus_write_data : out std_logic_vector(15 downto 0);
		operand_bus_function_code : out std_logic_vector(2 downto 0);

		table_bus_ready : in std_logic;
		table_bus_error : in std_logic;
		table_bus_read_data : in std_logic_vector(15 downto 0);
		table_bus_request : out std_logic;
		table_bus_write : out std_logic;
		table_bus_lock : out std_logic;
		table_bus_address : out std_logic_vector(31 downto 0);
		table_bus_write_data : out std_logic_vector(15 downto 0);
		table_bus_function_code : out std_logic_vector(2 downto 0);

		crp_out : out mmu_root_pointer_t;
		srp_out : out mmu_root_pointer_t;
		tc_out : out mmu_tc_t;
		tt0_out : out mmu_tt_t;
		tt1_out : out mmu_tt_t;
		mmusr_out : out mmu_status_t
	);
end entity;

architecture rtl of TG68K_MMU_System is
	signal decoded_valid : std_logic;
	signal decoded_unimplemented : std_logic;
	signal decoded_privilege : std_logic;
	signal decoded_operation : mmu_instruction_operation_t;
	signal decoded_register : mmu_register_t;
	signal decoded_size : mmu_operand_size_t;
	signal decoded_flush_disable : std_logic;
	signal decoded_read_access : std_logic;
	signal decoded_fc_source : mmu_fc_source_t;
	signal decoded_fc_immediate : std_logic_vector(2 downto 0);
	signal decoded_fc_data_register : std_logic_vector(2 downto 0);
	signal decoded_fc_mask : std_logic_vector(2 downto 0);
	signal decoded_ptest_level : std_logic_vector(2 downto 0);
	signal decoded_ptest_return : std_logic;
	signal decoded_ptest_address_register : std_logic_vector(2 downto 0);

	signal register_write : std_logic;
	signal register_select : mmu_register_t;
	signal register_write_data : std_logic_vector(63 downto 0);
	signal register_read_data : std_logic_vector(63 downto 0);
	signal register_flush_disable : std_logic;
	signal register_configuration_exception : std_logic;
	signal register_atc_flush_all : std_logic;
	signal crp : mmu_root_pointer_t;
	signal srp : mmu_root_pointer_t;
	signal tc : mmu_tc_t;
	signal tt0 : mmu_tt_t;
	signal tt1 : mmu_tt_t;
	signal mmusr : mmu_status_t;

	signal controller_atc_lookup_request : std_logic;
	signal controller_atc_lookup_test : std_logic;
	signal controller_atc_lookup_address : std_logic_vector(31 downto 0);
	signal controller_atc_lookup_fc : std_logic_vector(2 downto 0);
	signal controller_atc_lookup_write : std_logic;
	signal atc_lookup_match : std_logic;
	signal atc_lookup_hit : std_logic;
	signal atc_lookup_requires_walk : std_logic;
	signal atc_lookup_physical_address : std_logic_vector(31 downto 0);
	signal atc_lookup_cache_inhibit : std_logic;
	signal atc_lookup_write_protected : std_logic;
	signal atc_lookup_modified : std_logic;
	signal atc_lookup_bus_error : std_logic;
	signal controller_atc_flush_all : std_logic;
	signal combined_atc_flush_all : std_logic;
	signal controller_atc_flush_request : std_logic;
	signal controller_atc_flush_by_address : std_logic;
	signal controller_atc_flush_address : std_logic_vector(31 downto 0);
	signal controller_atc_flush_fc_base : std_logic_vector(2 downto 0);
	signal controller_atc_flush_fc_mask : std_logic_vector(2 downto 0);
	signal controller_atc_fill_request : std_logic;
	signal controller_atc_fill_logical : std_logic_vector(31 downto 0);
	signal controller_atc_fill_fc : std_logic_vector(2 downto 0);
	signal controller_atc_fill_physical : std_logic_vector(31 downto 0);
	signal controller_atc_fill_ci : std_logic;
	signal controller_atc_fill_wp : std_logic;
	signal controller_atc_fill_m : std_logic;
	signal controller_atc_fill_b : std_logic;

	signal transparent_match : std_logic;
	signal transparent_cache_inhibit : std_logic;
	signal transparent_cpu_space : std_logic;

	signal controller_walker_start : std_logic;
	signal controller_walker_logical : std_logic_vector(31 downto 0);
	signal controller_walker_fc : std_logic_vector(2 downto 0);
	signal controller_walker_write : std_logic;
	signal controller_walker_force : std_logic;
	signal controller_walker_suppress_updates : std_logic;
	signal controller_walker_stop_level : std_logic_vector(2 downto 0);
	signal walker_busy : std_logic;
	signal walker_done : std_logic;
	signal walker_mapping_valid : std_logic;
	signal walker_physical_address : std_logic_vector(31 downto 0);
	signal walker_cache_inhibit : std_logic;
	signal walker_write_protected : std_logic;
	signal walker_supervisor_violation : std_logic;
	signal walker_modified : std_logic;
	signal walker_invalid_descriptor : std_logic;
	signal walker_limit_violation : std_logic;
	signal walker_bus_error : std_logic;
	signal walker_fault_descriptor_address : std_logic_vector(31 downto 0);
	signal walker_fault_during_update : std_logic;
	signal walker_final_descriptor_address : std_logic_vector(31 downto 0);
	signal walker_descriptor_count : std_logic_vector(2 downto 0);
begin
	combined_atc_flush_all <= register_atc_flush_all or controller_atc_flush_all;
	fc_data_register_select <= decoded_fc_data_register;
	crp_out <= crp;
	srp_out <= srp;
	tc_out <= tc;
	tt0_out <= tt0;
	tt1_out <= tt1;
	mmusr_out <= mmusr;

	decoder : entity work.TG68K_MMU_Instruction_Decoder
		port map(
			opcode => opcode,
			extension_word => extension_word,
			supervisor => supervisor,
			instruction_match => instruction_match,
			instruction_valid => decoded_valid,
			unimplemented_instruction => decoded_unimplemented,
			privilege_violation => decoded_privilege,
			operation => decoded_operation,
			register_select => decoded_register,
			operand_size => decoded_size,
			flush_disable => decoded_flush_disable,
			read_access => decoded_read_access,
			requires_effective_address => instruction_requires_effective_address,
			fc_source => decoded_fc_source,
			fc_immediate => decoded_fc_immediate,
			fc_data_register => decoded_fc_data_register,
			fc_mask => decoded_fc_mask,
			ptest_level => decoded_ptest_level,
			ptest_return_address => decoded_ptest_return,
			ptest_address_register => decoded_ptest_address_register
		);
	instruction_valid <= decoded_valid;

	registers : entity work.TG68K_MMU
		port map(
			clk => clk,
			nReset => nReset,
			register_select => register_select,
			register_write => register_write,
			register_write_data => register_write_data,
			flush_disable => register_flush_disable,
			register_read_data => register_read_data,
			configuration_exception => register_configuration_exception,
			atc_flush_all => register_atc_flush_all,
			translation_enabled => open,
			supervisor_root_enabled => open,
			function_code_lookup_enabled => open,
			crp_out => crp,
			srp_out => srp,
			tc_out => tc,
			tt0_out => tt0,
			tt1_out => tt1,
			mmusr_out => mmusr
		);

	transparent : entity work.TG68K_MMU_Transparent
		port map(
			tt0 => tt0,
			tt1 => tt1,
			logical_address => controller_atc_lookup_address,
			function_code => controller_atc_lookup_fc,
			write_access => controller_atc_lookup_write,
			read_modify_write => '0',
			cpu_space_access => transparent_cpu_space,
			tt0_match => open,
			tt1_match => open,
			transparent_match => transparent_match,
			translation_bypass => open,
			physical_address => open,
			cache_inhibit => transparent_cache_inhibit
		);

	atc : entity work.TG68K_MMU_ATC
		port map(
			clk => clk,
			nReset => nReset,
			page_size => tc(MMU_TC_PS_HIGH downto MMU_TC_PS_LOW),
			lookup_request => controller_atc_lookup_request,
			lookup_logical_address => controller_atc_lookup_address,
			lookup_function_code => controller_atc_lookup_fc,
			lookup_write => controller_atc_lookup_write,
			lookup_test => controller_atc_lookup_test,
			lookup_match => atc_lookup_match,
			lookup_hit => atc_lookup_hit,
			lookup_requires_walk => atc_lookup_requires_walk,
			lookup_physical_address => atc_lookup_physical_address,
			lookup_cache_inhibit => atc_lookup_cache_inhibit,
			lookup_write_protected => atc_lookup_write_protected,
			lookup_modified => atc_lookup_modified,
			lookup_bus_error => atc_lookup_bus_error,
			fill_request => controller_atc_fill_request,
			fill_logical_address => controller_atc_fill_logical,
			fill_function_code => controller_atc_fill_fc,
			fill_physical_address => controller_atc_fill_physical,
			fill_cache_inhibit => controller_atc_fill_ci,
			fill_write_protected => controller_atc_fill_wp,
			fill_modified => controller_atc_fill_m,
			fill_bus_error => controller_atc_fill_b,
			flush_all => combined_atc_flush_all,
			flush_request => controller_atc_flush_request,
			flush_by_address => controller_atc_flush_by_address,
			flush_logical_address => controller_atc_flush_address,
			flush_function_code_base => controller_atc_flush_fc_base,
			flush_function_code_mask => controller_atc_flush_fc_mask
		);

	walker : entity work.TG68K_MMU_Walker
		port map(
			clk => clk,
			nReset => nReset,
			start => controller_walker_start,
			logical_address => controller_walker_logical,
			function_code => controller_walker_fc,
			write_access => controller_walker_write,
			force_table_search => controller_walker_force,
			suppress_descriptor_updates => controller_walker_suppress_updates,
			stop_level => controller_walker_stop_level,
			crp => crp,
			srp => srp,
			tc => tc,
			bus_ready => table_bus_ready,
			bus_error => table_bus_error,
			bus_read_data => table_bus_read_data,
			bus_request => table_bus_request,
			bus_write => table_bus_write,
			bus_lock => table_bus_lock,
			bus_address => table_bus_address,
			bus_write_data => table_bus_write_data,
			bus_function_code => table_bus_function_code,
			busy => walker_busy,
			done => walker_done,
			mapping_valid => walker_mapping_valid,
			physical_address => walker_physical_address,
			cache_inhibit => walker_cache_inhibit,
			write_protected => walker_write_protected,
			supervisor_violation => walker_supervisor_violation,
			modified => walker_modified,
			invalid_descriptor => walker_invalid_descriptor,
			limit_violation => walker_limit_violation,
			walk_bus_error => walker_bus_error,
			fault_descriptor_address => walker_fault_descriptor_address,
			fault_during_update => walker_fault_during_update,
			final_descriptor_address => walker_final_descriptor_address,
			descriptor_count => walker_descriptor_count
		);

	controller : entity work.TG68K_MMU_Instruction_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => instruction_start,
			command_valid => decoded_valid,
			command_unimplemented => decoded_unimplemented,
			command_privilege_violation => decoded_privilege,
			operation => decoded_operation,
			register_select => decoded_register,
			operand_size => decoded_size,
			flush_disable => decoded_flush_disable,
			read_access => decoded_read_access,
			effective_address => effective_address,
			fc_source => decoded_fc_source,
			fc_immediate => decoded_fc_immediate,
			fc_data_register_value => fc_data_register_value,
			sfc => sfc,
			dfc => dfc,
			fc_mask => decoded_fc_mask,
			ptest_level => decoded_ptest_level,
			ptest_return_address => decoded_ptest_return,
			ptest_address_register => decoded_ptest_address_register,
			memory_ready => operand_bus_ready,
			memory_error => operand_bus_error,
			memory_read_data => operand_bus_read_data,
			memory_request => operand_bus_request,
			memory_write => operand_bus_write,
			memory_address => operand_bus_address,
			memory_write_data => operand_bus_write_data,
			memory_function_code => operand_bus_function_code,
			mmu_register_read_data => register_read_data,
			mmu_configuration_exception => register_configuration_exception,
			mmu_register_write => register_write,
			mmu_register_select => register_select,
			mmu_register_write_data => register_write_data,
			mmu_flush_disable => register_flush_disable,
			atc_lookup_match => atc_lookup_match,
			atc_lookup_write_protected => atc_lookup_write_protected,
			atc_lookup_modified => atc_lookup_modified,
			atc_lookup_bus_error => atc_lookup_bus_error,
			transparent_match => transparent_match,
			atc_lookup_request => controller_atc_lookup_request,
			atc_lookup_test => controller_atc_lookup_test,
			atc_lookup_address => controller_atc_lookup_address,
			atc_lookup_function_code => controller_atc_lookup_fc,
			atc_lookup_write => controller_atc_lookup_write,
			atc_flush_all => controller_atc_flush_all,
			atc_flush_request => controller_atc_flush_request,
			atc_flush_by_address => controller_atc_flush_by_address,
			atc_flush_address => controller_atc_flush_address,
			atc_flush_function_code_base => controller_atc_flush_fc_base,
			atc_flush_function_code_mask => controller_atc_flush_fc_mask,
			atc_fill_request => controller_atc_fill_request,
			atc_fill_logical_address => controller_atc_fill_logical,
			atc_fill_function_code => controller_atc_fill_fc,
			atc_fill_physical_address => controller_atc_fill_physical,
			atc_fill_cache_inhibit => controller_atc_fill_ci,
			atc_fill_write_protected => controller_atc_fill_wp,
			atc_fill_modified => controller_atc_fill_m,
			atc_fill_bus_error => controller_atc_fill_b,
			walker_done => walker_done,
			walker_mapping_valid => walker_mapping_valid,
			walker_physical_address => walker_physical_address,
			walker_cache_inhibit => walker_cache_inhibit,
			walker_write_protected => walker_write_protected,
			walker_supervisor_violation => walker_supervisor_violation,
			walker_modified => walker_modified,
			walker_invalid_descriptor => walker_invalid_descriptor,
			walker_limit_violation => walker_limit_violation,
			walker_bus_error => walker_bus_error,
			walker_final_descriptor_address => walker_final_descriptor_address,
			walker_descriptor_count => walker_descriptor_count,
			walker_start => controller_walker_start,
			walker_logical_address => controller_walker_logical,
			walker_function_code => controller_walker_fc,
			walker_write_access => controller_walker_write,
			walker_force_table_search => controller_walker_force,
			walker_suppress_descriptor_updates => controller_walker_suppress_updates,
			walker_stop_level => controller_walker_stop_level,
			busy => instruction_busy,
			done => instruction_done,
			unimplemented_exception => unimplemented_exception,
			privilege_exception => privilege_exception,
			bus_error_exception => bus_error_exception,
			configuration_exception => configuration_exception,
			address_register_write => address_register_write,
			address_register_select => address_register_select,
			address_register_data => address_register_data
		);
end architecture;
