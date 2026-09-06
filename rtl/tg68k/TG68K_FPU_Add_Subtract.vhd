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
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		destination : in fpu_extended_t;
		subtract : in std_logic;
		compare_only : in std_logic;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0);
		compare_result_condition_codes : out std_logic_vector(3 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Add_Subtract is
	subtype arithmetic_significand_t is unsigned(66 downto 0);
	type arithmetic_state_t is (IDLE, NORMALIZE_SOURCE,
		NORMALIZE_DESTINATION, EVALUATE, PREPARE_ALIGNMENT,
		ALIGN_OPERANDS, CALCULATE, NORMALIZE_RESULT, COMPLETE);

	function or_reduce(value : unsigned) return std_logic is
		variable reduced : std_logic := '0';
	begin
		for index in value'range loop
			reduced := reduced or value(index);
		end loop;
		return reduced;
	end function;

	function leading_shift_chunk(value : arithmetic_significand_t)
		return natural is
	begin
		if value(value'high) = '1' or value = 0 then
			return 0;
		end if;
		for offset in 1 to 7 loop
			if value(value'high - offset) = '1' then
				return offset;
			end if;
		end loop;
		return 8;
	end function;

	function shift_right_sticky_chunk(
		value : arithmetic_significand_t;
		amount : natural) return arithmetic_significand_t is
		variable shifted : arithmetic_significand_t := value;
		variable sticky : std_logic := '0';
	begin
		if amount = 0 then
			return value;
		end if;
		shifted := shift_right(value, amount);
		case amount is
			when 1 => sticky := value(0);
			when 2 => sticky := or_reduce(value(1 downto 0));
			when 3 => sticky := or_reduce(value(2 downto 0));
			when 4 => sticky := or_reduce(value(3 downto 0));
			when 5 => sticky := or_reduce(value(4 downto 0));
			when 6 => sticky := or_reduce(value(5 downto 0));
			when 7 => sticky := or_reduce(value(6 downto 0));
			when others => sticky := or_reduce(value(7 downto 0));
		end case;
		shifted(0) := shifted(0) or sticky;
		return shifted;
	end function;

	signal state : arithmetic_state_t := IDLE;
	signal source_class_register : fpu_data_class_t := FPU_CLASS_ZERO;
	signal destination_class_register : fpu_data_class_t := FPU_CLASS_ZERO;
	signal source_operand_sign : std_logic := '0';
	signal source_arithmetic_sign : std_logic := '0';
	signal destination_sign : std_logic := '0';
	signal source_exponent_register : signed(16 downto 0) := (others => '0');
	signal destination_exponent_register : signed(16 downto 0) :=
		(others => '0');
	signal common_exponent_register : signed(16 downto 0) := (others => '0');
	signal result_exponent_register : signed(16 downto 0) := (others => '0');
	signal source_significand_register : arithmetic_significand_t :=
		(others => '0');
	signal destination_significand_register : arithmetic_significand_t :=
		(others => '0');
	signal result_significand_register : arithmetic_significand_t :=
		(others => '0');
	signal result_sign_register : std_logic := '0';
	signal alignment_count : natural range 0 to 66 := 0;
	signal align_source_operand : std_logic := '0';
	signal compare_latched : std_logic := '0';
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal selected_nan_register : fpu_extended_t := FPU_RESET_NAN;

	signal normalization_value : arithmetic_significand_t;
	signal normalization_amount : natural range 0 to 8;
	signal normalized_value : arithmetic_significand_t;
	signal alignment_amount : natural range 0 to 8;
	signal alignment_value : arithmetic_significand_t;
	signal aligned_value : arithmetic_significand_t;
	signal significand_arithmetic_result : unsigned(67 downto 0);

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
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	compare_result_condition_codes <= compare_condition_codes;

	normalization_value <= source_significand_register when
		state = NORMALIZE_SOURCE else destination_significand_register when
		state = NORMALIZE_DESTINATION else result_significand_register;
	normalization_amount <= leading_shift_chunk(normalization_value);
	normalized_value <= shift_left(normalization_value, normalization_amount);
	alignment_amount <= 8 when alignment_count > 8 else alignment_count;
	alignment_value <= source_significand_register when
		align_source_operand = '1' else destination_significand_register;
	aligned_value <= shift_right_sticky_chunk(alignment_value,
		alignment_amount);

	significand_arithmetic : process(source_significand_register,
			destination_significand_register, source_arithmetic_sign,
			destination_sign)
		variable left_value : unsigned(67 downto 0);
		variable right_value : unsigned(67 downto 0);
		variable subtract_value : std_logic;
	begin
		left_value := resize(source_significand_register, left_value'length);
		right_value := resize(destination_significand_register,
			right_value'length);
		subtract_value := '0';
		if source_arithmetic_sign /= destination_sign then
			subtract_value := '1';
			if destination_significand_register >
					source_significand_register then
				left_value := resize(destination_significand_register,
					left_value'length);
				right_value := resize(source_significand_register,
					right_value'length);
			end if;
		end if;
		if subtract_value = '1' then
			significand_arithmetic_result <= left_value - right_value;
		else
			significand_arithmetic_result <= left_value + right_value;
		end if;
	end process;

	base_status : process(compare_latched, signaling_nan_detected,
			operand_error_detected)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		if compare_latched = '0' then
			status(5) := operand_error_detected;
		end if;
		base_exception_status <= status;
	end process;

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		signal precision_latched : fpu_rounding_precision_t :=
			FPU_PRECISION_EXTENDED;
	begin
		capture_precision : process(clk)
		begin
			if rising_edge(clk) then
				if nReset = '0' then
					precision_latched <= FPU_PRECISION_EXTENDED;
				elsif state = IDLE and start = '1' then
					precision_latched <= rounding_precision;
				end if;
			end if;
		end process;

		round_result : entity work.TG68K_FPU_Round
			port map(
				input_class => intermediate_class,
				input_sign => intermediate_sign,
				input_exponent => intermediate_exponent,
				input_significand => intermediate_significand,
				special_value => intermediate_special,
				rounding_precision => precision_latched,
				rounding_mode => mode_latched,
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

	outputs : process(compare_latched, compare_condition_codes, rounded_result,
			signaling_nan_detected, operand_error_detected, rounded_inexact,
			rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		if compare_latched = '0' then
			status(5) := operand_error_detected;
			status(4) := rounded_overflow;
			status(3) := rounded_underflow;
			status(1) := rounded_inexact;
		end if;
		result <= rounded_result;
		if compare_latched = '1' then
			condition_codes <= compare_condition_codes;
		else
			condition_codes <= fpu_condition_codes(rounded_result);
		end if;
		exception_status <= status;
	end process;

	arithmetic_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable selected_nan : fpu_extended_t;
		variable comparison : integer range -1 to 1;
		variable difference : integer range 0 to 65535;
		variable reduced_value : arithmetic_significand_t;
		variable sum : unsigned(67 downto 0);
		variable magnitude : arithmetic_significand_t;
		variable result_sign : std_logic;
		variable result_exponent : signed(16 downto 0);
		variable normalized_exponent : signed(16 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				source_class_register <= FPU_CLASS_ZERO;
				destination_class_register <= FPU_CLASS_ZERO;
				source_operand_sign <= '0';
				source_arithmetic_sign <= '0';
				destination_sign <= '0';
				source_exponent_register <= (others => '0');
				destination_exponent_register <= (others => '0');
				common_exponent_register <= (others => '0');
				result_exponent_register <= (others => '0');
				source_significand_register <= (others => '0');
				destination_significand_register <= (others => '0');
				result_significand_register <= (others => '0');
				result_sign_register <= '0';
				alignment_count <= 0;
				align_source_operand <= '0';
				compare_latched <= '0';
				mode_latched <= FPU_ROUND_NEAREST;
				selected_nan_register <= FPU_RESET_NAN;
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				intermediate_exponent <= (others => '0');
				intermediate_significand <= (others => '0');
				intermediate_special <= (others => '0');
				signaling_nan_detected <= '0';
				operand_error_detected <= '0';
				compare_condition_codes <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							source_class := fpu_classify(source);
							destination_class := fpu_classify(destination);
							source_class_register <= source_class;
							destination_class_register <= destination_class;
							source_operand_sign <= source(79);
							source_arithmetic_sign <= source(79) xor subtract;
							destination_sign <= destination(79);
							source_exponent_register <= to_signed(
								fpu_unbiased_exponent(source), 17);
							destination_exponent_register <= to_signed(
								fpu_unbiased_exponent(destination), 17);
							source_significand_register <=
								unsigned(source(63 downto 0)) & "000";
							destination_significand_register <=
								unsigned(destination(63 downto 0)) & "000";
							compare_latched <= compare_only;
							mode_latched <= rounding_mode;
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= '0';
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							operand_error_detected <= '0';
							compare_condition_codes <= (others => '0');
							if source_class = FPU_CLASS_SIGNALING_NAN or
									destination_class = FPU_CLASS_SIGNALING_NAN then
								signaling_nan_detected <= '1';
							else
								signaling_nan_detected <= '0';
							end if;
							selected_nan := FPU_RESET_NAN;
							if destination_class = FPU_CLASS_QUIET_NAN or
									destination_class = FPU_CLASS_SIGNALING_NAN then
								selected_nan := destination;
							elsif source_class = FPU_CLASS_QUIET_NAN or
									source_class = FPU_CLASS_SIGNALING_NAN then
								selected_nan := source;
							end if;
							selected_nan(62) := '1';
							selected_nan_register <= selected_nan;
							state <= NORMALIZE_SOURCE;
						end if;

					when NORMALIZE_SOURCE =>
						if source_class_register = FPU_CLASS_NORMAL and
								source_significand_register /= 0 and
								source_significand_register(66) = '0' then
							source_significand_register <= normalized_value;
							source_exponent_register <=
								source_exponent_register - normalization_amount;
							if normalized_value(66) = '1' then
								state <= NORMALIZE_DESTINATION;
							end if;
						else
							state <= NORMALIZE_DESTINATION;
						end if;

					when NORMALIZE_DESTINATION =>
						if destination_class_register = FPU_CLASS_NORMAL and
								destination_significand_register /= 0 and
								destination_significand_register(66) = '0' then
							destination_significand_register <= normalized_value;
							destination_exponent_register <=
								destination_exponent_register - normalization_amount;
							if normalized_value(66) = '1' then
								state <= EVALUATE;
							end if;
						else
							state <= EVALUATE;
						end if;

					when EVALUATE =>
						if source_class_register = FPU_CLASS_QUIET_NAN or
								source_class_register = FPU_CLASS_SIGNALING_NAN or
								destination_class_register = FPU_CLASS_QUIET_NAN or
								destination_class_register = FPU_CLASS_SIGNALING_NAN then
							intermediate_class <= FPU_CLASS_QUIET_NAN;
							intermediate_sign <= selected_nan_register(79);
							intermediate_special <= selected_nan_register;
							compare_condition_codes <=
								fpu_condition_codes(selected_nan_register);
							state <= COMPLETE;
						elsif compare_latched = '1' then
							comparison := 0;
							if source_class_register = FPU_CLASS_ZERO and
									destination_class_register = FPU_CLASS_ZERO then
								comparison := 0;
							elsif destination_sign /= source_operand_sign then
								if destination_sign = '1' then
									comparison := -1;
								else
									comparison := 1;
								end if;
							elsif destination_class_register = FPU_CLASS_INFINITY then
								if source_class_register = FPU_CLASS_INFINITY then
									comparison := 0;
								elsif destination_sign = '1' then
									comparison := -1;
								else
									comparison := 1;
								end if;
							elsif source_class_register = FPU_CLASS_INFINITY then
								if destination_sign = '1' then
									comparison := 1;
								else
									comparison := -1;
								end if;
							elsif destination_class_register = FPU_CLASS_ZERO then
								if source_operand_sign = '1' then
									comparison := 1;
								else
									comparison := -1;
								end if;
							elsif source_class_register = FPU_CLASS_ZERO then
								if destination_sign = '1' then
									comparison := -1;
								else
									comparison := 1;
								end if;
							elsif destination_exponent_register >
									source_exponent_register or
									(destination_exponent_register =
									source_exponent_register and
									destination_significand_register >
									source_significand_register) then
								if destination_sign = '1' then
									comparison := -1;
								else
									comparison := 1;
								end if;
							elsif destination_exponent_register <
									source_exponent_register or
									(destination_exponent_register =
									source_exponent_register and
									destination_significand_register <
									source_significand_register) then
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
									intermediate_significand <= (others => '0');
									intermediate_significand(66) <= '1';
									compare_condition_codes <= "1000";
								when 1 =>
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_sign <= '0';
									intermediate_exponent <= to_signed(0, 17);
									intermediate_significand <= (others => '0');
									intermediate_significand(66) <= '1';
									compare_condition_codes <= "0000";
								when others =>
									intermediate_class <= FPU_CLASS_ZERO;
									intermediate_sign <= '0';
									intermediate_exponent <= (others => '0');
									intermediate_significand <= (others => '0');
									compare_condition_codes <= "0100";
							end case;
							state <= COMPLETE;
						elsif source_class_register = FPU_CLASS_INFINITY or
								destination_class_register = FPU_CLASS_INFINITY then
							if source_class_register = FPU_CLASS_INFINITY and
									destination_class_register = FPU_CLASS_INFINITY and
									source_arithmetic_sign /= destination_sign then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_special <= FPU_RESET_NAN;
								operand_error_detected <= '1';
							elsif destination_class_register = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_INFINITY;
								intermediate_sign <= destination_sign;
							else
								intermediate_class <= FPU_CLASS_INFINITY;
								intermediate_sign <= source_arithmetic_sign;
							end if;
							state <= COMPLETE;
						elsif source_class_register = FPU_CLASS_ZERO and
								destination_class_register = FPU_CLASS_ZERO then
							intermediate_class <= FPU_CLASS_ZERO;
							if source_arithmetic_sign = destination_sign then
								intermediate_sign <= destination_sign;
							elsif mode_latched = FPU_ROUND_MINUS_INFINITY then
								intermediate_sign <= '1';
							else
								intermediate_sign <= '0';
							end if;
							state <= COMPLETE;
						else
							if source_class_register = FPU_CLASS_ZERO then
								source_significand_register <= (others => '0');
								source_exponent_register <=
									destination_exponent_register;
							end if;
							if destination_class_register = FPU_CLASS_ZERO then
								destination_significand_register <= (others => '0');
								destination_exponent_register <=
									source_exponent_register;
							end if;
							state <= PREPARE_ALIGNMENT;
						end if;

					when PREPARE_ALIGNMENT =>
						if destination_exponent_register >=
								source_exponent_register then
							common_exponent_register <=
								destination_exponent_register;
							difference := to_integer(destination_exponent_register -
								source_exponent_register);
							align_source_operand <= '1';
							if difference >= 67 then
								reduced_value := (others => '0');
								reduced_value(0) :=
									or_reduce(source_significand_register);
								source_significand_register <= reduced_value;
								state <= CALCULATE;
							elsif difference = 0 then
								state <= CALCULATE;
							else
								alignment_count <= difference;
								state <= ALIGN_OPERANDS;
							end if;
						else
							common_exponent_register <= source_exponent_register;
							difference := to_integer(source_exponent_register -
								destination_exponent_register);
							align_source_operand <= '0';
							if difference >= 67 then
								reduced_value := (others => '0');
								reduced_value(0) :=
									or_reduce(destination_significand_register);
								destination_significand_register <= reduced_value;
								state <= CALCULATE;
							elsif difference = 0 then
								state <= CALCULATE;
							else
								alignment_count <= difference;
								state <= ALIGN_OPERANDS;
							end if;
						end if;

					when ALIGN_OPERANDS =>
						if align_source_operand = '1' then
							source_significand_register <= aligned_value;
						else
							destination_significand_register <= aligned_value;
						end if;
						if alignment_count <= 8 then
							alignment_count <= 0;
							state <= CALCULATE;
						else
							alignment_count <= alignment_count - 8;
						end if;

					when CALCULATE =>
						magnitude := (others => '0');
						result_exponent := common_exponent_register;
						if source_arithmetic_sign = destination_sign then
							sum := significand_arithmetic_result;
							if sum(67) = '1' then
								magnitude := sum(67 downto 1);
								magnitude(0) := magnitude(0) or sum(0);
								result_exponent := common_exponent_register + 1;
							else
								magnitude := sum(66 downto 0);
							end if;
							result_sign := destination_sign;
						elsif destination_significand_register >
								source_significand_register then
							magnitude := significand_arithmetic_result(66 downto 0);
							result_sign := destination_sign;
						elsif source_significand_register >
								destination_significand_register then
							magnitude := significand_arithmetic_result(66 downto 0);
							result_sign := source_arithmetic_sign;
						else
							if mode_latched = FPU_ROUND_MINUS_INFINITY then
								result_sign := '1';
							else
								result_sign := '0';
							end if;
						end if;
						if magnitude = 0 then
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= result_sign;
							state <= COMPLETE;
						elsif magnitude(66) = '1' then
							intermediate_class <= FPU_CLASS_NORMAL;
							intermediate_sign <= result_sign;
							intermediate_exponent <= result_exponent;
							intermediate_significand <= magnitude;
							state <= COMPLETE;
						else
							result_significand_register <= magnitude;
							result_sign_register <= result_sign;
							result_exponent_register <= result_exponent;
							state <= NORMALIZE_RESULT;
						end if;

					when NORMALIZE_RESULT =>
						normalized_exponent := result_exponent_register -
							normalization_amount;
							result_significand_register <= normalized_value;
							result_exponent_register <= normalized_exponent;
							if normalized_value(66) = '1' then
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_sign <= result_sign_register;
								intermediate_exponent <= normalized_exponent;
								intermediate_significand <= normalized_value;
								state <= COMPLETE;
							end if;

					when COMPLETE =>
						state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
