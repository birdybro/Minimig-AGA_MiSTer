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

entity TG68K_FPU_Integer is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		source : in fpu_extended_t;
		force_round_zero : in std_logic;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Integer is
	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	signal intermediate_class : fpu_data_class_t;
	signal intermediate_sign : std_logic;
	signal intermediate_exponent : signed(16 downto 0);
	signal intermediate_significand : fpu_significand_grs_t;
	signal intermediate_special : fpu_extended_t;
	signal intermediate_status : std_logic_vector(7 downto 0);
	signal effective_rounding_mode : fpu_rounding_mode_t;
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
begin
	effective_rounding_mode <= FPU_ROUND_ZERO when force_round_zero = '1' else
		rounding_mode;
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	base_exception_status <= intermediate_status;

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		round_result : entity work.TG68K_FPU_Round
			port map(
				input_class => intermediate_class,
				input_sign => intermediate_sign,
				input_exponent => intermediate_exponent,
				input_significand => intermediate_significand,
				special_value => intermediate_special,
				rounding_precision => rounding_precision,
				rounding_mode => effective_rounding_mode,
				result => rounded_result,
				inexact => rounded_inexact,
				overflow => rounded_overflow,
				underflow => rounded_underflow,
				signaling_nan => open
			);
	end generate;

	without_rounding : if not INCLUDE_ROUNDING_STAGE generate
		rounded_result <= (others => '0');
		rounded_inexact <= '0';
		rounded_overflow <= '0';
		rounded_underflow <= '0';
	end generate;

	outputs : process(rounded_result, intermediate_status, rounded_inexact,
			rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := intermediate_status;
		status(4) := rounded_overflow;
		status(3) := rounded_underflow;
		status(1) := intermediate_status(1) or rounded_inexact;
		result <= rounded_result;
		condition_codes <= fpu_condition_codes(rounded_result);
		exception_status <= status;
	end process;

	integral_value : process(source, effective_rounding_mode)
		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable normalized_significand : unsigned(63 downto 0);
		variable integral_significand : unsigned(63 downto 0);
		variable extended_sum : unsigned(64 downto 0);
		variable fractional_value : unsigned(63 downto 0);
		variable half_value : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable result_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable fractional_bits : natural range 1 to 63;
		variable increment : boolean;
		variable inexact : std_logic;
		variable selected_nan : fpu_extended_t;
	begin
		source_class := fpu_classify(source);
		source_significand := unsigned(source(63 downto 0));
		normalized_significand := source_significand;
		integral_significand := (others => '0');
		extended_sum := (others => '0');
		fractional_value := (others => '0');
		half_value := (others => '0');
		source_exponent := to_integer(unsigned(source(78 downto 64))) -
			FPU_EXTENDED_EXPONENT_BIAS;
		if source(78 downto 64) = "000000000000000" then
			source_exponent := 1 - FPU_EXTENDED_EXPONENT_BIAS;
		end if;
		result_exponent := source_exponent;
		normalization_shift := 0;
		fractional_bits := 1;
		increment := false;
		inexact := '0';
		selected_nan := source;
		selected_nan(62) := '1';

		intermediate_class <= FPU_CLASS_ZERO;
		intermediate_sign <= source(79);
		intermediate_exponent <= (others => '0');
		intermediate_significand <= (others => '0');
		intermediate_special <= (others => '0');
		intermediate_status <= (others => '0');

		if source_class = FPU_CLASS_QUIET_NAN or
				source_class = FPU_CLASS_SIGNALING_NAN then
			intermediate_class <= FPU_CLASS_QUIET_NAN;
			intermediate_special <= selected_nan;
			if source_class = FPU_CLASS_SIGNALING_NAN then
				intermediate_status(6) <= '1';
			end if;
		elsif source_class = FPU_CLASS_INFINITY then
			intermediate_class <= FPU_CLASS_INFINITY;
		elsif source_class = FPU_CLASS_ZERO or source_significand = 0 then
			intermediate_class <= FPU_CLASS_ZERO;
		else
			normalization_shift := 63 - highest_set_bit(source_significand);
			normalized_significand := shift_left(source_significand,
				normalization_shift);
			result_exponent := source_exponent - normalization_shift;

			if result_exponent >= 63 then
				integral_significand := normalized_significand;
			elsif result_exponent < 0 then
				inexact := '1';
				case effective_rounding_mode is
					when FPU_ROUND_NEAREST =>
						if result_exponent = -1 and
								normalized_significand > x"8000000000000000" then
							increment := true;
						end if;
					when FPU_ROUND_MINUS_INFINITY =>
						increment := source(79) = '1';
					when FPU_ROUND_PLUS_INFINITY =>
						increment := source(79) = '0';
					when others => null;
				end case;
				if increment then
					result_exponent := 0;
					integral_significand := x"8000000000000000";
				else
					integral_significand := (others => '0');
				end if;
			else
				fractional_bits := 63 - result_exponent;
				integral_significand := shift_left(shift_right(
					normalized_significand, fractional_bits), fractional_bits);
				fractional_value := normalized_significand -
					integral_significand;
				if fractional_value /= 0 then
					inexact := '1';
					case effective_rounding_mode is
						when FPU_ROUND_NEAREST =>
							half_value := shift_left(to_unsigned(1, 64),
								fractional_bits - 1);
							if fractional_value > half_value or
									(fractional_value = half_value and
									integral_significand(fractional_bits) = '1') then
								increment := true;
							end if;
						when FPU_ROUND_MINUS_INFINITY =>
							increment := source(79) = '1';
						when FPU_ROUND_PLUS_INFINITY =>
							increment := source(79) = '0';
						when others => null;
					end case;
				end if;
				if increment then
					extended_sum := resize(integral_significand, 65) +
						shift_left(to_unsigned(1, 65), fractional_bits);
					if extended_sum(64) = '1' then
						integral_significand := extended_sum(64 downto 1);
						result_exponent := result_exponent + 1;
					else
						integral_significand := extended_sum(63 downto 0);
					end if;
				end if;
			end if;

			if integral_significand = 0 then
				intermediate_class <= FPU_CLASS_ZERO;
			else
				intermediate_class <= FPU_CLASS_NORMAL;
				intermediate_exponent <= to_signed(result_exponent, 17);
				intermediate_significand(66 downto 3) <=
					integral_significand;
			end if;
			intermediate_status(1) <= inexact;
		end if;
	end process;
end architecture;
