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

entity TG68K_FPU_Multiply is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		source : in fpu_extended_t;
		destination : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Multiply is
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

	signal intermediate_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal intermediate_sign : std_logic := '0';
	signal intermediate_exponent : signed(16 downto 0) := (others => '0');
	signal intermediate_significand : fpu_significand_grs_t := (others => '0');
	signal intermediate_special : fpu_extended_t := (others => '0');
	signal signaling_nan_detected : std_logic := '0';
	signal operand_error_detected : std_logic := '0';

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
	base_exception_status <= "0" & signaling_nan_detected &
		operand_error_detected & "00000";

	calculate : process(source, destination)
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable source_exponent : integer range -65536 to 65535;
		variable destination_exponent : integer range -65536 to 65535;
		variable product_exponent : integer range -65536 to 65535;
		variable source_significand : unsigned(63 downto 0);
		variable destination_significand : unsigned(63 downto 0);
		variable product : unsigned(127 downto 0);
		variable selected_nan : fpu_extended_t;
		variable source_shift : natural range 0 to 63;
		variable destination_shift : natural range 0 to 63;
	begin
		source_class := fpu_classify(source);
		destination_class := fpu_classify(destination);
		source_exponent := to_integer(unsigned(source(78 downto 64))) -
			FPU_EXTENDED_EXPONENT_BIAS;
		destination_exponent := to_integer(unsigned(destination(78 downto 64))) -
			FPU_EXTENDED_EXPONENT_BIAS;
		if source(78 downto 64) = "000000000000000" then
			source_exponent := 1 - FPU_EXTENDED_EXPONENT_BIAS;
		end if;
		if destination(78 downto 64) = "000000000000000" then
			destination_exponent := 1 - FPU_EXTENDED_EXPONENT_BIAS;
		end if;
		source_significand := unsigned(source(63 downto 0));
		destination_significand := unsigned(destination(63 downto 0));
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
		intermediate_sign <= source(79) xor destination(79);
		intermediate_exponent <= (others => '0');
		intermediate_significand <= (others => '0');
		intermediate_special <= (others => '0');
		signaling_nan_detected <= '0';
		operand_error_detected <= '0';
		product := (others => '0');
		product_exponent := source_exponent + destination_exponent;
		selected_nan := FPU_RESET_NAN;

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
		elsif (source_class = FPU_CLASS_ZERO and
				destination_class = FPU_CLASS_INFINITY) or
				(source_class = FPU_CLASS_INFINITY and
				destination_class = FPU_CLASS_ZERO) then
			intermediate_class <= FPU_CLASS_QUIET_NAN;
			intermediate_sign <= '0';
			intermediate_special <= FPU_RESET_NAN;
			operand_error_detected <= '1';
		elsif source_class = FPU_CLASS_INFINITY or
				destination_class = FPU_CLASS_INFINITY then
			intermediate_class <= FPU_CLASS_INFINITY;
		elsif source_class = FPU_CLASS_ZERO or
				destination_class = FPU_CLASS_ZERO then
			intermediate_class <= FPU_CLASS_ZERO;
		else
			product := source_significand * destination_significand;
			if product(127) = '1' then
				product_exponent := product_exponent + 1;
				intermediate_significand(66 downto 3) <= product(127 downto 64);
				intermediate_significand(2) <= product(63);
				intermediate_significand(1) <= product(62);
				intermediate_significand(0) <= or_reduce(product(61 downto 0));
			else
				intermediate_significand(66 downto 3) <= product(126 downto 63);
				intermediate_significand(2) <= product(62);
				intermediate_significand(1) <= product(61);
				intermediate_significand(0) <= or_reduce(product(60 downto 0));
			end if;
			intermediate_class <= FPU_CLASS_NORMAL;
			intermediate_exponent <= to_signed(product_exponent, 17);
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

	outputs : process(rounded_result, signaling_nan_detected,
			operand_error_detected, rounded_inexact, rounded_overflow,
			rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		status(5) := operand_error_detected;
		status(4) := rounded_overflow;
		status(3) := rounded_underflow;
		status(1) := rounded_inexact;
		result <= rounded_result;
		condition_codes <= fpu_condition_codes(rounded_result);
		exception_status <= status;
	end process;
end architecture;
