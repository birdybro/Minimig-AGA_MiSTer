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

entity TG68K_MMU_Transparent is
	port(
		logical_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		write_access : in std_logic;
		read_modify_write : in std_logic;
		tt0 : in mmu_tt_t;
		tt1 : in mmu_tt_t;
		cpu_space_access : out std_logic;
		tt0_match : out std_logic;
		tt1_match : out std_logic;
		transparent_match : out std_logic;
		translation_bypass : out std_logic;
		physical_address : out std_logic_vector(31 downto 0);
		cache_inhibit : out std_logic
	);
end entity;

architecture rtl of TG68K_MMU_Transparent is
	function register_matches(
		value : mmu_tt_t;
		address_value : std_logic_vector(31 downto 0);
		fc_value : std_logic_vector(2 downto 0);
		is_write : std_logic;
		is_read_modify_write : std_logic) return boolean is
		variable address_difference : std_logic_vector(7 downto 0);
		variable function_code_difference : std_logic_vector(2 downto 0);
	begin
		if value(MMU_TT_ENABLE_BIT) = '0' then
			return false;
		end if;
		address_difference := (address_value(MMU_TT_ADDRESS_BASE_HIGH downto
			MMU_TT_ADDRESS_BASE_LOW) xor value(MMU_TT_ADDRESS_BASE_HIGH downto
			MMU_TT_ADDRESS_BASE_LOW)) and not value(MMU_TT_ADDRESS_MASK_HIGH downto
			MMU_TT_ADDRESS_MASK_LOW);
		function_code_difference := (fc_value xor value(
			MMU_TT_FUNCTION_CODE_BASE_HIGH downto MMU_TT_FUNCTION_CODE_BASE_LOW)) and
			not value(MMU_TT_FUNCTION_CODE_MASK_HIGH downto
			MMU_TT_FUNCTION_CODE_MASK_LOW);
		if address_difference /= x"00" or function_code_difference /= "000" then
			return false;
		end if;
		if is_read_modify_write = '1' then
			return value(MMU_TT_READ_WRITE_MASK_BIT) = '1';
		elsif value(MMU_TT_READ_WRITE_MASK_BIT) = '1' then
			return true;
		else
			return value(MMU_TT_READ_WRITE_BIT) = not is_write;
		end if;
	end function;

	signal cpu_space : std_logic;
	signal match0 : std_logic;
	signal match1 : std_logic;
begin
	cpu_space <= '1' when function_code = "111" else '0';
	match0 <= '1' when function_code /= "111" and register_matches(tt0,
		logical_address, function_code, write_access, read_modify_write) else '0';
	match1 <= '1' when function_code /= "111" and register_matches(tt1,
		logical_address, function_code, write_access, read_modify_write) else '0';

	cpu_space_access <= cpu_space;
	tt0_match <= match0;
	tt1_match <= match1;
	transparent_match <= match0 or match1;
	translation_bypass <= cpu_space or match0 or match1;
	physical_address <= logical_address;
	cache_inhibit <= (match0 and tt0(MMU_TT_CACHE_INHIBIT_BIT)) or
		(match1 and tt1(MMU_TT_CACHE_INHIBIT_BIT));
end architecture;
