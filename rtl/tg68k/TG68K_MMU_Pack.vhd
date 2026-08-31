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

	function mmu_tc_configuration_valid(value : mmu_tc_t) return boolean;
	function mmu_root_configuration_valid(
		value : mmu_root_pointer_t) return boolean;
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
end package body;
