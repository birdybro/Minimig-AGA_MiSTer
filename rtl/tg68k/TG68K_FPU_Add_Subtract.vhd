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

entity TG68K_FPU_Add_Subtract is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		source : in fpu_extended_t;
		destination : in fpu_extended_t;
		subtract : in std_logic;
		compare_only : in std_logic;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0);
		compare_result_condition_codes : out std_logic_vector(3 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Add_Subtract is
	subtype arithmetic_significand_t is unsigned(66 downto 0);

	function or_reduce(value : unsigned) return std_logic is
		variable reduced : std_logic := '0';
	begin
		for index in value'range loop
			reduced := reduced or value(index);
		end loop;
		return reduced;
	end function;

	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	function shift_right_sticky(
		value : arithmetic_significand_t;
		amount : natural) return arithmetic_significand_t is
		variable shifted : arithmetic_significand_t := (others => '0');
		variable sticky : std_logic := '0';
	begin
		if amount = 0 then
			return value;
		elsif amount >= arithmetic_significand_t'length then
			shifted(0) := or_reduce(value);
			return shifted;
		end if;
		shifted := shift_right(value, amount);
		for index in value'range loop
			if index < amount then
				sticky := sticky or value(index);
			end if;
		end loop;
		shifted(0) := shifted(0) or sticky;
		return shifted;
	end function;

	signal intermediate_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal intermediate_sign : std_logic := '0';
	signal intermediate_exponent : signed(16 downto 0) := (others => '0');
	signal intermediate_significand : fpu_significand_grs_t := (others => '0');
	signal intermediate_special : fpu_extended_t := (others => '0');
	signal signaling_nan_detected : std_logic := '0';
	signal operand_error_detected : std_logic := '0';
	signal compare_condition_codes : std_logic_vector(3 downto 0) :=
		(others => '0');

	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
begin
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	compare_result_condition_codes <= compare_condition_codes;

	base_status : process(compare_only, signaling_nan_detected,
			operand_error_detected)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		if compare_only = '0' then
			status(5) := operand_error_detected;
		end if;
		base_exception_status <= status;
	end process;

	calculate : process(source, destination, subtract, compare_only,
			rounding_mode)
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable source_sign : std_logic;
		variable destination_sign : std_logic;
		variable source_exponent : integer range -65536 to 65535;
		variable destination_exponent : integer range -65536 to 65535;
		variable common_exponent : integer range -65536 to 65535;
		variable result_exponent : integer range -65536 to 65535;
		variable source_significand : unsigned(63 downto 0);
		variable destination_significand : unsigned(63 downto 0);
		variable source_wide : arithmetic_significand_t;
		variable destination_wide : arithmetic_significand_t;
		variable magnitude : arithmetic_significand_t;
		variable sum : unsigned(67 downto 0);
		variable selected_nan : fpu_extended_t;
		variable result_sign : std_logic;
		variable source_shift : natural range 0 to 63;
		variable destination_shift : natural range 0 to 63;
		variable exponent_difference : natural range 0 to 65535;
		variable leading_position : natural range 0 to 66;
		variable normalization_shift : natural range 0 to 66;
		variable comparison : integer range -1 to 1;
	begin
		source_class := fpu_classify(source);
		destination_class := fpu_classify(destination);
		source_sign := source(79) xor subtract;
		destination_sign := destination(79);
		source_significand := unsigned(source(63 downto 0));
		destination_significand := unsigned(destination(63 downto 0));
		source_exponent := fpu_unbiased_exponent(source);
		destination_exponent := fpu_unbiased_exponent(destination);
		source_shift := 0;
		destination_shift := 0;
		if source_class = FPU_CLASS_NORMAL and source_significand /= 0 then
			source_shift := 63 - highest_set_bit(source_significand);
			source_significand := shift_left(source_significand, source_shift);
			source_exponent := source_exponent - source_shift;
		end if;
		if destination_class = FPU_CLASS_NORMAL and
				destination_significand /= 0 then
			destination_shift := 63 - highest_set_bit(destination_significand);
			destination_significand := shift_left(destination_significand,
				destination_shift);
			destination_exponent := destination_exponent - destination_shift;
		end if;

		intermediate_class <= FPU_CLASS_ZERO;
		intermediate_sign <= '0';
		intermediate_exponent <= (others => '0');
		intermediate_significand <= (others => '0');
		intermediate_special <= (others => '0');
		signaling_nan_detected <= '0';
		operand_error_detected <= '0';
		compare_condition_codes <= (others => '0');
		source_wide := (others => '0');
		destination_wide := (others => '0');
		magnitude := (others => '0');
		sum := (others => '0');
		selected_nan := FPU_RESET_NAN;
		result_sign := '0';
		common_exponent := 0;
		result_exponent := 0;
		exponent_difference := 0;
		leading_position := 0;
		normalization_shift := 0;
		comparison := 0;

		if source_class = FPU_CLASS_SIGNALING_NAN or
				destination_class = FPU_CLASS_SIGNALING_NAN then
			signaling_nan_detected <= '1';
		end if;
		if destination_class = FPU_CLASS_QUIET_NAN or
				destination_class = FPU_CLASS_SIGNALING_NAN then
			selected_nan := destination;
		elsif source_class = FPU_CLASS_QUIET_NAN or
				source_class = FPU_CLASS_SIGNALING_NAN then
			selected_nan := source;
		end if;
		selected_nan(62) := '1';

		if source_class = FPU_CLASS_QUIET_NAN or
				source_class = FPU_CLASS_SIGNALING_NAN or
				destination_class = FPU_CLASS_QUIET_NAN or
				destination_class = FPU_CLASS_SIGNALING_NAN then
			intermediate_class <= FPU_CLASS_QUIET_NAN;
			intermediate_sign <= selected_nan(79);
			intermediate_special <= selected_nan;
			compare_condition_codes <= fpu_condition_codes(selected_nan);
		elsif compare_only = '1' then
			if source_class = FPU_CLASS_ZERO and
					destination_class = FPU_CLASS_ZERO then
				comparison := 0;
			elsif destination_sign /= source(79) then
				if destination_sign = '1' then
					comparison := -1;
				else
					comparison := 1;
				end if;
			elsif destination_class = FPU_CLASS_INFINITY then
				if source_class = FPU_CLASS_INFINITY then
					comparison := 0;
				elsif destination_sign = '1' then
					comparison := -1;
				else
					comparison := 1;
				end if;
			elsif source_class = FPU_CLASS_INFINITY then
				if destination_sign = '1' then
					comparison := 1;
				else
					comparison := -1;
				end if;
			elsif destination_class = FPU_CLASS_ZERO then
				if source(79) = '1' then
					comparison := 1;
				else
					comparison := -1;
				end if;
			elsif source_class = FPU_CLASS_ZERO then
				if destination_sign = '1' then
					comparison := -1;
				else
					comparison := 1;
				end if;
			elsif destination_exponent > source_exponent or
					(destination_exponent = source_exponent and
					destination_significand > source_significand) then
				if destination_sign = '1' then
					comparison := -1;
				else
					comparison := 1;
				end if;
			elsif destination_exponent < source_exponent or
					(destination_exponent = source_exponent and
					destination_significand < source_significand) then
				if destination_sign = '1' then
					comparison := 1;
				else
					comparison := -1;
				end if;
			end if;
			case comparison is
				when -1 =>
					intermediate_class <= FPU_CLASS_NORMAL;
					intermediate_sign <= '1';
					intermediate_exponent <= to_signed(0, 17);
					intermediate_significand(66) <= '1';
					compare_condition_codes <= "1000";
				when 1 =>
					intermediate_class <= FPU_CLASS_NORMAL;
					intermediate_exponent <= to_signed(0, 17);
					intermediate_significand(66) <= '1';
					compare_condition_codes <= "0000";
				when others =>
					intermediate_class <= FPU_CLASS_ZERO;
					compare_condition_codes <= "0100";
			end case;
		elsif source_class = FPU_CLASS_INFINITY or
				destination_class = FPU_CLASS_INFINITY then
			if source_class = FPU_CLASS_INFINITY and
					destination_class = FPU_CLASS_INFINITY and
					source_sign /= destination_sign then
				intermediate_class <= FPU_CLASS_QUIET_NAN;
				intermediate_special <= FPU_RESET_NAN;
				operand_error_detected <= '1';
			elsif destination_class = FPU_CLASS_INFINITY then
				intermediate_class <= FPU_CLASS_INFINITY;
				intermediate_sign <= destination_sign;
			else
				intermediate_class <= FPU_CLASS_INFINITY;
				intermediate_sign <= source_sign;
			end if;
		elsif source_class = FPU_CLASS_ZERO and
				destination_class = FPU_CLASS_ZERO then
			intermediate_class <= FPU_CLASS_ZERO;
			if source_sign = destination_sign then
				intermediate_sign <= destination_sign;
			elsif rounding_mode = FPU_ROUND_MINUS_INFINITY then
				intermediate_sign <= '1';
			end if;
		else
			source_wide(66 downto 3) := source_significand;
			destination_wide(66 downto 3) := destination_significand;
			if source_class = FPU_CLASS_ZERO then
				source_wide := (others => '0');
				source_exponent := destination_exponent;
			end if;
			if destination_class = FPU_CLASS_ZERO then
				destination_wide := (others => '0');
				destination_exponent := source_exponent;
			end if;
			if destination_exponent >= source_exponent then
				common_exponent := destination_exponent;
				exponent_difference := destination_exponent - source_exponent;
				source_wide := shift_right_sticky(source_wide,
					exponent_difference);
			else
				common_exponent := source_exponent;
				exponent_difference := source_exponent - destination_exponent;
				destination_wide := shift_right_sticky(destination_wide,
					exponent_difference);
			end if;
			if source_sign = destination_sign then
				sum := resize(source_wide, 68) + resize(destination_wide, 68);
				if sum(67) = '1' then
					magnitude := sum(67 downto 1);
					magnitude(0) := magnitude(0) or sum(0);
					common_exponent := common_exponent + 1;
				else
					magnitude := sum(66 downto 0);
				end if;
				result_sign := destination_sign;
			elsif destination_wide > source_wide then
				magnitude := destination_wide - source_wide;
				result_sign := destination_sign;
			elsif source_wide > destination_wide then
				magnitude := source_wide - destination_wide;
				result_sign := source_sign;
			else
				magnitude := (others => '0');
				if rounding_mode = FPU_ROUND_MINUS_INFINITY then
					result_sign := '1';
				end if;
			end if;
			if magnitude = 0 then
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= result_sign;
			else
				leading_position := highest_set_bit(magnitude);
				result_exponent := common_exponent + leading_position - 66;
				normalization_shift := 66 - leading_position;
				magnitude := shift_left(magnitude, normalization_shift);
				intermediate_class <= FPU_CLASS_NORMAL;
				intermediate_sign <= result_sign;
				intermediate_exponent <= to_signed(result_exponent, 17);
				intermediate_significand <= magnitude;
			end if;
		end if;
	end process;

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		round_result : entity work.TG68K_FPU_Round
			port map(
				input_class => intermediate_class,
				input_sign => intermediate_sign,
				input_exponent => intermediate_exponent,
				input_significand => intermediate_significand,
				special_value => intermediate_special,
				rounding_precision => rounding_precision,
				rounding_mode => rounding_mode,
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

	outputs : process(compare_only, compare_condition_codes, rounded_result,
			signaling_nan_detected, operand_error_detected, rounded_inexact,
			rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		if compare_only = '0' then
			status(5) := operand_error_detected;
			status(4) := rounded_overflow;
			status(3) := rounded_underflow;
			status(1) := rounded_inexact;
		end if;
		result <= rounded_result;
		if compare_only = '1' then
			condition_codes <= compare_condition_codes;
		else
			condition_codes <= fpu_condition_codes(rounded_result);
		end if;
		exception_status <= status;
	end process;
end architecture;
