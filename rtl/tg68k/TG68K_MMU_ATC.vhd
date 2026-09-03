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

entity TG68K_MMU_ATC is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		page_size : in std_logic_vector(3 downto 0);

		lookup_request : in std_logic;
		lookup_logical_address : in std_logic_vector(31 downto 0);
		lookup_function_code : in std_logic_vector(2 downto 0);
		lookup_write : in std_logic;
		lookup_test : in std_logic := '0';
		lookup_match : out std_logic;
		lookup_hit : out std_logic;
		lookup_requires_walk : out std_logic;
		lookup_physical_address : out std_logic_vector(31 downto 0);
		lookup_cache_inhibit : out std_logic;
		lookup_write_protected : out std_logic;
		lookup_modified : out std_logic;
		lookup_bus_error : out std_logic;

		fill_request : in std_logic;
		fill_logical_address : in std_logic_vector(31 downto 0);
		fill_function_code : in std_logic_vector(2 downto 0);
		fill_physical_address : in std_logic_vector(31 downto 0);
		fill_cache_inhibit : in std_logic;
		fill_write_protected : in std_logic;
		fill_modified : in std_logic;
		fill_bus_error : in std_logic;

		flush_all : in std_logic;
		flush_request : in std_logic;
		flush_by_address : in std_logic;
		flush_logical_address : in std_logic_vector(31 downto 0);
		flush_function_code_base : in std_logic_vector(2 downto 0);
		flush_function_code_mask : in std_logic_vector(2 downto 0)
	);
end entity;

architecture rtl of TG68K_MMU_ATC is
	type page_address_array_t is array (0 to MMU_ATC_ENTRY_COUNT - 1) of
		std_logic_vector(23 downto 0);
	type function_code_array_t is array (0 to MMU_ATC_ENTRY_COUNT - 1) of
		std_logic_vector(2 downto 0);
	constant DATA_PHYSICAL_HIGH : natural := 27;
	constant DATA_PHYSICAL_LOW : natural := 4;
	constant DATA_CACHE_INHIBIT_BIT : natural := 3;
	constant DATA_WRITE_PROTECT_BIT : natural := 2;
	constant DATA_MODIFIED_BIT : natural := 1;
	constant DATA_BUS_ERROR_BIT : natural := 0;
	subtype atc_data_t is std_logic_vector(DATA_PHYSICAL_HIGH downto 0);
	type atc_data_array_t is array (0 to MMU_ATC_ENTRY_COUNT - 1) of
		atc_data_t;

	function page_offset_mask(size : std_logic_vector(3 downto 0)) return unsigned is
		variable result : unsigned(31 downto 0) := (others => '0');
		variable bit_count : natural range 0 to 15;
	begin
		bit_count := to_integer(unsigned(size));
		for bit_number in result'range loop
			if bit_number < bit_count then
				result(bit_number) := '1';
			end if;
		end loop;
		return result;
	end function;

	function tag_matches(
		stored_address : std_logic_vector(23 downto 0);
		requested_address : std_logic_vector(31 downto 0);
		offset_mask : unsigned(31 downto 0)) return boolean is
	begin
		return (shift_left(resize(unsigned(stored_address), 32), 8) and
			not offset_mask) =
			(unsigned(requested_address) and not offset_mask);
	end function;

	signal valid_bits : std_logic_vector(MMU_ATC_ENTRY_COUNT - 1 downto 0) :=
		(others => '0');
	signal history_bits : std_logic_vector(MMU_ATC_ENTRY_COUNT - 1 downto 0) :=
		(others => '0');
	signal logical_addresses : page_address_array_t := (others => (others => '0'));
	signal function_codes : function_code_array_t := (others => (others => '0'));
	signal entry_data : atc_data_array_t;
	signal matched_index : natural range 0 to MMU_ATC_ENTRY_COUNT - 1 := 0;
	signal matched_data : atc_data_t;
	signal matched_entry : std_logic := '0';
	signal matched_write_protected : std_logic := '0';
	signal matched_modified : std_logic := '0';
	signal matched_bus_error : std_logic := '0';
	attribute ramstyle : string;
	attribute ramstyle of entry_data : signal is "MLAB, no_rw_check";
