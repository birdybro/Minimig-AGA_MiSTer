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

entity TG68K_MMU is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		register_select : in mmu_register_t;
		register_write : in std_logic;
		register_write_data : in std_logic_vector(63 downto 0);
		flush_disable : in std_logic;
		register_read_data : out std_logic_vector(63 downto 0);
		configuration_exception : out std_logic;
		atc_flush_all : out std_logic;
		translation_enabled : out std_logic;
		supervisor_root_enabled : out std_logic;
		function_code_lookup_enabled : out std_logic;
		crp_out : out mmu_root_pointer_t;
		srp_out : out mmu_root_pointer_t;
		tc_out : out mmu_tc_t;
		tt0_out : out mmu_tt_t;
		tt1_out : out mmu_tt_t;
		mmusr_out : out mmu_status_t
	);
end entity;

architecture rtl of TG68K_MMU is
	signal crp : mmu_root_pointer_t := (others => '0');
	signal srp : mmu_root_pointer_t := (others => '0');
	signal tc : mmu_tc_t := (others => '0');
	signal tt0 : mmu_tt_t := (others => '0');
	signal tt1 : mmu_tt_t := (others => '0');
	signal mmusr : mmu_status_t := (others => '0');
begin
	with register_select select register_read_data <=
		crp when MMU_REG_CRP,
		srp when MMU_REG_SRP,
		x"00000000" & tc when MMU_REG_TC,
		x"00000000" & tt0 when MMU_REG_TT0,
		x"00000000" & tt1 when MMU_REG_TT1,
		x"000000000000" & mmusr when MMU_REG_MMUSR;

	translation_enabled <= tc(MMU_TC_ENABLE_BIT);
	supervisor_root_enabled <= tc(MMU_TC_SRE_BIT);
	function_code_lookup_enabled <= tc(MMU_TC_FCL_BIT);
	crp_out <= crp;
	srp_out <= srp;
	tc_out <= tc;
	tt0_out <= tt0;
	tt1_out <= tt1;
	mmusr_out <= mmusr;

	registers : process(clk)
		variable next_tc : mmu_tc_t;
		variable next_root : mmu_root_pointer_t;
	begin
		if rising_edge(clk) then
			configuration_exception <= '0';
			atc_flush_all <= '0';
			if nReset = '0' then
				tc(MMU_TC_ENABLE_BIT) <= '0';
				tt0(MMU_TT_ENABLE_BIT) <= '0';
				tt1(MMU_TT_ENABLE_BIT) <= '0';
			elsif register_write = '1' then
				case register_select is
					when MMU_REG_CRP =>
						next_root := register_write_data and
							MMU_ROOT_IMPLEMENTED_MASK;
						crp <= next_root;
						if not mmu_root_configuration_valid(next_root) then
							configuration_exception <= '1';
						end if;
						if flush_disable = '0' then
							atc_flush_all <= '1';
						end if;
					when MMU_REG_SRP =>
						next_root := register_write_data and
							MMU_ROOT_IMPLEMENTED_MASK;
						srp <= next_root;
						if not mmu_root_configuration_valid(next_root) then
							configuration_exception <= '1';
						end if;
						if flush_disable = '0' then
							atc_flush_all <= '1';
						end if;
					when MMU_REG_TC =>
						next_tc := register_write_data(31 downto 0) and
							MMU_TC_IMPLEMENTED_MASK;
						if not mmu_tc_configuration_valid(next_tc) then
							next_tc(MMU_TC_ENABLE_BIT) := '0';
							configuration_exception <= '1';
						end if;
						tc <= next_tc;
						if flush_disable = '0' then
							atc_flush_all <= '1';
						end if;
					when MMU_REG_TT0 =>
						tt0 <= register_write_data(31 downto 0) and
							MMU_TT_IMPLEMENTED_MASK;
						if flush_disable = '0' then
							atc_flush_all <= '1';
						end if;
					when MMU_REG_TT1 =>
						tt1 <= register_write_data(31 downto 0) and
							MMU_TT_IMPLEMENTED_MASK;
						if flush_disable = '0' then
							atc_flush_all <= '1';
						end if;
					when MMU_REG_MMUSR =>
						mmusr <= register_write_data(15 downto 0) and
							MMU_STATUS_IMPLEMENTED_MASK;
				end case;
			end if;
		end if;
	end process;
end architecture;
