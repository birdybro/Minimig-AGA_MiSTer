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

package TG68K_MMU_Pack is
	type mmu_register_t is (MMU_REG_CRP, MMU_REG_SRP, MMU_REG_TC,
		MMU_REG_TT0, MMU_REG_TT1, MMU_REG_MMUSR);
	type mmu_descriptor_format_t is (MMU_DESCRIPTOR_ROOT,
		MMU_DESCRIPTOR_SHORT, MMU_DESCRIPTOR_LONG);
	type mmu_descriptor_kind_t is (MMU_DESCRIPTOR_INVALID,
		MMU_DESCRIPTOR_PAGE, MMU_DESCRIPTOR_TABLE, MMU_DESCRIPTOR_INDIRECT);

	subtype mmu_root_pointer_t is std_logic_vector(63 downto 0);
	subtype mmu_tc_t is std_logic_vector(31 downto 0);
	subtype mmu_tt_t is std_logic_vector(31 downto 0);
	subtype mmu_status_t is std_logic_vector(15 downto 0);

	constant MMU_TC_ENABLE_BIT : natural := 31;
	constant MMU_TC_SRE_BIT : natural := 25;
	constant MMU_TC_FCL_BIT : natural := 24;
	constant MMU_TC_PS_HIGH : natural := 23;
	constant MMU_TC_PS_LOW : natural := 20;
	constant MMU_TC_IS_HIGH : natural := 19;
	constant MMU_TC_IS_LOW : natural := 16;
	constant MMU_TC_IMPLEMENTED_MASK : mmu_tc_t := x"83FFFFFF";

	constant MMU_ROOT_DT_HIGH : natural := 33;
	constant MMU_ROOT_DT_LOW : natural := 32;
	constant MMU_ROOT_IMPLEMENTED_MASK : mmu_root_pointer_t :=
		x"FFFF0003FFFFFFF0";

	constant MMU_TT_ENABLE_BIT : natural := 15;
	constant MMU_TT_CACHE_INHIBIT_BIT : natural := 10;
	constant MMU_TT_READ_WRITE_BIT : natural := 9;
	constant MMU_TT_READ_WRITE_MASK_BIT : natural := 8;
	constant MMU_TT_IMPLEMENTED_MASK : mmu_tt_t := x"FFFF8777";

	constant MMU_STATUS_IMPLEMENTED_MASK : mmu_status_t := x"EE47";
	constant MMU_DESCRIPTOR_TYPE_INVALID : std_logic_vector(1 downto 0) := "00";
	constant MMU_DESCRIPTOR_TYPE_PAGE : std_logic_vector(1 downto 0) := "01";
	constant MMU_DESCRIPTOR_TYPE_SHORT : std_logic_vector(1 downto 0) := "10";
	constant MMU_DESCRIPTOR_TYPE_LONG : std_logic_vector(1 downto 0) := "11";
	constant MMU_DESCRIPTOR_WRITE_PROTECT_BIT : natural := 2;
	constant MMU_DESCRIPTOR_USED_BIT : natural := 3;
	constant MMU_DESCRIPTOR_MODIFIED_BIT : natural := 4;
	constant MMU_DESCRIPTOR_CACHE_INHIBIT_BIT : natural := 6;
	constant MMU_LONG_DESCRIPTOR_SUPERVISOR_BIT : natural := 40;

	type mmu_descriptor_info_t is record
		kind : mmu_descriptor_kind_t;
		descriptor_type : std_logic_vector(1 downto 0);
		next_format : mmu_descriptor_format_t;
		address_field : std_logic_vector(31 downto 0);
		limit_present : std_logic;
		limit_lower : std_logic;
		limit : std_logic_vector(14 downto 0);
		early_termination : std_logic;
		supervisor_only : std_logic;
		cache_inhibit : std_logic;
		write_protect : std_logic;
		used : std_logic;
		modified : std_logic;
	end record;

	constant MMU_DESCRIPTOR_INFO_DEFAULT : mmu_descriptor_info_t := (
		kind => MMU_DESCRIPTOR_INVALID,
		descriptor_type => MMU_DESCRIPTOR_TYPE_INVALID,
		next_format => MMU_DESCRIPTOR_SHORT,
		address_field => (others => '0'),
		limit_present => '0',
		limit_lower => '0',
		limit => (others => '0'),
		early_termination => '0',
		supervisor_only => '0',
		cache_inhibit => '0',
		write_protect => '0',
		used => '0',
		modified => '0'
	);

	function mmu_tc_configuration_valid(value : mmu_tc_t) return boolean;
	function mmu_root_configuration_valid(
		value : mmu_root_pointer_t) return boolean;
	function mmu_decode_descriptor(
		value : std_logic_vector(63 downto 0);
		format : mmu_descriptor_format_t;
		leaf_level : std_logic) return mmu_descriptor_info_t;
end package;

