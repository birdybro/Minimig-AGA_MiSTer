------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2026 TG68K contributors                                    --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU Lesser General Public License as published --
-- by the Free Software Foundation, either version 3 of the License, or     --
--                                                                          --
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TG68K_FPU_Square_Root_Engine is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		narrow_start : in std_logic;
		narrow_radicand : in unsigned(65 downto 0);
		wide_start : in std_logic;
		wide_radicand : in unsigned(225 downto 0);

		root_result : out unsigned(112 downto 0);
		remainder_nonzero : out std_logic;
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Square_Root_Engine is
	constant NARROW_ROOT_BITS : natural := 66;
	constant WIDE_ROOT_BITS : natural := 113;

	signal active : std_logic := '0';
	signal final_iteration : natural range 0 to WIDE_ROOT_BITS - 1 := 0;
	signal iteration_count : natural range 0 to WIDE_ROOT_BITS - 1 := 0;
	signal radicand_register : unsigned(225 downto 0) := (others => '0');
	signal remainder_register : unsigned(115 downto 0) := (others => '0');
	signal root_register : unsigned(112 downto 0) := (others => '0');
	signal next_remainder : unsigned(115 downto 0);
	signal next_root : unsigned(112 downto 0);
begin
	busy <= active;
	done <= '1' when active = '1' and iteration_count = final_iteration else '0';
	root_result <= next_root when active = '1' else root_register;
	remainder_nonzero <= '1' when
		(active = '1' and next_remainder /= 0) or
		(active = '0' and remainder_register /= 0) else '0';

	root_step : process(radicand_register, remainder_register, root_register)
		variable shifted_remainder : unsigned(115 downto 0);
		variable trial_divisor : unsigned(115 downto 0);
		variable calculated_remainder : unsigned(115 downto 0);
		variable calculated_root : unsigned(112 downto 0);
	begin
		shifted_remainder := shift_left(remainder_register, 2);
		shifted_remainder(1 downto 0) := radicand_register(225 downto 224);
		trial_divisor := shift_left(resize(root_register,
			trial_divisor'length), 2);
		trial_divisor(0) := '1';
		calculated_root := shift_left(root_register, 1);
		if shifted_remainder >= trial_divisor then
			calculated_remainder := shifted_remainder - trial_divisor;
			calculated_root(0) := '1';
		else
			calculated_remainder := shifted_remainder;
			calculated_root(0) := '0';
		end if;
		next_remainder <= calculated_remainder;
		next_root <= calculated_root;
	end process;

	root_sequence : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				active <= '0';
				final_iteration <= 0;
				iteration_count <= 0;
				radicand_register <= (others => '0');
				remainder_register <= (others => '0');
				root_register <= (others => '0');
			elsif active = '1' then
				radicand_register <= shift_left(radicand_register, 2);
				remainder_register <= next_remainder;
				root_register <= next_root;
				if iteration_count = final_iteration then
					active <= '0';
				else
					iteration_count <= iteration_count + 1;
				end if;
			elsif wide_start = '1' then
				active <= '1';
				final_iteration <= WIDE_ROOT_BITS - 1;
				iteration_count <= 0;
				radicand_register <= wide_radicand;
				remainder_register <= (others => '0');
				root_register <= (others => '0');
			elsif narrow_start = '1' then
				active <= '1';
				final_iteration <= NARROW_ROOT_BITS - 1;
				iteration_count <= 0;
				radicand_register <= narrow_radicand &
					unsigned'(159 downto 0 => '0');
				remainder_register <= (others => '0');
				root_register <= (others => '0');
			end if;
		end if;
	end process;
end architecture;
