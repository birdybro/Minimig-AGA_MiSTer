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
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Round is
	port(
		input_class : in fpu_data_class_t;
		input_sign : in std_logic;
		input_exponent : in signed(16 downto 0);
		input_significand : in unsigned(66 downto 0);
		special_value : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		single_extended_range : in std_logic := '0';

		result : out fpu_extended_t;
		inexact : out std_logic;
		overflow : out std_logic;
		underflow : out std_logic;
		signaling_nan : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Round is
	function or_reduce(value : unsigned) return std_logic is
		variable reduced : std_logic := '0';
	begin
		for index in value'range loop
			reduced := reduced or value(index);
		end loop;
		return reduced;
	end function;

	function shift_right_sticky(
		value : unsigned(66 downto 0);
		amount : natural) return unsigned is
		variable shifted : unsigned(66 downto 0) := (others => '0');
		variable sticky : std_logic := '0';
	begin
		if amount = 0 then
			return value;
		elsif amount >= 67 then
			shifted(0) := or_reduce(value);
			return shifted;
		end if;
		shifted := shift_right(value, amount);
		for index in 0 to 66 loop
			if index < amount then
				sticky := sticky or value(index);
			end if;
		end loop;
		shifted(0) := shifted(0) or sticky;
		return shifted;
	end function;

	function highest_set_bit(value : unsigned(66 downto 0)) return natural is
	begin
		for index in 66 downto 0 loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;
begin
	round_result : process(input_class, input_sign, input_exponent,
		input_significand, special_value, rounding_precision, rounding_mode,
		single_extended_range)
		variable rounded_result : fpu_extended_t;
		variable working_significand : unsigned(66 downto 0);
		variable extended_sum : unsigned(67 downto 0);
		variable exponent_value : integer range -65536 to 65535;
		variable minimum_exponent : integer range -16383 to -126;
		variable maximum_exponent : integer range 127 to 16383;
		variable precision_bits : natural range 24 to 64;
		variable least_retained_bit : natural range 3 to 43;
		variable denormal_shift : natural range 0 to 65535;
		variable normalization_shift : natural range 0 to 66;
		variable discarded : std_logic;
		variable guard : std_logic;
		variable lower_discarded : std_logic;
		variable increment : boolean;
		variable overflow_to_infinity : boolean;
		variable overflow_detected : boolean;
		variable underflow_detected : boolean;
		variable use_single_extended_range : boolean;
		variable biased_exponent : natural range 0 to 32767;
	begin
		rounded_result := (others => '0');
		working_significand := input_significand;
		extended_sum := (others => '0');
		exponent_value := to_integer(input_exponent);
		discarded := '0';
		guard := '0';
		lower_discarded := '0';
		increment := false;
		overflow_to_infinity := false;
		overflow_detected := false;
		underflow_detected := false;
		use_single_extended_range := rounding_precision = FPU_PRECISION_SINGLE and
			single_extended_range = '1';
		biased_exponent := 0;

		case rounding_precision is
			when FPU_PRECISION_SINGLE =>
				precision_bits := 24;
				if use_single_extended_range then
					minimum_exponent := -16383;
					maximum_exponent := 16383;
					if exponent_value < minimum_exponent then
						precision_bits := 64;
					end if;
				else
					minimum_exponent := -126;
					maximum_exponent := 127;
				end if;
			when FPU_PRECISION_DOUBLE =>
				precision_bits := 53;
				minimum_exponent := -1022;
				maximum_exponent := 1023;
			when others =>
				precision_bits := 64;
				minimum_exponent := -16383;
				maximum_exponent := 16383;
		end case;
		least_retained_bit := 67 - precision_bits;

		case input_class is
			when FPU_CLASS_ZERO =>
			rounded_result(79) := input_sign;

			when FPU_CLASS_INFINITY =>
			rounded_result(79) := input_sign;
			rounded_result(78 downto 64) := (others => '1');
			rounded_result(63) := '1';

			when FPU_CLASS_QUIET_NAN | FPU_CLASS_SIGNALING_NAN =>
			rounded_result := special_value;
			rounded_result(78 downto 64) := (others => '1');
			rounded_result(62) := '1';

			when FPU_CLASS_NORMAL =>
				if working_significand = 0 then
					rounded_result(79) := input_sign;
				else
					if rounding_precision = FPU_PRECISION_EXTENDED or
							rounding_precision = FPU_PRECISION_RESERVED or
							use_single_extended_range then
						underflow_detected := exponent_value < minimum_exponent;
					else
						underflow_detected := exponent_value <= minimum_exponent;
					end if;

					if exponent_value < minimum_exponent then
						denormal_shift := minimum_exponent - exponent_value;
						working_significand := shift_right_sticky(
							working_significand, denormal_shift);
						exponent_value := minimum_exponent;
					end if;

					for index in 0 to 42 loop
						if index < least_retained_bit then
							discarded := discarded or working_significand(index);
						end if;
					end loop;
					guard := working_significand(least_retained_bit - 1);
					for index in 0 to 41 loop
						if index < least_retained_bit - 1 then
							lower_discarded := lower_discarded or
								working_significand(index);
						end if;
					end loop;

					case rounding_mode is
						when FPU_ROUND_NEAREST =>
							increment := guard = '1' and
								(lower_discarded = '1' or
								 working_significand(least_retained_bit) = '1');
						when FPU_ROUND_ZERO =>
							increment := false;
						when FPU_ROUND_MINUS_INFINITY =>
							increment := input_sign = '1' and discarded = '1';
						when FPU_ROUND_PLUS_INFINITY =>
							increment := input_sign = '0' and discarded = '1';
					end case;

					extended_sum := resize(working_significand, 68);
					if increment then
						extended_sum := extended_sum +
							shift_left(to_unsigned(1, 68), least_retained_bit);
					end if;
					if extended_sum(67) = '1' then
						working_significand := extended_sum(67 downto 1);
						exponent_value := exponent_value + 1;
					else
						working_significand := extended_sum(66 downto 0);
					end if;
					for index in 0 to 42 loop
						if index < least_retained_bit then
							working_significand(index) := '0';
						end if;
					end loop;

					if not use_single_extended_range and
							rounding_precision /= FPU_PRECISION_EXTENDED and
							rounding_precision /= FPU_PRECISION_RESERVED and
							working_significand /= 0 and
							working_significand(66) = '0' then
						normalization_shift := 66 -
							highest_set_bit(working_significand);
						working_significand := shift_left(
							working_significand, normalization_shift);
						exponent_value := exponent_value - normalization_shift;
					end if;

					overflow_detected := exponent_value > maximum_exponent;
					if overflow_detected then
						case rounding_mode is
							when FPU_ROUND_NEAREST =>
								overflow_to_infinity := true;
							when FPU_ROUND_ZERO =>
								overflow_to_infinity := false;
							when FPU_ROUND_MINUS_INFINITY =>
								overflow_to_infinity := input_sign = '1';
							when FPU_ROUND_PLUS_INFINITY =>
								overflow_to_infinity := input_sign = '0';
						end case;
						rounded_result(79) := input_sign;
						if overflow_to_infinity then
							rounded_result(78 downto 64) := (others => '1');
							rounded_result(63) := '1';
						else
							biased_exponent := maximum_exponent +
								FPU_EXTENDED_EXPONENT_BIAS;
							rounded_result(78 downto 64) := std_logic_vector(
								to_unsigned(biased_exponent, 15));
							if use_single_extended_range then
								rounded_result(63 downto 0) := (others => '1');
							else
								for index in 0 to 63 loop
									if index >= 64 - precision_bits then
										rounded_result(index) := '1';
									end if;
								end loop;
							end if;
						end if;
					else
						rounded_result(79) := input_sign;
						if working_significand = 0 then
							rounded_result(78 downto 0) := (others => '0');
						else
							biased_exponent := exponent_value +
								FPU_EXTENDED_EXPONENT_BIAS;
							rounded_result(78 downto 64) := std_logic_vector(
								to_unsigned(biased_exponent, 15));
							rounded_result(63 downto 0) := std_logic_vector(
								working_significand(66 downto 3));
						end if;
					end if;
				end if;
		end case;

		result <= rounded_result;
		if discarded = '1' or overflow_detected then
			inexact <= '1';
		else
			inexact <= '0';
		end if;
		if overflow_detected then
			overflow <= '1';
		else
			overflow <= '0';
		end if;
		if underflow_detected then
			underflow <= '1';
		else
			underflow <= '0';
		end if;
		if input_class = FPU_CLASS_SIGNALING_NAN then
			signaling_nan <= '1';
		else
			signaling_nan <= '0';
		end if;
	end process;
end architecture;
