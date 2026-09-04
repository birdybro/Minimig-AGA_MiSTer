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

entity TG68K_FPU_Remainder is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		ieee_remainder : in std_logic;
		source : in fpu_extended_t;
		destination : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		reduction_start : out std_logic;
		reduction_initial_mode : out fpu_divide_initial_t;
		reduction_divisor : out unsigned(64 downto 0);
		reduction_dividend : out unsigned(64 downto 0);
		reduction_forced_subtrahend : out unsigned(64 downto 0);
		reduction_iterations : out natural range 0 to 65535;
		reduction_nearest_adjust : out std_logic;
		reduction_remainder : in unsigned(64 downto 0);
		reduction_quotient : in unsigned(65 downto 0);
		reduction_sign_invert : in std_logic;
		reduction_done : in std_logic;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		quotient : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Remainder is
	type remainder_state_t is (IDLE, REDUCE, COMPLETE);

	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	signal state : remainder_state_t := IDLE;
	signal prepared_initial_mode : fpu_divide_initial_t := FPU_DIVIDE_BYPASS;
	signal prepared_divisor : unsigned(64 downto 0) := (others => '0');
	signal prepared_dividend : unsigned(64 downto 0) := (others => '0');
	signal prepared_forced_subtrahend : unsigned(64 downto 0) :=
		(others => '0');
	signal prepared_iterations : natural range 0 to 65535 := 0;
	signal prepared_nearest_adjust : std_logic := '0';
	signal prepared_exponent : signed(16 downto 0) := (others => '0');
	signal prepared_sign : std_logic := '0';
	signal reduction_operand_valid : std_logic := '0';
	signal remainder_exponent : signed(16 downto 0) := (others => '0');
	signal destination_sign : std_logic := '0';
	signal quotient_sign : std_logic := '0';
	signal quotient_result : std_logic_vector(7 downto 0) := (others => '0');

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
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	quotient <= quotient_result;
	reduction_start <= '1' when state = IDLE and start = '1' and
		reduction_operand_valid = '1' else '0';
	reduction_initial_mode <= prepared_initial_mode;
	reduction_divisor <= prepared_divisor;
	reduction_dividend <= prepared_dividend;
	reduction_forced_subtrahend <= prepared_forced_subtrahend;
	reduction_iterations <= prepared_iterations;
	reduction_nearest_adjust <= prepared_nearest_adjust;
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	base_exception_status <= "0" & signaling_nan_detected &
		operand_error_detected & "00000";

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

	prepare_reduction : process(source, destination, ieee_remainder)
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable source_exponent : integer range -65536 to 65535;
		variable destination_exponent : integer range -65536 to 65535;
		variable exponent_difference : integer range -65536 to 65535;
		variable source_significand : unsigned(63 downto 0);
		variable destination_significand : unsigned(63 downto 0);
		variable source_shift : natural range 0 to 63;
		variable destination_shift : natural range 0 to 63;
	begin
		source_class := fpu_classify(source);
		destination_class := fpu_classify(destination);
		source_exponent := fpu_unbiased_exponent(source);
		destination_exponent := fpu_unbiased_exponent(destination);
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

		prepared_initial_mode <= FPU_DIVIDE_BYPASS;
		prepared_divisor <= resize(source_significand, 65);
		prepared_dividend <= resize(destination_significand, 65);
		prepared_forced_subtrahend <= resize(destination_significand, 65);
		prepared_iterations <= 0;
		prepared_nearest_adjust <= '0';
		prepared_exponent <= to_signed(destination_exponent, 17);
		prepared_sign <= destination(79);
		exponent_difference := destination_exponent - source_exponent;
		if exponent_difference < 0 then
			if ieee_remainder = '1' and exponent_difference = -1 and
					destination_significand > source_significand then
				prepared_initial_mode <= FPU_DIVIDE_SUBTRACT;
				prepared_dividend <=
					shift_left(resize(source_significand, 65), 1);
				prepared_sign <= not destination(79);
			end if;
		else
			prepared_initial_mode <= FPU_DIVIDE_REDUCTION;
			prepared_iterations <= exponent_difference;
			prepared_nearest_adjust <= ieee_remainder;
			prepared_exponent <= to_signed(source_exponent, 17);
		end if;
		if source_class = FPU_CLASS_NORMAL and source_significand /= 0 and
				destination_class = FPU_CLASS_NORMAL and
				destination_significand /= 0 then
			reduction_operand_valid <= '1';
		else
			reduction_operand_valid <= '0';
		end if;
	end process;

	remainder_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable destination_significand : unsigned(63 downto 0);
		variable selected_nan : fpu_extended_t;
		variable final_remainder : unsigned(63 downto 0);
		variable final_sign : std_logic;
		variable final_shift : natural range 0 to 63;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				remainder_exponent <= (others => '0');
				destination_sign <= '0';
				quotient_sign <= '0';
				quotient_result <= (others => '0');
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				intermediate_exponent <= (others => '0');
				intermediate_significand <= (others => '0');
				intermediate_special <= (others => '0');
				signaling_nan_detected <= '0';
				operand_error_detected <= '0';
			else
				case state is
					when IDLE =>
						if start = '1' then
							source_class := fpu_classify(source);
							destination_class := fpu_classify(destination);
							source_significand := unsigned(source(63 downto 0));
							destination_significand :=
								unsigned(destination(63 downto 0));

							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= destination(79);
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							signaling_nan_detected <= '0';
							operand_error_detected <= '0';
							destination_sign <= destination(79);
							quotient_sign <= source(79) xor destination(79);
							quotient_result <= (source(79) xor destination(79)) &
								"0000000";
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
							elsif source_class = FPU_CLASS_ZERO or
									source_significand = 0 or
									destination_class = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_sign <= '0';
								intermediate_special <= FPU_RESET_NAN;
								operand_error_detected <= '1';
								state <= COMPLETE;
							elsif destination_class = FPU_CLASS_ZERO or
									destination_significand = 0 then
								intermediate_class <= FPU_CLASS_ZERO;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_exponent <=
									prepared_exponent;
								intermediate_significand(66 downto 3) <=
									prepared_dividend(63 downto 0);
								state <= COMPLETE;
							else
								remainder_exponent <= prepared_exponent;
								destination_sign <= prepared_sign;
								state <= REDUCE;
							end if;
						end if;

					when REDUCE =>
						if reduction_done = '1' then
							final_remainder := reduction_remainder(63 downto 0);
							final_sign := destination_sign xor reduction_sign_invert;
							quotient_result <= quotient_sign &
								std_logic_vector(reduction_quotient(6 downto 0));
							intermediate_sign <= final_sign;
							intermediate_special <= (others => '0');
							intermediate_significand <= (others => '0');
							if final_remainder = 0 then
								intermediate_class <= FPU_CLASS_ZERO;
								intermediate_sign <= destination_sign;
								intermediate_exponent <= (others => '0');
							else
								final_shift := 63 - highest_set_bit(final_remainder);
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_exponent <= remainder_exponent -
									to_signed(final_shift, 17);
								intermediate_significand(66 downto 3) <=
									shift_left(final_remainder, final_shift);
							end if;
							state <= COMPLETE;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
