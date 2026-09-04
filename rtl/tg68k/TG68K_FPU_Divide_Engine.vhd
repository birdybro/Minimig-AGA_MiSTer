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
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Divide_Engine is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		initial_mode : in fpu_divide_initial_t;
		divisor : in unsigned(64 downto 0);
		dividend : in unsigned(64 downto 0);
		forced_subtrahend : in unsigned(64 downto 0);
		iterations : in natural range 0 to 65535;
		nearest_adjust : in std_logic;

		divisor_result : out unsigned(64 downto 0);
		remainder_result : out unsigned(64 downto 0);
		quotient_result : out unsigned(65 downto 0);
		exponent_decrement : out std_logic;
		sign_invert : out std_logic;
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Divide_Engine is
	signal active : std_logic := '0';
	signal remainder_operation : std_logic := '0';
	signal finalize_pending : std_logic := '0';
	signal nearest_adjust_latched : std_logic := '0';
	signal exponent_decrement_register : std_logic := '0';
	signal divisor_register : unsigned(64 downto 0) := (others => '0');
	signal remainder_register : unsigned(64 downto 0) := (others => '0');
	signal quotient_register : unsigned(65 downto 0) := (others => '0');
	signal iterations_remaining : natural range 0 to 65535 := 0;
	signal calculated_remainder : unsigned(64 downto 0);
	signal calculated_quotient : unsigned(65 downto 0);
	signal calculated_sign_invert : std_logic;
	signal completion_pending : std_logic;
begin
	busy <= active;
	completion_pending <= '1' when active = '1' and
		((remainder_operation = '0' and iterations_remaining = 1) or
		(remainder_operation = '1' and finalize_pending = '1')) else '0';
	done <= completion_pending;
	divisor_result <= divisor_register;
	remainder_result <= calculated_remainder when completion_pending = '1' else
		remainder_register;
	quotient_result <= calculated_quotient when completion_pending = '1' else
		quotient_register;
	exponent_decrement <= exponent_decrement_register;
	sign_invert <= calculated_sign_invert when completion_pending = '1' else '0';

	divide_step : process(active, finalize_pending, initial_mode, divisor,
			dividend, forced_subtrahend, divisor_register, remainder_register,
			quotient_register, nearest_adjust_latched)
		variable left_value : unsigned(64 downto 0);
		variable right_value : unsigned(64 downto 0);
		variable next_quotient : unsigned(65 downto 0);
		variable subtract_value : std_logic;
		variable quotient_bit : std_logic;
	begin
		left_value := dividend;
		right_value := divisor;
		next_quotient := (others => '0');
		subtract_value := '0';
		quotient_bit := '0';
		calculated_sign_invert <= '0';

		if active = '1' then
			if finalize_pending = '1' then
				left_value := remainder_register;
				next_quotient := quotient_register;
				if nearest_adjust_latched = '1' and
						(shift_left(remainder_register, 1) > divisor_register or
						(shift_left(remainder_register, 1) = divisor_register and
						quotient_register(0) = '1')) then
					left_value := divisor_register;
					right_value := remainder_register;
					subtract_value := '1';
					next_quotient := quotient_register + 1;
					calculated_sign_invert <= '1';
				end if;
			else
				left_value := shift_left(remainder_register, 1);
				right_value := divisor_register;
				next_quotient := shift_left(quotient_register, 1);
				if left_value >= divisor_register then
					subtract_value := '1';
					quotient_bit := '1';
				end if;
				next_quotient(0) := quotient_bit;
			end if;
		else
			case initial_mode is
				when FPU_DIVIDE_FRACTION =>
					if dividend < divisor then
						left_value := shift_left(dividend, 1);
					end if;
					subtract_value := '1';
					next_quotient(0) := '1';
				when FPU_DIVIDE_REDUCTION =>
					if dividend >= divisor then
						subtract_value := '1';
						next_quotient(0) := '1';
					end if;
				when FPU_DIVIDE_SUBTRACT =>
					right_value := forced_subtrahend;
					subtract_value := '1';
					next_quotient(0) := '1';
				when FPU_DIVIDE_BYPASS => null;
			end case;
		end if;

		if subtract_value = '1' then
			calculated_remainder <= left_value - right_value;
		else
			calculated_remainder <= left_value;
		end if;
		calculated_quotient <= next_quotient;
	end process;

	divide_sequence : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				active <= '0';
				remainder_operation <= '0';
				finalize_pending <= '0';
				nearest_adjust_latched <= '0';
				exponent_decrement_register <= '0';
				divisor_register <= (others => '0');
				remainder_register <= (others => '0');
				quotient_register <= (others => '0');
				iterations_remaining <= 0;
			elsif active = '1' then
				if finalize_pending = '1' then
					remainder_register <= calculated_remainder;
					quotient_register <= calculated_quotient;
					active <= '0';
					finalize_pending <= '0';
				else
					remainder_register <= calculated_remainder;
					quotient_register <= calculated_quotient;
					if iterations_remaining = 1 then
						if remainder_operation = '1' then
							iterations_remaining <= 0;
							finalize_pending <= '1';
						else
							active <= '0';
						end if;
					else
						iterations_remaining <= iterations_remaining - 1;
					end if;
				end if;
			elsif start = '1' then
				active <= '1';
				if initial_mode = FPU_DIVIDE_FRACTION then
					remainder_operation <= '0';
				else
					remainder_operation <= '1';
				end if;
				if initial_mode /= FPU_DIVIDE_FRACTION and iterations = 0 then
					finalize_pending <= '1';
				else
					finalize_pending <= '0';
				end if;
				nearest_adjust_latched <= nearest_adjust;
				if initial_mode = FPU_DIVIDE_FRACTION and dividend < divisor then
					exponent_decrement_register <= '1';
				else
					exponent_decrement_register <= '0';
				end if;
				divisor_register <= divisor;
				remainder_register <= calculated_remainder;
				quotient_register <= calculated_quotient;
				iterations_remaining <= iterations;
			end if;
		end if;
	end process;
end architecture;
