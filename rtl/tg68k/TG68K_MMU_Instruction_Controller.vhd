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
use ieee.numeric_std.all;
use work.TG68K_MMU_Pack.all;

entity TG68K_MMU_Instruction_Controller is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		command_valid : in std_logic;
		command_unimplemented : in std_logic;
		command_privilege_violation : in std_logic;
		operation : in mmu_instruction_operation_t;
		register_select : in mmu_register_t;
		operand_size : in mmu_operand_size_t;
		flush_disable : in std_logic;
		read_access : in std_logic;
		effective_address : in std_logic_vector(31 downto 0);
		fc_source : in mmu_fc_source_t;
		fc_immediate : in std_logic_vector(2 downto 0);
		fc_data_register_value : in std_logic_vector(2 downto 0);
		sfc : in std_logic_vector(2 downto 0);
		dfc : in std_logic_vector(2 downto 0);
		fc_mask : in std_logic_vector(2 downto 0);
		ptest_level : in std_logic_vector(2 downto 0);
		ptest_return_address : in std_logic;
		ptest_address_register : in std_logic_vector(2 downto 0);

		memory_ready : in std_logic;
		memory_error : in std_logic;
		memory_read_data : in std_logic_vector(15 downto 0);
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_function_code : out std_logic_vector(2 downto 0);

		mmu_register_read_data : in std_logic_vector(63 downto 0);
		mmu_configuration_exception : in std_logic;
		mmu_register_write : out std_logic;
		mmu_register_select : out mmu_register_t;
		mmu_register_write_data : out std_logic_vector(63 downto 0);
		mmu_flush_disable : out std_logic;

		atc_lookup_match : in std_logic;
		atc_lookup_write_protected : in std_logic;
		atc_lookup_modified : in std_logic;
		atc_lookup_bus_error : in std_logic;
		transparent_match : in std_logic;
		atc_lookup_request : out std_logic;
		atc_lookup_test : out std_logic;
		atc_lookup_address : out std_logic_vector(31 downto 0);
		atc_lookup_function_code : out std_logic_vector(2 downto 0);
		atc_lookup_write : out std_logic;
		atc_flush_all : out std_logic;
		atc_flush_request : out std_logic;
		atc_flush_by_address : out std_logic;
		atc_flush_address : out std_logic_vector(31 downto 0);
		atc_flush_function_code_base : out std_logic_vector(2 downto 0);
		atc_flush_function_code_mask : out std_logic_vector(2 downto 0);
		atc_fill_request : out std_logic;
		atc_fill_logical_address : out std_logic_vector(31 downto 0);
		atc_fill_function_code : out std_logic_vector(2 downto 0);
		atc_fill_physical_address : out std_logic_vector(31 downto 0);
		atc_fill_cache_inhibit : out std_logic;
		atc_fill_write_protected : out std_logic;
		atc_fill_modified : out std_logic;
		atc_fill_bus_error : out std_logic;

		walker_done : in std_logic;
		walker_mapping_valid : in std_logic;
		walker_physical_address : in std_logic_vector(31 downto 0);
		walker_cache_inhibit : in std_logic;
		walker_write_protected : in std_logic;
		walker_supervisor_violation : in std_logic;
		walker_modified : in std_logic;
		walker_invalid_descriptor : in std_logic;
		walker_limit_violation : in std_logic;
		walker_bus_error : in std_logic;
		walker_final_descriptor_address : in std_logic_vector(31 downto 0);
		walker_descriptor_count : in std_logic_vector(2 downto 0);
		walker_start : out std_logic;
		walker_logical_address : out std_logic_vector(31 downto 0);
		walker_function_code : out std_logic_vector(2 downto 0);
		walker_write_access : out std_logic;
		walker_force_table_search : out std_logic;
		walker_suppress_descriptor_updates : out std_logic;
		walker_stop_level : out std_logic_vector(2 downto 0);

		busy : out std_logic;
		done : out std_logic;
		unimplemented_exception : out std_logic;
		privilege_exception : out std_logic;
		bus_error_exception : out std_logic;
		configuration_exception : out std_logic;
		address_register_write : out std_logic;
		address_register_select : out std_logic_vector(2 downto 0);
		address_register_data : out std_logic_vector(31 downto 0)
	);
end entity;

