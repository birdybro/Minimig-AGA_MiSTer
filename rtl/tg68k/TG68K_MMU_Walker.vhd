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

entity TG68K_MMU_Walker is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		logical_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		write_access : in std_logic;
		crp : in mmu_root_pointer_t;
		srp : in mmu_root_pointer_t;
		tc : in mmu_tc_t;

		bus_ready : in std_logic;
		bus_error : in std_logic;
		bus_read_data : in std_logic_vector(15 downto 0);
		bus_request : out std_logic;
		bus_write : out std_logic;
		bus_lock : out std_logic;
		bus_address : out std_logic_vector(31 downto 0);
		bus_write_data : out std_logic_vector(15 downto 0);
		bus_function_code : out std_logic_vector(2 downto 0);

		busy : out std_logic;
		done : out std_logic;
		mapping_valid : out std_logic;
		physical_address : out std_logic_vector(31 downto 0);
		cache_inhibit : out std_logic;
		write_protected : out std_logic;
		supervisor_violation : out std_logic;
		modified : out std_logic;
		invalid_descriptor : out std_logic;
		limit_violation : out std_logic;
		walk_bus_error : out std_logic;
		fault_descriptor_address : out std_logic_vector(31 downto 0);
		fault_during_update : out std_logic;
		final_descriptor_address : out std_logic_vector(31 downto 0);
		descriptor_count : out std_logic_vector(2 downto 0)
	);
end entity;

architecture rtl of TG68K_MMU_Walker is
	type walk_state_t is (IDLE, PREPARE_FETCH, FETCH_WORD_0,
		FETCH_WORD_1, FETCH_WORD_2, FETCH_WORD_3, DECODE_DESCRIPTOR,
		UPDATE_WORD_0, UPDATE_WORD_1, FINALIZE_PAGE, COMPLETE);
	type update_action_t is (UPDATE_CONTINUE_TABLE, UPDATE_FINISH_PAGE);

	function table_width(value : mmu_tc_t; level : natural) return natural is
	begin
		case level is
			when 0 => return to_integer(unsigned(value(15 downto 12)));
			when 1 => return to_integer(unsigned(value(11 downto 8)));
			when 2 => return to_integer(unsigned(value(7 downto 4)));
			when 3 => return to_integer(unsigned(value(3 downto 0)));
			when others => return 0;
		end case;
	end function;

	function extract_index(
		address_value : std_logic_vector(31 downto 0);
		remaining : natural;
		width : natural) return unsigned is
		variable shifted : unsigned(31 downto 0);
		variable result : unsigned(14 downto 0) := (others => '0');
	begin
		shifted := shift_right(unsigned(address_value), remaining - width);
		for bit_number in 0 to 14 loop
			if bit_number < width then
				result(bit_number) := shifted(bit_number);
			end if;
		end loop;
		return result;
	end function;

	function low_mask(bit_count : natural) return unsigned is
		variable result : unsigned(31 downto 0) := (others => '0');
	begin
		for bit_number in result'range loop
			if bit_number < bit_count then
				result(bit_number) := '1';
			end if;
		end loop;
		return result;
	end function;

	function outside_limit(
		index_value : unsigned(14 downto 0);
		descriptor : mmu_descriptor_info_t) return boolean is
	begin
		if descriptor.limit_present = '0' then
			return false;
		elsif descriptor.limit_lower = '1' then
			return index_value < unsigned(descriptor.limit);
		else
			return index_value > unsigned(descriptor.limit);
		end if;
	end function;

	signal state : walk_state_t := IDLE;
	signal update_action : update_action_t := UPDATE_CONTINUE_TABLE;
	signal logical_address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) := (others => '0');
	signal write_access_latched : std_logic := '0';
	signal tc_latched : mmu_tc_t := (others => '0');
	signal current_descriptor : mmu_descriptor_info_t := MMU_DESCRIPTOR_INFO_DEFAULT;
	signal descriptor_data : std_logic_vector(63 downto 0) := (others => '0');
	signal fetch_format : mmu_descriptor_format_t := MMU_DESCRIPTOR_SHORT;
	signal fetch_leaf : std_logic := '0';
	signal fetch_indirect_target : std_logic := '0';
	signal descriptor_base_address : std_logic_vector(31 downto 0) := (others => '0');
	signal transfer_address : std_logic_vector(31 downto 0) := (others => '0');
	signal update_first_word : std_logic_vector(31 downto 0) := (others => '0');
	signal table_level : natural range 0 to 4 := 0;
	signal remaining_bits : natural range 0 to 32 := 0;
	signal fcl_pending : std_logic := '0';
	signal accrued_write_protect : std_logic := '0';
	signal accrued_supervisor_violation : std_logic := '0';
	signal page_address_field : std_logic_vector(31 downto 0) := (others => '0');
	signal page_limit_present : std_logic := '0';
	signal page_limit_lower : std_logic := '0';
	signal page_limit : std_logic_vector(14 downto 0) := (others => '0');
	signal page_early_termination : std_logic := '0';

	signal mapping_valid_reg : std_logic := '0';
	signal physical_address_reg : std_logic_vector(31 downto 0) := (others => '0');
	signal cache_inhibit_reg : std_logic := '0';
	signal write_protected_reg : std_logic := '0';
	signal supervisor_violation_reg : std_logic := '0';
	signal modified_reg : std_logic := '0';
	signal invalid_descriptor_reg : std_logic := '0';
	signal limit_violation_reg : std_logic := '0';
	signal walk_bus_error_reg : std_logic := '0';
	signal fault_descriptor_address_reg : std_logic_vector(31 downto 0) := (others => '0');
	signal fault_during_update_reg : std_logic := '0';
	signal final_descriptor_address_reg : std_logic_vector(31 downto 0) := (others => '0');
	signal descriptor_count_reg : unsigned(2 downto 0) := (others => '0');
