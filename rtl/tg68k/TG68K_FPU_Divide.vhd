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

entity TG68K_FPU_Divide is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		destination : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		single_precision_operation : in std_logic := '0';

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Divide is
	constant QUOTIENT_FRACTION_BITS : natural := 65;
	type divider_state_t is (IDLE, DIVIDE, COMPLETE);

	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	signal state : divider_state_t := IDLE;
	signal divisor_register : unsigned(64 downto 0) := (others => '0');
	signal remainder_register : unsigned(64 downto 0) := (others => '0');
	signal quotient_register : unsigned(65 downto 0) := (others => '0');
	signal iteration_count : natural range 0 to QUOTIENT_FRACTION_BITS - 1 := 0;

	signal intermediate_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal intermediate_sign : std_logic := '0';
	signal intermediate_exponent : signed(16 downto 0) := (others => '0');
	signal intermediate_significand : fpu_significand_grs_t := (others => '0');
	signal intermediate_special : fpu_extended_t := (others => '0');
	signal signaling_nan_detected : std_logic := '0';
	signal operand_error_detected : std_logic := '0';
	signal divide_by_zero_detected : std_logic := '0';

	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
begin
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	base_exception_status <= "0" & signaling_nan_detected &
		operand_error_detected & "00" & divide_by_zero_detected & "00";

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		signal effective_rounding_precision : fpu_rounding_precision_t;
	begin
		effective_rounding_precision <= FPU_PRECISION_SINGLE when
			single_precision_operation = '1' else rounding_precision;
		round_result : entity work.TG68K_FPU_Round
			port map(
				input_class => intermediate_class,
				input_sign => intermediate_sign,
				input_exponent => intermediate_exponent,
				input_significand => intermediate_significand,
				special_value => intermediate_special,
				rounding_precision => effective_rounding_precision,
				rounding_mode => rounding_mode,
				single_extended_range => single_precision_operation,
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
			operand_error_detected, divide_by_zero_detected, rounded_inexact,
			rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		status(5) := operand_error_detected;
		status(4) := rounded_overflow;
		status(3) := rounded_underflow;
		status(2) := divide_by_zero_detected;
		status(1) := rounded_inexact;
		result <= rounded_result;
		condition_codes <= fpu_condition_codes(rounded_result);
		exception_status <= status;
	end process;

	divider_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable source_exponent : integer range -65536 to 65535;
		variable destination_exponent : integer range -65536 to 65535;
		variable quotient_exponent : integer range -65536 to 65535;
		variable source_significand : unsigned(63 downto 0);
		variable destination_significand : unsigned(63 downto 0);
		variable source_shift : natural range 0 to 63;
		variable destination_shift : natural range 0 to 63;
		variable selected_nan : fpu_extended_t;
		variable shifted_remainder : unsigned(64 downto 0);
		variable next_remainder : unsigned(64 downto 0);
		variable next_quotient : unsigned(65 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				divisor_register <= (others => '0');
				remainder_register <= (others => '0');
				quotient_register <= (others => '0');
				iteration_count <= 0;
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				intermediate_exponent <= (others => '0');
				intermediate_significand <= (others => '0');
				intermediate_special <= (others => '0');
				signaling_nan_detected <= '0';
				operand_error_detected <= '0';
				divide_by_zero_detected <= '0';
			else
				case state is
					when IDLE =>
						if start = '1' then
							source_class := fpu_classify(source);
							destination_class := fpu_classify(destination);
							source_exponent := fpu_unbiased_exponent(source);
							destination_exponent :=
								fpu_unbiased_exponent(destination);
							source_significand := unsigned(source(63 downto 0));
							destination_significand :=
								unsigned(destination(63 downto 0));
							source_shift := 0;
							destination_shift := 0;
							if source_class = FPU_CLASS_NORMAL and
									source_significand /= 0 then
								source_shift := 63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									source_shift);
								source_exponent := source_exponent - source_shift;
							end if;
							if destination_class = FPU_CLASS_NORMAL and
									destination_significand /= 0 then
								destination_shift :=
									63 - highest_set_bit(destination_significand);
								destination_significand :=
									shift_left(destination_significand,
										destination_shift);
								destination_exponent :=
									destination_exponent - destination_shift;
							end if;
							if single_precision_operation = '1' then
								source_significand(39 downto 0) := (others => '0');
								destination_significand(39 downto 0) :=
									(others => '0');
							end if;

							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= source(79) xor destination(79);
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							signaling_nan_detected <= '0';
							operand_error_detected <= '0';
							divide_by_zero_detected <= '0';
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
								state <= COMPLETE;
							elsif (source_class = FPU_CLASS_ZERO and
									destination_class = FPU_CLASS_ZERO) or
									(source_class = FPU_CLASS_INFINITY and
									destination_class = FPU_CLASS_INFINITY) then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_sign <= '0';
								intermediate_special <= FPU_RESET_NAN;
								operand_error_detected <= '1';
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_ZERO then
								intermediate_class <= FPU_CLASS_INFINITY;
								if destination_class = FPU_CLASS_NORMAL then
									divide_by_zero_detected <= '1';
								end if;
								state <= COMPLETE;
							elsif destination_class = FPU_CLASS_ZERO or
									source_class = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_ZERO;
								state <= COMPLETE;
							elsif destination_class = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_INFINITY;
								state <= COMPLETE;
							else
								quotient_exponent :=
									destination_exponent - source_exponent;
								divisor_register <= resize(source_significand, 65);
								if destination_significand < source_significand then
									remainder_register <=
										shift_left(resize(destination_significand, 65), 1) -
										resize(source_significand, 65);
									quotient_exponent := quotient_exponent - 1;
								else
									remainder_register <=
										resize(destination_significand, 65) -
										resize(source_significand, 65);
								end if;
								quotient_register <= (0 => '1', others => '0');
								iteration_count <= 0;
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_exponent <=
									to_signed(quotient_exponent, 17);
								state <= DIVIDE;
							end if;
						end if;

					when DIVIDE =>
						shifted_remainder := shift_left(remainder_register, 1);
						next_quotient := shift_left(quotient_register, 1);
						if shifted_remainder >= divisor_register then
							next_remainder := shifted_remainder - divisor_register;
							next_quotient(0) := '1';
						else
							next_remainder := shifted_remainder;
							next_quotient(0) := '0';
						end if;
						remainder_register <= next_remainder;
						quotient_register <= next_quotient;
						if iteration_count = QUOTIENT_FRACTION_BITS - 1 then
							intermediate_significand(66 downto 3) <=
								next_quotient(65 downto 2);
							intermediate_significand(2) <= next_quotient(1);
							intermediate_significand(1) <= next_quotient(0);
							if next_remainder /= 0 then
								intermediate_significand(0) <= '1';
							else
								intermediate_significand(0) <= '0';
							end if;
							state <= COMPLETE;
						else
							iteration_count <= iteration_count + 1;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