architecture rtl of TG68K_MMU_Instruction_Controller is
	type controller_state_t is (IDLE, PMOVE_READ, PMOVE_COMMIT,
		PMOVE_WAIT_CONFIGURATION, PMOVE_WRITE, FLUSH_ATC, PLOAD_FLUSH,
		PLOAD_WALK_START, PLOAD_WALK_WAIT, PLOAD_FILL, PTEST_ATC,
		PTEST_WALK_START, PTEST_WALK_WAIT, PTEST_COMMIT, COMPLETE);

	function transfer_word_count(size : mmu_operand_size_t) return natural is
	begin
		case size is
			when MMU_SIZE_WORD => return 1;
			when MMU_SIZE_LONG => return 2;
			when MMU_SIZE_QUAD => return 4;
			when others => return 1;
		end case;
	end function;

	function transfer_word(
		value : std_logic_vector(63 downto 0);
		size : mmu_operand_size_t;
		index : natural) return std_logic_vector is
	begin
		case size is
			when MMU_SIZE_QUAD =>
				case index is
					when 0 => return value(63 downto 48);
					when 1 => return value(47 downto 32);
					when 2 => return value(31 downto 16);
					when others => return value(15 downto 0);
				end case;
			when MMU_SIZE_LONG =>
				if index = 0 then
					return value(31 downto 16);
				else
					return value(15 downto 0);
				end if;
			when others =>
				return value(15 downto 0);
		end case;
	end function;

	function resolve_function_code(
		source : mmu_fc_source_t;
		immediate_value : std_logic_vector(2 downto 0);
		data_register_value : std_logic_vector(2 downto 0);
		source_function_code : std_logic_vector(2 downto 0);
		destination_function_code : std_logic_vector(2 downto 0))
		return std_logic_vector is
	begin
		case source is
			when MMU_FC_SOURCE_IMMEDIATE => return immediate_value;
			when MMU_FC_SOURCE_DATA_REGISTER => return data_register_value;
			when MMU_FC_SOURCE_DFC => return destination_function_code;
			when others => return source_function_code;
		end case;
	end function;

	signal state : controller_state_t := IDLE;
	signal operation_latched : mmu_instruction_operation_t := MMU_OP_NONE;
	signal register_latched : mmu_register_t := MMU_REG_TC;
	signal operand_size_latched : mmu_operand_size_t := MMU_SIZE_NONE;
	signal flush_disable_latched : std_logic := '0';
	signal read_access_latched : std_logic := '0';
	signal effective_address_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) := (others => '0');
	signal fc_mask_latched : std_logic_vector(2 downto 0) := (others => '0');
	signal ptest_level_latched : std_logic_vector(2 downto 0) := (others => '0');
	signal ptest_return_latched : std_logic := '0';
	signal ptest_address_register_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal transfer_data : std_logic_vector(63 downto 0) := (others => '0');
	signal transfer_index : natural range 0 to 3 := 0;
	signal transfer_count : natural range 1 to 4 := 1;
	signal ptest_status : mmu_status_t := (others => '0');
	signal result_unimplemented : std_logic := '0';
	signal result_privilege : std_logic := '0';
	signal result_bus_error : std_logic := '0';
	signal result_configuration : std_logic := '0';
	signal result_address_write : std_logic := '0';
	signal result_address_select : std_logic_vector(2 downto 0) := (others => '0');
	signal result_address_data : std_logic_vector(31 downto 0) := (others => '0');
	signal fill_physical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal fill_cache_inhibit : std_logic := '0';
	signal fill_write_protected : std_logic := '0';
	signal fill_modified : std_logic := '0';
	signal fill_bus_error : std_logic := '0';