package body TG68K_MMU_Pack is
	function mmu_tc_configuration_valid(value : mmu_tc_t) return boolean is
		type table_size_array_t is array (0 to 3) of natural range 0 to 15;
		variable table_size : table_size_array_t;
		variable table_sum : natural range 0 to 60 := 0;
		variable zero_seen : boolean := false;
		variable page_size : natural range 0 to 15;
		variable initial_shift : natural range 0 to 15;
	begin
		page_size := to_integer(unsigned(value(MMU_TC_PS_HIGH downto
			MMU_TC_PS_LOW)));
		initial_shift := to_integer(unsigned(value(MMU_TC_IS_HIGH downto
			MMU_TC_IS_LOW)));
		table_size(0) := to_integer(unsigned(value(15 downto 12)));
		table_size(1) := to_integer(unsigned(value(11 downto 8)));
		table_size(2) := to_integer(unsigned(value(7 downto 4)));
		table_size(3) := to_integer(unsigned(value(3 downto 0)));

		if page_size < 8 then
			return false;
		end if;
		if value(MMU_TC_ENABLE_BIT) = '0' then
			return true;
		end if;

		for index in table_size'range loop
			if table_size(index) = 0 then
				zero_seen := true;
			elsif not zero_seen then
				table_sum := table_sum + table_size(index);
			end if;
		end loop;
		return initial_shift + page_size + table_sum = 32;
	end function;

	function mmu_root_configuration_valid(
		value : mmu_root_pointer_t) return boolean is
	begin
		return value(MMU_ROOT_DT_HIGH downto MMU_ROOT_DT_LOW) /= "00";
	end function;

	function mmu_decode_descriptor(
		value : std_logic_vector(63 downto 0);
		format : mmu_descriptor_format_t;
		leaf_level : std_logic) return mmu_descriptor_info_t is
		variable result : mmu_descriptor_info_t := MMU_DESCRIPTOR_INFO_DEFAULT;
		variable descriptor_type : std_logic_vector(1 downto 0);
	begin
		if format = MMU_DESCRIPTOR_SHORT then
			descriptor_type := value(1 downto 0);
		else
			descriptor_type := value(33 downto 32);
		end if;
		result.descriptor_type := descriptor_type;
		if descriptor_type = MMU_DESCRIPTOR_TYPE_LONG then
			result.next_format := MMU_DESCRIPTOR_LONG;
		end if;

		case format is
			when MMU_DESCRIPTOR_ROOT =>
				if descriptor_type = MMU_DESCRIPTOR_TYPE_PAGE then
					result.kind := MMU_DESCRIPTOR_PAGE;
					result.early_termination := '1';
					result.address_field := value(31 downto 4) & "0000";
				elsif descriptor_type = MMU_DESCRIPTOR_TYPE_SHORT or
						descriptor_type = MMU_DESCRIPTOR_TYPE_LONG then
					result.kind := MMU_DESCRIPTOR_TABLE;
					result.address_field := value(31 downto 4) & "0000";
				end if;
				if result.kind /= MMU_DESCRIPTOR_INVALID then
					result.limit_present := '1';
					result.limit_lower := value(63);
					result.limit := value(62 downto 48);
				end if;

			when MMU_DESCRIPTOR_SHORT =>
				if descriptor_type = MMU_DESCRIPTOR_TYPE_PAGE then
					result.kind := MMU_DESCRIPTOR_PAGE;
					result.early_termination := not leaf_level;
					result.address_field := value(31 downto 8) & x"00";
					result.cache_inhibit := value(MMU_DESCRIPTOR_CACHE_INHIBIT_BIT);
					result.modified := value(MMU_DESCRIPTOR_MODIFIED_BIT);
					result.used := value(MMU_DESCRIPTOR_USED_BIT);
					result.write_protect := value(MMU_DESCRIPTOR_WRITE_PROTECT_BIT);
				elsif descriptor_type = MMU_DESCRIPTOR_TYPE_SHORT or
						descriptor_type = MMU_DESCRIPTOR_TYPE_LONG then
					if leaf_level = '1' then
						result.kind := MMU_DESCRIPTOR_INDIRECT;
						result.address_field := value(31 downto 2) & "00";
					else
						result.kind := MMU_DESCRIPTOR_TABLE;
						result.address_field := value(31 downto 4) & "0000";
						result.used := value(MMU_DESCRIPTOR_USED_BIT);
						result.write_protect := value(MMU_DESCRIPTOR_WRITE_PROTECT_BIT);
					end if;
				end if;

			when MMU_DESCRIPTOR_LONG =>
				if descriptor_type = MMU_DESCRIPTOR_TYPE_PAGE then
					result.kind := MMU_DESCRIPTOR_PAGE;
					result.early_termination := not leaf_level;
					result.address_field := value(31 downto 8) & x"00";
					result.supervisor_only := value(MMU_LONG_DESCRIPTOR_SUPERVISOR_BIT);
					result.cache_inhibit := value(32 + MMU_DESCRIPTOR_CACHE_INHIBIT_BIT);
					result.modified := value(32 + MMU_DESCRIPTOR_MODIFIED_BIT);
					result.used := value(32 + MMU_DESCRIPTOR_USED_BIT);
					result.write_protect := value(32 + MMU_DESCRIPTOR_WRITE_PROTECT_BIT);
					if leaf_level = '0' then
						result.limit_present := '1';
						result.limit_lower := value(63);
						result.limit := value(62 downto 48);
					end if;
				elsif descriptor_type = MMU_DESCRIPTOR_TYPE_SHORT or
						descriptor_type = MMU_DESCRIPTOR_TYPE_LONG then
					if leaf_level = '1' then
						result.kind := MMU_DESCRIPTOR_INDIRECT;
						result.address_field := value(31 downto 2) & "00";
					else
						result.kind := MMU_DESCRIPTOR_TABLE;
						result.address_field := value(31 downto 4) & "0000";
						result.limit_present := '1';
						result.limit_lower := value(63);
						result.limit := value(62 downto 48);
						result.supervisor_only := value(MMU_LONG_DESCRIPTOR_SUPERVISOR_BIT);
						result.used := value(32 + MMU_DESCRIPTOR_USED_BIT);
						result.write_protect := value(32 + MMU_DESCRIPTOR_WRITE_PROTECT_BIT);
					end if;
				end if;
		end case;
		return result;
	end function;
end package body;
