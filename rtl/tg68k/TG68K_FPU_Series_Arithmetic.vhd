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

entity TG68K_FPU_Series_Arithmetic is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		cube_divide : in std_logic;
		divide_by_six : in std_logic;
		source_significand : in unsigned(63 downto 0);
		product_left : out unsigned(63 downto 0);
		product_right : out unsigned(63 downto 0);
		product_result : in unsigned(127 downto 0);

		square_result : out unsigned(127 downto 0);
		cube_quotient : out unsigned(79 downto 0);
		cube_remainder : out natural range 0 to 5;
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Series_Arithmetic is
	type arithmetic_state_t is (IDLE, SQUARE, CUBE, DIVIDE_CUBE);

	signal state : arithmetic_state_t := IDLE;
	signal product : unsigned(127 downto 0) := (others => '0');
	signal quotient : unsigned(79 downto 0) := (others => '0');
	signal remainder : natural range 0 to 5 := 0;
	signal divisor : natural range 3 to 6 := 3;
	signal iteration : natural range 0 to 79 := 0;
	signal completion : std_logic := '0';
begin
	busy <= '0' when state = IDLE else '1';
	done <= completion;
	product_left <= source_significand;
	-- Cube requests follow a completed square and consume its retained high word.
	product_right <= resize(product(127 downto 112), 64)
		when cube_divide = '1' else
		source_significand;
	square_result <= product;
	cube_quotient <= quotient;
	cube_remainder <= remainder;

	arithmetic_sequence : process(clk)
		variable next_quotient : unsigned(79 downto 0);
		variable division_trial : natural range 0 to 11;
	begin
		if rising_edge(clk) then
			completion <= '0';
			if nReset = '0' then
				state <= IDLE;
				product <= (others => '0');
				quotient <= (others => '0');
				remainder <= 0;
				divisor <= 3;
				iteration <= 0;
			elsif state = IDLE then
				if start = '1' and completion = '0' then
					iteration <= 0;
					-- The shared DSP result is captured immediately; these states
					-- retain the original square/cube completion latency.
					product <= product_result;
					if cube_divide = '1' then
						if divide_by_six = '1' then
							divisor <= 6;
						else
							divisor <= 3;
						end if;
						state <= CUBE;
					else
						state <= SQUARE;
					end if;
				end if;
			else
				case state is
					when SQUARE =>
						if iteration = 63 then
							completion <= '1';
							state <= IDLE;
						else
							iteration <= iteration + 1;
						end if;

					when CUBE =>
						if iteration = 63 then
							quotient <= (others => '0');
							remainder <= 0;
							iteration <= 0;
							state <= DIVIDE_CUBE;
						else
							iteration <= iteration + 1;
						end if;

					when DIVIDE_CUBE =>
						division_trial := remainder * 2;
						if product(79 - iteration) = '1' then
							division_trial := division_trial + 1;
						end if;
						next_quotient := quotient;
						if division_trial >= divisor then
							next_quotient(79 - iteration) := '1';
							division_trial := division_trial - divisor;
						end if;
						if iteration = 79 then
							quotient <= next_quotient;
							remainder <= division_trial;
							completion <= '1';
							state <= IDLE;
						else
							quotient <= next_quotient;
							remainder <= division_trial;
							iteration <= iteration + 1;
						end if;

					when IDLE => null;
				end case;
			end if;
		end if;
	end process;
end architecture;