begin
	matched_data <= entry_data(matched_index);
	lookup_write_protected <= matched_write_protected;
	lookup_modified <= matched_modified;
	lookup_bus_error <= matched_bus_error;

	lookup : process(page_size, lookup_request, lookup_logical_address,
		lookup_function_code, lookup_write, lookup_test, valid_bits, logical_addresses,
		function_codes, matched_data)
		variable found : boolean;
		variable selected_index : natural range 0 to MMU_ATC_ENTRY_COUNT - 1;
		variable offset_mask : unsigned(31 downto 0);
		variable translated_base : unsigned(31 downto 0);
	begin
		found := false;
		selected_index := 0;
		offset_mask := page_offset_mask(page_size);
		for entry_number in 0 to MMU_ATC_ENTRY_COUNT - 1 loop
			if not found and valid_bits(entry_number) = '1' and
					function_codes(entry_number) = lookup_function_code and
					tag_matches(logical_addresses(entry_number),
						lookup_logical_address, offset_mask) then
				found := true;
				selected_index := entry_number;
			end if;
		end loop;

		matched_index <= selected_index;
		matched_entry <= '0';
		lookup_match <= '0';
		lookup_hit <= '0';
		lookup_requires_walk <= lookup_request;
		lookup_physical_address <= (others => '0');
		lookup_cache_inhibit <= '0';
		matched_write_protected <= '0';
		matched_modified <= '0';
		matched_bus_error <= '0';
		if lookup_request = '1' and found then
			matched_entry <= '1';
			lookup_match <= '1';
			lookup_cache_inhibit <= matched_data(DATA_CACHE_INHIBIT_BIT);
			matched_write_protected <= matched_data(DATA_WRITE_PROTECT_BIT);
			matched_modified <= matched_data(DATA_MODIFIED_BIT);
			matched_bus_error <= matched_data(DATA_BUS_ERROR_BIT);
			translated_base := shift_left(resize(unsigned(
				matched_data(DATA_PHYSICAL_HIGH downto DATA_PHYSICAL_LOW)), 32), 8) and
				not offset_mask;
			lookup_physical_address <= std_logic_vector(translated_base or
				(unsigned(lookup_logical_address) and offset_mask));
			if lookup_test = '0' and lookup_write = '1' and
					matched_data(DATA_MODIFIED_BIT) = '0' and
					matched_data(DATA_WRITE_PROTECT_BIT) = '0' and
					matched_data(DATA_BUS_ERROR_BIT) = '0' then
				lookup_requires_walk <= '1';
			else
				lookup_hit <= '1';
				lookup_requires_walk <= '0';
			end if;
		end if;
	end process;

	entries : process(clk)
		variable next_valid : std_logic_vector(MMU_ATC_ENTRY_COUNT - 1 downto 0);
		variable next_history : std_logic_vector(MMU_ATC_ENTRY_COUNT - 1 downto 0);
		variable selected_index : natural range 0 to MMU_ATC_ENTRY_COUNT - 1;
		variable found : boolean;
		variable offset_mask : unsigned(31 downto 0);

		procedure mark_recent(
			variable history : inout std_logic_vector;
			constant entry_number : natural) is
		begin
			history(entry_number) := '1';
			-- Completing a history epoch makes every other entry replacement-eligible.
			if history = (history'range => '1') then
				history := (history'range => '0');
				history(entry_number) := '1';
			end if;
		end procedure;
	begin
		if rising_edge(clk) then
			-- RESET disables translation but deliberately preserves every ATC entry.
			if nReset = '1' then
				next_valid := valid_bits;
				next_history := history_bits;
				if flush_all = '1' then
					next_valid := (others => '0');
				elsif flush_request = '1' then
					offset_mask := page_offset_mask(page_size);
					for entry_number in 0 to MMU_ATC_ENTRY_COUNT - 1 loop
						if valid_bits(entry_number) = '1' and
								((function_codes(entry_number) xor
									flush_function_code_base) and
								 flush_function_code_mask) = "000" then
							if flush_by_address = '0' or
									tag_matches(logical_addresses(entry_number),
										flush_logical_address, offset_mask) then
								next_valid(entry_number) := '0';
							end if;
						end if;
					end loop;
				elsif fill_request = '1' then
					selected_index := 0;
					found := false;
					for entry_number in 0 to MMU_ATC_ENTRY_COUNT - 1 loop
						if not found and valid_bits(entry_number) = '0' then
							selected_index := entry_number;
							found := true;
						end if;
					end loop;
					if not found then
						for entry_number in 0 to MMU_ATC_ENTRY_COUNT - 1 loop
							if not found and history_bits(entry_number) = '0' then
								selected_index := entry_number;
								found := true;
							end if;
						end loop;
					end if;

					logical_addresses(selected_index) <= fill_logical_address(31 downto 8);
					function_codes(selected_index) <= fill_function_code;
					entry_data(selected_index) <= fill_physical_address(31 downto 8) &
						fill_cache_inhibit & fill_write_protected &
						fill_modified & fill_bus_error;
					next_valid(selected_index) := '1';
					mark_recent(next_history, selected_index);
				elsif lookup_request = '1' and matched_entry = '1' and
						lookup_test = '0' then
					if lookup_write = '1' and
							matched_modified = '0' and
							matched_write_protected = '0' and
							matched_bus_error = '0' then
						next_valid(matched_index) := '0';
					else
						mark_recent(next_history, matched_index);
					end if;
				end if;
				valid_bits <= next_valid;
				history_bits <= next_history;
			end if;
		end if;
	end process;
end architecture;