begin
	bus_request <= '1' when state = FETCH_WORD_0 or state = FETCH_WORD_1 or
		state = FETCH_WORD_2 or state = FETCH_WORD_3 or
		state = UPDATE_WORD_0 or state = UPDATE_WORD_1 else '0';
	bus_write <= '1' when state = UPDATE_WORD_0 or state = UPDATE_WORD_1 else '0';
	bus_lock <= '1' when state /= IDLE and state /= COMPLETE else '0';
	bus_address <= transfer_address;
	bus_write_data <= update_first_word(31 downto 16) when state = UPDATE_WORD_0 else
		update_first_word(15 downto 0);
	bus_function_code <= "101";
	busy <= '1' when state /= IDLE else '0';

	mapping_valid <= mapping_valid_reg;
	physical_address <= physical_address_reg;
	cache_inhibit <= cache_inhibit_reg;
	write_protected <= write_protected_reg;
	supervisor_violation <= supervisor_violation_reg;
	modified <= modified_reg;
	invalid_descriptor <= invalid_descriptor_reg;
	limit_violation <= limit_violation_reg;
	walk_bus_error <= walk_bus_error_reg;
	fault_descriptor_address <= fault_descriptor_address_reg;
	fault_during_update <= fault_during_update_reg;
	final_descriptor_address <= final_descriptor_address_reg;
	descriptor_count <= std_logic_vector(descriptor_count_reg);

	walker : process(clk)
		variable selected_root : mmu_root_pointer_t;
		variable decoded : mmu_descriptor_info_t;
		variable index_value : unsigned(14 downto 0);
		variable index_width : natural range 0 to 15;
		variable descriptor_offset : unsigned(31 downto 0);
		variable first_word : std_logic_vector(31 downto 0);
		variable next_write_protect : std_logic;
		variable next_supervisor_violation : std_logic;
		variable page_mask : unsigned(31 downto 0);
		variable offset_mask : unsigned(31 downto 0);
		variable initial_remaining : natural range 0 to 32;
		variable perform_fetch : boolean;
	begin
		if rising_edge(clk) then
			done <= '0';
			if nReset = '0' then
				state <= IDLE;
				mapping_valid_reg <= '0';
				physical_address_reg <= (others => '0');
				cache_inhibit_reg <= '0';
				write_protected_reg <= '0';
				supervisor_violation_reg <= '0';
				modified_reg <= '0';
				invalid_descriptor_reg <= '0';
				limit_violation_reg <= '0';
				walk_bus_error_reg <= '0';
				fault_descriptor_address_reg <= (others => '0');
				fault_during_update_reg <= '0';
				final_descriptor_address_reg <= (others => '0');
				descriptor_count_reg <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							logical_address_latched <= logical_address;
							function_code_latched <= function_code;
							write_access_latched <= write_access;
							tc_latched <= tc;
							mapping_valid_reg <= '0';
							physical_address_reg <= (others => '0');
							cache_inhibit_reg <= '0';
							write_protected_reg <= '0';
							supervisor_violation_reg <= '0';
							modified_reg <= '0';
							invalid_descriptor_reg <= '0';
							limit_violation_reg <= '0';
							walk_bus_error_reg <= '0';
							fault_descriptor_address_reg <= (others => '0');
							fault_during_update_reg <= '0';
							final_descriptor_address_reg <= (others => '0');
							descriptor_count_reg <= (others => '0');
							accrued_write_protect <= '0';
							accrued_supervisor_violation <= '0';
							table_level <= 0;
							initial_remaining := 32 - to_integer(unsigned(tc(
								MMU_TC_IS_HIGH downto MMU_TC_IS_LOW)));
							remaining_bits <= initial_remaining;

							if tc(MMU_TC_ENABLE_BIT) = '0' or function_code = "111" then
								mapping_valid_reg <= '1';
								physical_address_reg <= logical_address;
								state <= COMPLETE;
							else
								if tc(MMU_TC_SRE_BIT) = '1' and function_code(2) = '1' then
									selected_root := srp;
								else
									selected_root := crp;
								end if;
								decoded := mmu_decode_descriptor(selected_root,
									MMU_DESCRIPTOR_ROOT, '0');
								if decoded.kind = MMU_DESCRIPTOR_INVALID then
									invalid_descriptor_reg <= '1';
									state <= COMPLETE;
								elsif decoded.kind = MMU_DESCRIPTOR_PAGE then
									index_width := table_width(tc, 0);
									index_value := extract_index(logical_address,
										initial_remaining, index_width);
									if outside_limit(index_value, decoded) then
										limit_violation_reg <= '1';
									else
										mapping_valid_reg <= '1';
										physical_address_reg <= std_logic_vector(
											unsigned(logical_address) +
											unsigned(decoded.address_field));
									end if;
									state <= COMPLETE;
								else
									current_descriptor <= decoded;
									fcl_pending <= tc(MMU_TC_FCL_BIT);
									state <= PREPARE_FETCH;
								end if;
							end if;
						end if;

					when PREPARE_FETCH =>
						perform_fetch := false;
						if fcl_pending = '1' then
							index_value := resize(unsigned(function_code_latched), 15);
							fetch_leaf <= '0';
							fcl_pending <= '0';
							perform_fetch := true;
						else
							index_width := table_width(tc_latched, table_level);
							if index_width = 0 then
								invalid_descriptor_reg <= '1';
								state <= COMPLETE;
							else
								index_value := extract_index(logical_address_latched,
									remaining_bits, index_width);
								if outside_limit(index_value, current_descriptor) then
									limit_violation_reg <= '1';
									state <= COMPLETE;
								else
									remaining_bits <= remaining_bits - index_width;
									if table_level = 3 or table_width(tc_latched,
											table_level + 1) = 0 then
										fetch_leaf <= '1';
									else
										fetch_leaf <= '0';
									end if;
									table_level <= table_level + 1;
									perform_fetch := true;
								end if;
							end if;
						end if;

						if perform_fetch then
							if current_descriptor.next_format = MMU_DESCRIPTOR_LONG then
								descriptor_offset := shift_left(resize(index_value, 32), 3);
							else
								descriptor_offset := shift_left(resize(index_value, 32), 2);
							end if;
							descriptor_base_address <= std_logic_vector(
								unsigned(current_descriptor.address_field) + descriptor_offset);
							transfer_address <= std_logic_vector(
								unsigned(current_descriptor.address_field) + descriptor_offset);
							fetch_format <= current_descriptor.next_format;
							fetch_indirect_target <= '0';
							descriptor_data <= (others => '0');
							state <= FETCH_WORD_0;
						end if;

					when FETCH_WORD_0 =>
						if bus_error = '1' then
							walk_bus_error_reg <= '1';
							fault_descriptor_address_reg <= transfer_address;
							state <= COMPLETE;
						elsif bus_ready = '1' then
							if fetch_format = MMU_DESCRIPTOR_SHORT then
								descriptor_data(31 downto 16) <= bus_read_data;
							else
								descriptor_data(63 downto 48) <= bus_read_data;
							end if;
							transfer_address <= std_logic_vector(unsigned(transfer_address) + 2);
							state <= FETCH_WORD_1;
						end if;

					when FETCH_WORD_1 =>
						if bus_error = '1' then
							walk_bus_error_reg <= '1';
							fault_descriptor_address_reg <= transfer_address;
							state <= COMPLETE;
						elsif bus_ready = '1' then
							if fetch_format = MMU_DESCRIPTOR_SHORT then
								descriptor_data(15 downto 0) <= bus_read_data;
								descriptor_count_reg <= descriptor_count_reg + 1;
								final_descriptor_address_reg <= descriptor_base_address;
								state <= DECODE_DESCRIPTOR;
							else
								descriptor_data(47 downto 32) <= bus_read_data;
								transfer_address <= std_logic_vector(unsigned(transfer_address) + 2);
								state <= FETCH_WORD_2;
							end if;
						end if;

					when FETCH_WORD_2 =>
						if bus_error = '1' then
							walk_bus_error_reg <= '1';
							fault_descriptor_address_reg <= transfer_address;
							state <= COMPLETE;
						elsif bus_ready = '1' then
							descriptor_data(31 downto 16) <= bus_read_data;
							transfer_address <= std_logic_vector(unsigned(transfer_address) + 2);
							state <= FETCH_WORD_3;
						end if;

					when FETCH_WORD_3 =>
						if bus_error = '1' then
							walk_bus_error_reg <= '1';
							fault_descriptor_address_reg <= transfer_address;
							state <= COMPLETE;
						elsif bus_ready = '1' then
							descriptor_data(15 downto 0) <= bus_read_data;
							descriptor_count_reg <= descriptor_count_reg + 1;
							final_descriptor_address_reg <= descriptor_base_address;
							state <= DECODE_DESCRIPTOR;
						end if;

					when DECODE_DESCRIPTOR =>
						decoded := mmu_decode_descriptor(descriptor_data,
							fetch_format, fetch_leaf);
						if fetch_indirect_target = '1' and
								decoded.kind /= MMU_DESCRIPTOR_PAGE then
							invalid_descriptor_reg <= '1';
							state <= COMPLETE;
						elsif decoded.kind = MMU_DESCRIPTOR_INVALID then
							invalid_descriptor_reg <= '1';
							state <= COMPLETE;
						elsif decoded.kind = MMU_DESCRIPTOR_INDIRECT then
							descriptor_base_address <= decoded.address_field;
							transfer_address <= decoded.address_field;
							fetch_format <= decoded.next_format;
							fetch_leaf <= '1';
							fetch_indirect_target <= '1';
							descriptor_data <= (others => '0');
							state <= FETCH_WORD_0;
						else
							next_write_protect := accrued_write_protect or
								decoded.write_protect;
							next_supervisor_violation := accrued_supervisor_violation or
								(decoded.supervisor_only and not function_code_latched(2));
							accrued_write_protect <= next_write_protect;
							accrued_supervisor_violation <= next_supervisor_violation;
							write_protected_reg <= next_write_protect;
							supervisor_violation_reg <= next_supervisor_violation;
							first_word := descriptor_data(31 downto 0);
							if fetch_format = MMU_DESCRIPTOR_LONG then
								first_word := descriptor_data(63 downto 32);
							end if;

							if decoded.kind = MMU_DESCRIPTOR_TABLE then
								current_descriptor <= decoded;
								if decoded.used = '0' and
										next_supervisor_violation = '0' then
									first_word(MMU_DESCRIPTOR_USED_BIT) := '1';
									update_first_word <= first_word;
									transfer_address <= descriptor_base_address;
									update_action <= UPDATE_CONTINUE_TABLE;
									state <= UPDATE_WORD_0;
								else
									state <= PREPARE_FETCH;
								end if;
							else
								page_address_field <= decoded.address_field;
								page_limit_present <= decoded.limit_present;
								page_limit_lower <= decoded.limit_lower;
								page_limit <= decoded.limit;
								page_early_termination <= decoded.early_termination;
								cache_inhibit_reg <= decoded.cache_inhibit;
								modified_reg <= decoded.modified;
								if next_supervisor_violation = '0' and
										(decoded.used = '0' or
										(write_access_latched = '1' and
										 next_write_protect = '0' and decoded.modified = '0')) then
									first_word(MMU_DESCRIPTOR_USED_BIT) := '1';
									if write_access_latched = '1' and
											next_write_protect = '0' then
										first_word(MMU_DESCRIPTOR_MODIFIED_BIT) := '1';
										modified_reg <= '1';
									end if;
									update_first_word <= first_word;
									transfer_address <= descriptor_base_address;
									update_action <= UPDATE_FINISH_PAGE;
									state <= UPDATE_WORD_0;
								else
									state <= FINALIZE_PAGE;
								end if;
							end if;
						end if;

					when UPDATE_WORD_0 =>
						if bus_error = '1' then
							walk_bus_error_reg <= '1';
							fault_descriptor_address_reg <= transfer_address;
							fault_during_update_reg <= '1';
							state <= COMPLETE;
						elsif bus_ready = '1' then
							transfer_address <= std_logic_vector(unsigned(transfer_address) + 2);
							state <= UPDATE_WORD_1;
						end if;

					when UPDATE_WORD_1 =>
						if bus_error = '1' then
							walk_bus_error_reg <= '1';
							fault_descriptor_address_reg <= transfer_address;
							fault_during_update_reg <= '1';
							state <= COMPLETE;
						elsif bus_ready = '1' then
							if update_action = UPDATE_CONTINUE_TABLE then
								state <= PREPARE_FETCH;
							else
								state <= FINALIZE_PAGE;
							end if;
						end if;

					when FINALIZE_PAGE =>
						if page_early_termination = '1' and
								page_limit_present = '1' then
							index_width := table_width(tc_latched, table_level);
							index_value := extract_index(logical_address_latched,
								remaining_bits, index_width);
							decoded := MMU_DESCRIPTOR_INFO_DEFAULT;
							decoded.limit_present := page_limit_present;
							decoded.limit_lower := page_limit_lower;
							decoded.limit := page_limit;
							if outside_limit(index_value, decoded) then
								limit_violation_reg <= '1';
								state <= COMPLETE;
							else
								page_mask := low_mask(to_integer(unsigned(tc_latched(
									MMU_TC_PS_HIGH downto MMU_TC_PS_LOW))));
								offset_mask := low_mask(remaining_bits);
								physical_address_reg <= std_logic_vector(
									(unsigned(page_address_field) and not page_mask) +
									(unsigned(logical_address_latched) and offset_mask));
								mapping_valid_reg <= '1';
								state <= COMPLETE;
							end if;
						else
							page_mask := low_mask(to_integer(unsigned(tc_latched(
								MMU_TC_PS_HIGH downto MMU_TC_PS_LOW))));
							offset_mask := low_mask(remaining_bits);
							physical_address_reg <= std_logic_vector(
								(unsigned(page_address_field) and not page_mask) +
								(unsigned(logical_address_latched) and offset_mask));
							mapping_valid_reg <= '1';
							state <= COMPLETE;
						end if;

					when COMPLETE =>
						done <= '1';
						state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