begin
	busy <= '1' when state /= IDLE and state /= COMPLETE else '0';
	done <= '1' when state = COMPLETE else '0';
	unimplemented_exception <= result_unimplemented when state = COMPLETE else '0';
	privilege_exception <= result_privilege when state = COMPLETE else '0';
	bus_error_exception <= result_bus_error when state = COMPLETE else '0';
	configuration_exception <= result_configuration when state = COMPLETE else '0';
	address_register_write <= result_address_write when state = COMPLETE else '0';
	address_register_select <= result_address_select;
	address_register_data <= result_address_data;

	memory_request <= '1' when state = PMOVE_READ or state = PMOVE_WRITE else '0';
	memory_write <= '1' when state = PMOVE_WRITE else '0';
	memory_address <= std_logic_vector(unsigned(effective_address_latched) +
		to_unsigned(transfer_index * 2, 32));
	memory_write_data <= transfer_word(transfer_data, operand_size_latched,
		transfer_index);
	memory_function_code <= "101";

	mmu_register_write <= '1' when state = PMOVE_COMMIT or
		state = PTEST_COMMIT else '0';
	mmu_register_select <= MMU_REG_MMUSR when state = PTEST_COMMIT else
		register_select when state = IDLE else register_latched;
	mmu_register_write_data <= x"000000000000" & ptest_status
		when state = PTEST_COMMIT else transfer_data;
	mmu_flush_disable <= flush_disable_latched;

	atc_lookup_request <= '1' when state = PTEST_ATC else '0';
	atc_lookup_test <= '1' when state = PTEST_ATC else '0';
	atc_lookup_address <= effective_address_latched;
	atc_lookup_function_code <= function_code_latched;
	atc_lookup_write <= not read_access_latched;
	atc_flush_all <= '1' when state = FLUSH_ATC and
		operation_latched = MMU_OP_PFLUSH_ALL else '0';
	atc_flush_request <= '1' when state = PLOAD_FLUSH or
		(state = FLUSH_ATC and operation_latched /= MMU_OP_PFLUSH_ALL) else '0';
	atc_flush_by_address <= '1' when state = PLOAD_FLUSH or
		(state = FLUSH_ATC and operation_latched = MMU_OP_PFLUSH_PAGE) else '0';
	atc_flush_address <= effective_address_latched;
	atc_flush_function_code_base <= function_code_latched;
	atc_flush_function_code_mask <= "111" when state = PLOAD_FLUSH else
		fc_mask_latched;
	atc_fill_request <= '1' when state = PLOAD_FILL else '0';
	atc_fill_logical_address <= effective_address_latched;
	atc_fill_function_code <= function_code_latched;
	atc_fill_physical_address <= fill_physical_address;
	atc_fill_cache_inhibit <= fill_cache_inhibit;
	atc_fill_write_protected <= fill_write_protected;
	atc_fill_modified <= fill_modified;
	atc_fill_bus_error <= fill_bus_error;

	walker_start <= '1' when state = PLOAD_WALK_START or
		state = PTEST_WALK_START else '0';
	walker_logical_address <= effective_address_latched;
	walker_function_code <= function_code_latched;
	walker_write_access <= not read_access_latched;
	walker_force_table_search <= '1' when state = PLOAD_WALK_START or
		state = PLOAD_WALK_WAIT or state = PTEST_WALK_START or
		state = PTEST_WALK_WAIT else '0';
	walker_suppress_descriptor_updates <= '1' when
		state = PTEST_WALK_START or state = PTEST_WALK_WAIT else '0';
	walker_stop_level <= ptest_level_latched when
		state = PTEST_WALK_START or state = PTEST_WALK_WAIT else "000";

	controller : process(clk)
		variable next_transfer_data : std_logic_vector(63 downto 0);
		variable next_status : mmu_status_t;
		variable resolved_function_code : std_logic_vector(2 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				operation_latched <= MMU_OP_NONE;
				register_latched <= MMU_REG_TC;
				operand_size_latched <= MMU_SIZE_NONE;
				flush_disable_latched <= '0';
				read_access_latched <= '0';
				effective_address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				fc_mask_latched <= (others => '0');
				ptest_level_latched <= (others => '0');
				ptest_return_latched <= '0';
				ptest_address_register_latched <= (others => '0');
				transfer_data <= (others => '0');
				transfer_index <= 0;
				transfer_count <= 1;
				ptest_status <= (others => '0');
				result_unimplemented <= '0';
				result_privilege <= '0';
				result_bus_error <= '0';
				result_configuration <= '0';
				result_address_write <= '0';
				result_address_select <= (others => '0');
				result_address_data <= (others => '0');
				fill_physical_address <= (others => '0');
				fill_cache_inhibit <= '0';
				fill_write_protected <= '0';
				fill_modified <= '0';
				fill_bus_error <= '0';
			else
				case state is
					when IDLE =>
						result_unimplemented <= '0';
						result_privilege <= '0';
						result_bus_error <= '0';
						result_configuration <= '0';
						result_address_write <= '0';
						if start = '1' then
							resolved_function_code := resolve_function_code(fc_source,
								fc_immediate, fc_data_register_value, sfc, dfc);
							operation_latched <= operation;
							register_latched <= register_select;
							operand_size_latched <= operand_size;
							flush_disable_latched <= flush_disable;
							read_access_latched <= read_access;
							effective_address_latched <= effective_address;
							function_code_latched <= resolved_function_code;
							fc_mask_latched <= fc_mask;
							ptest_level_latched <= ptest_level;
							ptest_return_latched <= ptest_return_address;
							ptest_address_register_latched <= ptest_address_register;
							transfer_index <= 0;
							transfer_count <= transfer_word_count(operand_size);
							transfer_data <= (others => '0');
							if command_privilege_violation = '1' then
								result_privilege <= '1';
								state <= COMPLETE;
							elsif command_valid = '0' or command_unimplemented = '1' then
								result_unimplemented <= '1';
								state <= COMPLETE;
							else
								case operation is
									when MMU_OP_PMOVE_TO_MMU =>
										state <= PMOVE_READ;
									when MMU_OP_PMOVE_FROM_MMU =>
										transfer_data <= mmu_register_read_data;
										state <= PMOVE_WRITE;
									when MMU_OP_PFLUSH_ALL | MMU_OP_PFLUSH_FC |
											MMU_OP_PFLUSH_PAGE =>
										state <= FLUSH_ATC;
									when MMU_OP_PLOAD =>
										state <= PLOAD_FLUSH;
									when MMU_OP_PTEST =>
										if ptest_level = "000" then
											state <= PTEST_ATC;
										else
											state <= PTEST_WALK_START;
										end if;
									when others =>
										result_unimplemented <= '1';
										state <= COMPLETE;
								end case;
							end if;
						end if;

					when PMOVE_READ =>
						if memory_error = '1' then
							result_bus_error <= '1';
							state <= COMPLETE;
						elsif memory_ready = '1' then
							next_transfer_data := transfer_data;
							case operand_size_latched is
								when MMU_SIZE_QUAD =>
									case transfer_index is
										when 0 => next_transfer_data(63 downto 48) := memory_read_data;
										when 1 => next_transfer_data(47 downto 32) := memory_read_data;
										when 2 => next_transfer_data(31 downto 16) := memory_read_data;
										when others => next_transfer_data(15 downto 0) := memory_read_data;
									end case;
								when MMU_SIZE_LONG =>
									if transfer_index = 0 then
										next_transfer_data(31 downto 16) := memory_read_data;
									else
										next_transfer_data(15 downto 0) := memory_read_data;
									end if;
								when others =>
									next_transfer_data(15 downto 0) := memory_read_data;
							end case;
							transfer_data <= next_transfer_data;
							if transfer_index + 1 = transfer_count then
								state <= PMOVE_COMMIT;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when PMOVE_COMMIT =>
						state <= PMOVE_WAIT_CONFIGURATION;

					when PMOVE_WAIT_CONFIGURATION =>
						result_configuration <= mmu_configuration_exception;
						state <= COMPLETE;

					when PMOVE_WRITE =>
						if memory_error = '1' then
							result_bus_error <= '1';
							state <= COMPLETE;
						elsif memory_ready = '1' then
							if transfer_index + 1 = transfer_count then
								state <= COMPLETE;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when FLUSH_ATC =>
						state <= COMPLETE;

					when PLOAD_FLUSH =>
						state <= PLOAD_WALK_START;

					when PLOAD_WALK_START =>
						state <= PLOAD_WALK_WAIT;

					when PLOAD_WALK_WAIT =>
						if walker_done = '1' then
							fill_physical_address <= walker_physical_address;
							fill_cache_inhibit <= walker_cache_inhibit;
							fill_write_protected <= walker_write_protected;
							fill_modified <= walker_modified;
			fill_bus_error <= not walker_mapping_valid or walker_bus_error or
								walker_invalid_descriptor or walker_limit_violation or
								walker_supervisor_violation;
							state <= PLOAD_FILL;
						end if;

					when PLOAD_FILL =>
						state <= COMPLETE;

					when PTEST_ATC =>
						next_status := (others => '0');
						if transparent_match = '1' then
							next_status(MMU_STATUS_TRANSPARENT_BIT) := '1';
						else
							next_status(MMU_STATUS_BUS_ERROR_BIT) := atc_lookup_bus_error;
							next_status(MMU_STATUS_WRITE_PROTECT_BIT) :=
								atc_lookup_write_protected;
							next_status(MMU_STATUS_INVALID_BIT) :=
								not atc_lookup_match or atc_lookup_bus_error;
							next_status(MMU_STATUS_MODIFIED_BIT) := atc_lookup_modified;
						end if;
						ptest_status <= next_status;
						state <= PTEST_COMMIT;

					when PTEST_WALK_START =>
						state <= PTEST_WALK_WAIT;

					when PTEST_WALK_WAIT =>
						if walker_done = '1' then
							next_status := (others => '0');
							next_status(MMU_STATUS_BUS_ERROR_BIT) := walker_bus_error;
							next_status(MMU_STATUS_LIMIT_BIT) := walker_limit_violation;
							next_status(MMU_STATUS_SUPERVISOR_BIT) :=
								walker_supervisor_violation;
							next_status(MMU_STATUS_WRITE_PROTECT_BIT) :=
								walker_write_protected;
							next_status(MMU_STATUS_INVALID_BIT) :=
								walker_invalid_descriptor or walker_bus_error or
								walker_limit_violation;
							next_status(MMU_STATUS_MODIFIED_BIT) := walker_modified;
							next_status(MMU_STATUS_LEVEL_HIGH downto
								MMU_STATUS_LEVEL_LOW) := walker_descriptor_count;
							ptest_status <= next_status;
							if ptest_return_latched = '1' then
								result_address_write <= '1';
								result_address_select <= ptest_address_register_latched;
								result_address_data <= walker_final_descriptor_address;
							end if;
							state <= PTEST_COMMIT;
						end if;

					when PTEST_COMMIT =>
						state <= COMPLETE;

					when COMPLETE =>
						state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
