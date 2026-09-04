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

entity TG68K_FPU_Binary_Controller is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true;
		INCLUDE_CONVERSION_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		operation : in fpu_operation_t;
		external_source : in std_logic;
		operand_format : in fpu_operand_format_t;
		external_data_register : in std_logic;
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		integer_register_data : in std_logic_vector(31 downto 0);
		fp_register_data : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		exception_enable : in std_logic_vector(7 downto 0);
		packed_conversion_start : out std_logic;
		packed_conversion_source : out std_logic_vector(95 downto 0);
		packed_conversion_done : in std_logic;
		packed_conversion_result : in fpu_extended_t;
		packed_conversion_status : in std_logic_vector(7 downto 0);
		external_converted_data : in fpu_extended_t := (others => '0');
		conversion_source_format : out fpu_operand_format_t;
		conversion_source_data : out std_logic_vector(95 downto 0);
		external_rounded_result : in fpu_extended_t := (others => '0');
		external_rounded_inexact : in std_logic := '0';
		external_rounded_overflow : in std_logic := '0';
		external_rounded_underflow : in std_logic := '0';
		round_input : out fpu_round_input_t;
		rounding_precision_out : out fpu_rounding_precision_t;
		rounding_mode_out : out fpu_rounding_mode_t;
		round_single_extended_range : out std_logic;

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
		resume_context : in std_logic;
		saved_context_in : in std_logic_vector(98 downto 0);
		saved_context_out : out std_logic_vector(98 downto 0);
		memory_read_data : in std_logic_vector(15 downto 0);
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_nuds : out std_logic;
		memory_nlds : out std_logic;
		memory_function_code : out std_logic_vector(2 downto 0);

		fp_register_write : out std_logic;
		fp_register_write_data : out fpu_extended_t;
		fp_register_write_cosine : out std_logic;
		operation_status_write : out std_logic;
		condition_codes_write : out std_logic;
		operation_condition_codes : out std_logic_vector(3 downto 0);
		quotient_write : out std_logic;
		operation_quotient : out std_logic_vector(7 downto 0);
		operation_exception_status : out std_logic_vector(7 downto 0);
		exceptional_operand : out fpu_extended_t;

		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Binary_Controller is
	type controller_state_t is (IDLE, LOAD_MEMORY, UNPACK_OPERAND,
		START_PACKED_CONVERSION, WAIT_PACKED_CONVERSION,
		CAPTURE_DESTINATION, EXECUTE, WAIT_ADD_SUBTRACT, WAIT_DIVIDE,
		WAIT_SQUARE_ROOT,
		WAIT_REMAINDER, WAIT_EXPONENTIAL, WAIT_LOGARITHM, WAIT_ARC_TANGENT,
		WAIT_SINE_COSINE, WAIT_SINE_COSINE_SECONDARY, COMMIT_COSINE,
		COMMIT, BUS_ERROR_WAIT, COMPLETE);

	function transfer_word_count(format_value : fpu_operand_format_t)
		return natural is
	begin
		case format_value is
			when FPU_FORMAT_BYTE_INTEGER | FPU_FORMAT_WORD_INTEGER => return 1;
			when FPU_FORMAT_LONG_INTEGER | FPU_FORMAT_SINGLE => return 2;
			when FPU_FORMAT_DOUBLE => return 4;
			when others => return 6;
		end case;
	end function;

	function restored_transfer_index(
		value : std_logic_vector(2 downto 0)) return natural is
		variable decoded : natural;
	begin
		decoded := to_integer(unsigned(value));
		if decoded <= 5 then
			return decoded;
		end if;
		return 0;
	end function;

	signal state : controller_state_t := IDLE;
	signal add_subtract_latched : std_logic := '0';
	signal subtract_latched : std_logic := '0';
	signal compare_latched : std_logic := '0';
	signal multiply_latched : std_logic := '0';
	signal divide_latched : std_logic := '0';
	signal single_precision_latched : std_logic := '0';
	signal square_root_latched : std_logic := '0';
	signal integer_latched : std_logic := '0';
	signal force_round_zero_latched : std_logic := '0';
	signal scale_latched : std_logic := '0';
	signal remainder_latched : std_logic := '0';
	signal ieee_remainder_latched : std_logic := '0';
	signal exponential_latched : std_logic := '0';
	signal exponential_base_latched : fpu_exponential_base_t :=
		FPU_EXP_BASE_TWO;
	signal exponential_minus_one_latched : std_logic := '0';
	signal hyperbolic_sine_latched : std_logic := '0';
	signal hyperbolic_cosine_latched : std_logic := '0';
	signal hyperbolic_tangent_latched : std_logic := '0';
	signal logarithm_latched : std_logic := '0';
	signal logarithm_add_one_latched : std_logic := '0';
	signal inverse_hyperbolic_tangent_latched : std_logic := '0';
	signal logarithm_base_latched : fpu_logarithm_base_t := FPU_LOG_BASE_E;
	signal arc_tangent_latched : std_logic := '0';
	signal arc_sine_latched : std_logic := '0';
	signal arc_cosine_latched : std_logic := '0';
	signal sine_cosine_latched : std_logic := '0';
	signal sine_cosine_cosine_latched : std_logic := '0';
	signal sine_cosine_tangent_latched : std_logic := '0';
	signal sine_cosine_simultaneous_latched : std_logic := '0';
	signal format_latched : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal precision_latched : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal snan_enable_latched : std_logic := '0';
	signal operr_enable_latched : std_logic := '0';
	signal dz_enable_latched : std_logic := '0';
	signal external_buffer : std_logic_vector(95 downto 0) := (others => '0');
	signal source_latched : fpu_extended_t := (others => '0');
	signal destination_latched : fpu_extended_t := (others => '0');
	signal result_latched : fpu_extended_t := (others => '0');
	signal cosine_result_latched : fpu_extended_t := (others => '0');
	signal condition_codes_latched : std_logic_vector(3 downto 0) :=
		(others => '0');
	signal status_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal conversion_status_latched : std_logic_vector(7 downto 0) :=
		(others => '0');
	signal quotient_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal write_result_latched : std_logic := '0';
	signal transfer_index : natural range 0 to 5 := 0;

	signal unpacked_operand : fpu_extended_t;
	signal add_subtract_start : std_logic;
	signal add_subtract_done : std_logic;
	signal add_subtract_round_input : fpu_round_input_t;
	signal add_subtract_base_status : std_logic_vector(7 downto 0);
	signal add_subtract_compare_codes : std_logic_vector(3 downto 0);
	signal multiply_round_input : fpu_round_input_t;
	signal multiply_base_status : std_logic_vector(7 downto 0);
	signal shared_product_left : unsigned(63 downto 0);
	signal shared_product_right : unsigned(63 downto 0);
	signal shared_product_result : unsigned(127 downto 0);
	signal divide_start : std_logic;
	signal divide_done : std_logic;
	signal divide_digit_start : std_logic;
	signal divide_digit_divisor : unsigned(64 downto 0);
	signal divide_digit_dividend : unsigned(64 downto 0);
	signal divide_round_input : fpu_round_input_t;
	signal divide_base_status : std_logic_vector(7 downto 0);
	signal square_root_start : std_logic;
	signal square_root_done : std_logic;
	signal square_root_round_input : fpu_round_input_t;
	signal square_root_base_status : std_logic_vector(7 downto 0);
	signal square_root_digit_start : std_logic;
	signal square_root_radicand : unsigned(65 downto 0);
	signal shared_root_result : unsigned(112 downto 0);
	signal shared_root_remainder_nonzero : std_logic;
	signal shared_root_done : std_logic;
	signal integer_round_input : fpu_round_input_t;
	signal integer_base_status : std_logic_vector(7 downto 0);
	signal scale_round_input : fpu_round_input_t;
	signal scale_base_status : std_logic_vector(7 downto 0);
	signal remainder_start : std_logic;
	signal remainder_done : std_logic;
	signal remainder_digit_start : std_logic;
	signal remainder_digit_initial_mode : fpu_divide_initial_t;
	signal remainder_digit_divisor : unsigned(64 downto 0);
	signal remainder_digit_dividend : unsigned(64 downto 0);
	signal remainder_digit_forced_subtrahend : unsigned(64 downto 0);
	signal remainder_digit_iterations : natural range 0 to 65535;
	signal remainder_digit_nearest_adjust : std_logic;
	signal remainder_round_input : fpu_round_input_t;
	signal remainder_base_status : std_logic_vector(7 downto 0);
	signal remainder_quotient : std_logic_vector(7 downto 0);
	signal shared_divide_start : std_logic;
	signal shared_divide_initial_mode : fpu_divide_initial_t;
	signal shared_divide_divisor : unsigned(64 downto 0);
	signal shared_divide_dividend : unsigned(64 downto 0);
	signal shared_divide_forced_subtrahend : unsigned(64 downto 0);
	signal shared_divide_iterations : natural range 0 to 65535;
	signal shared_divide_nearest_adjust : std_logic;
	signal shared_divide_remainder : unsigned(64 downto 0);
	signal shared_divide_quotient : unsigned(65 downto 0);
	signal shared_divide_exponent_decrement : std_logic;
	signal shared_divide_sign_invert : std_logic;
	signal shared_divide_done : std_logic;
	signal exponential_start : std_logic;
	signal exponential_done : std_logic;
	signal exponential_round_input : fpu_round_input_t;
	signal exponential_base_status : std_logic_vector(7 downto 0);
	signal logarithm_start : std_logic;
	signal logarithm_done : std_logic;
	signal logarithm_round_input : fpu_round_input_t;
	signal logarithm_base_status : std_logic_vector(7 downto 0);
	signal exponential_series_start : std_logic;
	signal exponential_series_cube : std_logic;
	signal exponential_series_divide_by_six : std_logic;
	signal exponential_series_source : unsigned(63 downto 0);
	signal exponential_series_square_high : unsigned(15 downto 0);
	signal logarithm_series_start : std_logic;
	signal logarithm_series_cube : std_logic;
	signal logarithm_series_divide_by_six : std_logic;
	signal logarithm_series_source : unsigned(63 downto 0);
	signal logarithm_series_square_high : unsigned(15 downto 0);
	signal shared_series_start : std_logic;
	signal shared_series_cube : std_logic;
	signal shared_series_divide_by_six : std_logic;
	signal shared_series_source : unsigned(63 downto 0);
	signal shared_series_square_high : unsigned(15 downto 0);
	signal shared_series_square_result : unsigned(127 downto 0);
	signal shared_series_cube_quotient : unsigned(79 downto 0);
	signal shared_series_cube_remainder : natural range 0 to 5;
	signal shared_series_done : std_logic;
	signal exponential_cordic_start : std_logic;
	signal exponential_cordic_x_input : signed(99 downto 0);
	signal exponential_cordic_y_input : signed(99 downto 0);
	signal exponential_cordic_z_input : signed(112 downto 0);
	signal logarithm_cordic_start : std_logic;
	signal logarithm_cordic_x_input : signed(99 downto 0);
	signal logarithm_cordic_y_input : signed(99 downto 0);
	signal logarithm_cordic_z_input : signed(112 downto 0);
	signal hyperbolic_cordic_x_input : signed(99 downto 0);
	signal hyperbolic_cordic_y_input : signed(99 downto 0);
	signal hyperbolic_cordic_z_input : signed(112 downto 0);
	signal hyperbolic_cordic_x_result : signed(99 downto 0);
	signal hyperbolic_cordic_y_result : signed(99 downto 0);
	signal hyperbolic_cordic_z_result : signed(112 downto 0);
	signal hyperbolic_cordic_done : std_logic;
	signal shared_cordic_hyperbolic : std_logic;
	signal arc_tangent_start : std_logic;
	signal arc_tangent_done : std_logic;
	signal arc_tangent_round_input : fpu_round_input_t;
	signal arc_tangent_base_status : std_logic_vector(7 downto 0);
	signal arc_root_start : std_logic;
	signal arc_root_radicand : unsigned(225 downto 0);
	signal sine_cosine_start : std_logic;
	signal sine_cosine_done : std_logic;
	signal sine_cosine_round_input : fpu_round_input_t;
	signal sine_cosine_secondary_round_input : fpu_round_input_t;
	signal sine_cosine_base_status : std_logic_vector(7 downto 0);
	signal arc_cordic_start : std_logic;
	signal arc_cordic_x_input : signed(147 downto 0);
	signal arc_cordic_y_input : signed(147 downto 0);
	signal arc_cordic_z_input : signed(147 downto 0);
	signal sine_cordic_start : std_logic;
	signal sine_cordic_x_input : signed(147 downto 0);
	signal sine_cordic_y_input : signed(147 downto 0);
	signal sine_cordic_z_input : signed(147 downto 0);
	signal circular_cordic_x_input : signed(147 downto 0);
	signal circular_cordic_y_input : signed(147 downto 0);
	signal circular_cordic_z_input : signed(147 downto 0);
	signal circular_cordic_x_result : signed(147 downto 0);
	signal circular_cordic_y_result : signed(147 downto 0);
	signal circular_cordic_z_result : signed(147 downto 0);
	signal circular_cordic_done : std_logic;
	signal circular_shift_source : signed(147 downto 0);
	signal circular_shift_amount : natural range 0 to 144;
	signal circular_shift_result : signed(147 downto 0);
	signal shared_cordic_shift_source : signed(139 downto 0);
	signal shared_cordic_shift_amount : natural range 0 to 136;
	signal shared_cordic_shift_result : signed(139 downto 0);
	signal selected_round_input : fpu_round_input_t;
	signal selected_base_status : std_logic_vector(7 downto 0);
	signal selected_rounding_mode : fpu_rounding_mode_t;
	signal selected_rounding_precision : fpu_rounding_precision_t;
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
	signal rounded_condition_codes : std_logic_vector(3 downto 0);
	signal rounded_status : std_logic_vector(7 downto 0);
begin
	exceptional_operand <= source_latched;
	round_input <= selected_round_input;
	rounding_precision_out <= selected_rounding_precision;
	rounding_mode_out <= selected_rounding_mode;
	round_single_extended_range <= single_precision_latched;
	saved_context_out <= external_buffer &
		std_logic_vector(to_unsigned(transfer_index, 3));
	add_subtract_start <= '1' when state = EXECUTE and
		add_subtract_latched = '1' else '0';
	divide_start <= '1' when state = EXECUTE and divide_latched = '1' else '0';
	round_input_selection : process(divide_round_input,
		square_root_round_input, remainder_round_input,
		exponential_round_input, logarithm_round_input,
		arc_tangent_round_input, sine_cosine_round_input,
		sine_cosine_secondary_round_input, integer_round_input,
		scale_round_input, multiply_round_input, add_subtract_round_input,
		divide_latched, square_root_latched, remainder_latched,
		exponential_latched, logarithm_latched, arc_tangent_latched,
		sine_cosine_latched, integer_latched, scale_latched,
		multiply_latched, add_subtract_latched, state, source_latched,
		destination_latched)
		variable selected : fpu_round_input_t;
		variable special_value : fpu_extended_t;
		variable source_class : fpu_data_class_t;
		variable destination_class : fpu_data_class_t;
		variable uses_destination : boolean;
	begin
		selected.data_class := add_subtract_round_input.data_class;
		selected.sign := add_subtract_round_input.sign;
		selected.exponent := add_subtract_round_input.exponent;
		selected.significand := add_subtract_round_input.significand;
		if divide_latched = '1' then
			selected.data_class := divide_round_input.data_class;
			selected.sign := divide_round_input.sign;
			selected.exponent := divide_round_input.exponent;
			selected.significand := divide_round_input.significand;
		elsif square_root_latched = '1' then
			selected.data_class := square_root_round_input.data_class;
			selected.sign := square_root_round_input.sign;
			selected.exponent := square_root_round_input.exponent;
			selected.significand := square_root_round_input.significand;
		elsif remainder_latched = '1' then
			selected.data_class := remainder_round_input.data_class;
			selected.sign := remainder_round_input.sign;
			selected.exponent := remainder_round_input.exponent;
			selected.significand := remainder_round_input.significand;
		elsif exponential_latched = '1' then
			selected.data_class := exponential_round_input.data_class;
			selected.sign := exponential_round_input.sign;
			selected.exponent := exponential_round_input.exponent;
			selected.significand := exponential_round_input.significand;
		elsif logarithm_latched = '1' then
			selected.data_class := logarithm_round_input.data_class;
			selected.sign := logarithm_round_input.sign;
			selected.exponent := logarithm_round_input.exponent;
			selected.significand := logarithm_round_input.significand;
		elsif arc_tangent_latched = '1' then
			selected.data_class := arc_tangent_round_input.data_class;
			selected.sign := arc_tangent_round_input.sign;
			selected.exponent := arc_tangent_round_input.exponent;
			selected.significand := arc_tangent_round_input.significand;
		elsif state = WAIT_SINE_COSINE_SECONDARY then
			selected.data_class := sine_cosine_secondary_round_input.data_class;
			selected.sign := sine_cosine_secondary_round_input.sign;
			selected.exponent := sine_cosine_secondary_round_input.exponent;
			selected.significand := sine_cosine_secondary_round_input.significand;
		elsif sine_cosine_latched = '1' then
			selected.data_class := sine_cosine_round_input.data_class;
			selected.sign := sine_cosine_round_input.sign;
			selected.exponent := sine_cosine_round_input.exponent;
			selected.significand := sine_cosine_round_input.significand;
		elsif integer_latched = '1' then
			selected.data_class := integer_round_input.data_class;
			selected.sign := integer_round_input.sign;
			selected.exponent := integer_round_input.exponent;
			selected.significand := integer_round_input.significand;
		elsif scale_latched = '1' then
			selected.data_class := scale_round_input.data_class;
			selected.sign := scale_round_input.sign;
			selected.exponent := scale_round_input.exponent;
			selected.significand := scale_round_input.significand;
		elsif multiply_latched = '1' then
			selected.data_class := multiply_round_input.data_class;
			selected.sign := multiply_round_input.sign;
			selected.exponent := multiply_round_input.exponent;
			selected.significand := multiply_round_input.significand;
		end if;

		source_class := fpu_classify(source_latched);
		destination_class := fpu_classify(destination_latched);
		uses_destination := add_subtract_latched = '1' or
			multiply_latched = '1' or divide_latched = '1' or
			remainder_latched = '1' or scale_latched = '1';
		special_value := FPU_RESET_NAN;
		if uses_destination and
				(destination_class = FPU_CLASS_QUIET_NAN or
				destination_class = FPU_CLASS_SIGNALING_NAN) then
			special_value := destination_latched;
		elsif source_class = FPU_CLASS_QUIET_NAN or
				source_class = FPU_CLASS_SIGNALING_NAN then
			special_value := source_latched;
		end if;
		special_value(62) := '1';
		selected.special := special_value;
		selected_round_input <= selected;
	end process;
	selected_base_status <= divide_base_status when divide_latched = '1' else
		square_root_base_status when square_root_latched = '1' else
		remainder_base_status when remainder_latched = '1' else
		exponential_base_status when exponential_latched = '1' else
		logarithm_base_status when logarithm_latched = '1' else
		arc_tangent_base_status when arc_tangent_latched = '1' else
		sine_cosine_base_status when sine_cosine_latched = '1' else
		integer_base_status when integer_latched = '1' else
		scale_base_status when scale_latched = '1' else
		multiply_base_status when multiply_latched = '1' else
		add_subtract_base_status;
	selected_rounding_mode <= FPU_ROUND_ZERO when
		integer_latched = '1' and force_round_zero_latched = '1' else
		mode_latched;
	selected_rounding_precision <= FPU_PRECISION_SINGLE when
		single_precision_latched = '1' else precision_latched;
	rounded_condition_codes <= add_subtract_compare_codes
		when compare_latched = '1' else fpu_condition_codes(rounded_result);

	rounded_exceptions : process(selected_base_status, conversion_status_latched,
			compare_latched,
			rounded_inexact, rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := selected_base_status or conversion_status_latched;
		if compare_latched = '0' then
			status(4) := rounded_overflow;
			status(3) := rounded_underflow;
			status(1) := selected_base_status(1) or rounded_inexact;
		end if;
		rounded_status <= status;
	end process;

	conversion_source_format <= format_latched;
	conversion_source_data <= external_buffer;

	with_conversion : if INCLUDE_CONVERSION_STAGE generate
		unpack : entity work.TG68K_FPU_Convert
			port map(
				source_format => format_latched,
				source_data => external_buffer,
				extended_data => unpacked_operand,
				conversion_valid => open,
				extended_source => (others => '0'),
				external_extended_data => open
			);
	end generate;

	without_conversion : if not INCLUDE_CONVERSION_STAGE generate
		unpacked_operand <= external_converted_data;
	end generate;

	add_subtract : entity work.TG68K_FPU_Add_Subtract
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => add_subtract_start,
			source => source_latched,
			destination => destination_latched,
			subtract => subtract_latched,
			compare_only => compare_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => add_subtract_done,
			round_input => add_subtract_round_input,
			base_exception_status => add_subtract_base_status,
			compare_result_condition_codes => add_subtract_compare_codes
		);

	multiply : entity work.TG68K_FPU_Multiply
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			source => source_latched,
			destination => destination_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			single_precision_operation => single_precision_latched,
			shared_product_request => shared_series_start,
			shared_product_left => shared_product_left,
			shared_product_right => shared_product_right,
			shared_product_result => shared_product_result,
			result => open,
			condition_codes => open,
			exception_status => open,
			round_input => multiply_round_input,
			base_exception_status => multiply_base_status
		);

	divide : entity work.TG68K_FPU_Divide
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => divide_start,
			source => source_latched,
			destination => destination_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			single_precision_operation => single_precision_latched,
			divide_start => divide_digit_start,
			divide_divisor => divide_digit_divisor,
			divide_dividend => divide_digit_dividend,
			divide_remainder => shared_divide_remainder,
			divide_quotient => shared_divide_quotient,
			divide_exponent_decrement =>
				shared_divide_exponent_decrement,
			divide_done => shared_divide_done,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => divide_done,
			round_input => divide_round_input,
			base_exception_status => divide_base_status
		);

	shared_divide_start <= divide_digit_start or remainder_digit_start;
	shared_divide_initial_mode <= remainder_digit_initial_mode when
		remainder_digit_start = '1' else FPU_DIVIDE_FRACTION;
	shared_divide_divisor <= remainder_digit_divisor when
		remainder_digit_start = '1' else divide_digit_divisor;
	shared_divide_dividend <= remainder_digit_dividend when
		remainder_digit_start = '1' else divide_digit_dividend;
	shared_divide_forced_subtrahend <= remainder_digit_forced_subtrahend when
		remainder_digit_start = '1' else (others => '0');
	shared_divide_iterations <= remainder_digit_iterations when
		remainder_digit_start = '1' else 65;
	shared_divide_nearest_adjust <= remainder_digit_nearest_adjust when
		remainder_digit_start = '1' else '0';

	shared_divider : entity work.TG68K_FPU_Divide_Engine
		port map(
			clk => clk,
			nReset => nReset,
			start => shared_divide_start,
			initial_mode => shared_divide_initial_mode,
			divisor => shared_divide_divisor,
			dividend => shared_divide_dividend,
			forced_subtrahend => shared_divide_forced_subtrahend,
			iterations => shared_divide_iterations,
			nearest_adjust => shared_divide_nearest_adjust,
			divisor_result => open,
			remainder_result => shared_divide_remainder,
			quotient_result => shared_divide_quotient,
			exponent_decrement => shared_divide_exponent_decrement,
			sign_invert => shared_divide_sign_invert,
			busy => open,
			done => shared_divide_done
		);

	square_root_start <= '1' when state = EXECUTE and
		square_root_latched = '1' else '0';

	square_root : entity work.TG68K_FPU_Square_Root
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => square_root_start,
			source => source_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			root_start => square_root_digit_start,
			root_radicand => square_root_radicand,
			root_result => shared_root_result(65 downto 0),
			root_remainder_nonzero => shared_root_remainder_nonzero,
			root_done => shared_root_done,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => square_root_done,
			round_input => square_root_round_input,
			base_exception_status => square_root_base_status
		);

	shared_square_root : entity work.TG68K_FPU_Square_Root_Engine
		port map(
			clk => clk,
			nReset => nReset,
			narrow_start => square_root_digit_start,
			narrow_radicand => square_root_radicand,
			wide_start => arc_root_start,
			wide_radicand => arc_root_radicand,
			root_result => shared_root_result,
			remainder_nonzero => shared_root_remainder_nonzero,
			busy => open,
			done => shared_root_done
		);

	remainder_start <= '1' when state = EXECUTE and
		remainder_latched = '1' else '0';

	remainder : entity work.TG68K_FPU_Remainder
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => remainder_start,
			ieee_remainder => ieee_remainder_latched,
			source => source_latched,
			destination => destination_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			reduction_start => remainder_digit_start,
			reduction_initial_mode => remainder_digit_initial_mode,
			reduction_divisor => remainder_digit_divisor,
			reduction_dividend => remainder_digit_dividend,
			reduction_forced_subtrahend =>
				remainder_digit_forced_subtrahend,
			reduction_iterations => remainder_digit_iterations,
			reduction_nearest_adjust => remainder_digit_nearest_adjust,
			reduction_remainder => shared_divide_remainder,
			reduction_quotient => shared_divide_quotient,
			reduction_sign_invert => shared_divide_sign_invert,
			reduction_done => shared_divide_done,
			result => open,
			condition_codes => open,
			exception_status => open,
			quotient => remainder_quotient,
			busy => open,
			done => remainder_done,
			round_input => remainder_round_input,
			base_exception_status => remainder_base_status
		);

	exponential_start <= '1' when state = EXECUTE and
		exponential_latched = '1' else '0';
	hyperbolic_cordic_x_input <= exponential_cordic_x_input when
		exponential_cordic_start = '1' else logarithm_cordic_x_input;
	hyperbolic_cordic_y_input <= exponential_cordic_y_input when
		exponential_cordic_start = '1' else logarithm_cordic_y_input;
	hyperbolic_cordic_z_input <= exponential_cordic_z_input when
		exponential_cordic_start = '1' else logarithm_cordic_z_input;
	shared_cordic_hyperbolic <= exponential_cordic_start or
		logarithm_cordic_start;
	shared_cordic_shift_source <= resize(circular_shift_source,
		shared_cordic_shift_source'length);
	shared_cordic_shift_amount <= circular_shift_amount;
	shared_cordic_shift_result <= shift_right(shared_cordic_shift_source,
		shared_cordic_shift_amount);
	circular_shift_result <= resize(shared_cordic_shift_result,
		circular_shift_result'length);
	hyperbolic_cordic_x_result <= resize(circular_cordic_x_result,
		hyperbolic_cordic_x_result'length);
	hyperbolic_cordic_y_result <= resize(circular_cordic_y_result,
		hyperbolic_cordic_y_result'length);
	hyperbolic_cordic_z_result <= resize(circular_cordic_z_result,
		hyperbolic_cordic_z_result'length);
	hyperbolic_cordic_done <= circular_cordic_done;

	shared_series_start <= exponential_series_start or logarithm_series_start;
	shared_series_cube <= exponential_series_cube when exponential_latched = '1'
		else logarithm_series_cube;
	shared_series_divide_by_six <= exponential_series_divide_by_six when
		exponential_latched = '1' else logarithm_series_divide_by_six;
	shared_series_source <= exponential_series_source when
		exponential_latched = '1' else logarithm_series_source;
	shared_series_square_high <= exponential_series_square_high when
		exponential_latched = '1' else logarithm_series_square_high;

	series_arithmetic : entity work.TG68K_FPU_Series_Arithmetic
		port map(
			clk => clk,
			nReset => nReset,
			start => shared_series_start,
			cube_divide => shared_series_cube,
			divide_by_six => shared_series_divide_by_six,
			source_significand => shared_series_source,
			square_high => shared_series_square_high,
			product_left => shared_product_left,
			product_right => shared_product_right,
			product_result => shared_product_result,
			square_result => shared_series_square_result,
			cube_quotient => shared_series_cube_quotient,
			cube_remainder => shared_series_cube_remainder,
			busy => open,
			done => shared_series_done
		);

	exponential : entity work.TG68K_FPU_Exponential
		generic map(
			INCLUDE_ROUNDING_STAGE => false,
			INCLUDE_SERIES_ARITHMETIC => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => exponential_start,
			source => source_latched,
			exponential_base => exponential_base_latched,
			subtract_one => exponential_minus_one_latched,
			hyperbolic_sine => hyperbolic_sine_latched,
			hyperbolic_cosine => hyperbolic_cosine_latched,
			hyperbolic_tangent => hyperbolic_tangent_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			cordic_start => exponential_cordic_start,
			cordic_x_input => exponential_cordic_x_input,
			cordic_y_input => exponential_cordic_y_input,
			cordic_z_input => exponential_cordic_z_input,
			cordic_x_result => hyperbolic_cordic_x_result,
			cordic_y_result => hyperbolic_cordic_y_result,
			cordic_done => hyperbolic_cordic_done,
			series_arithmetic_done => shared_series_done,
			series_square_result => shared_series_square_result,
			series_cube_quotient => shared_series_cube_quotient,
			series_cube_remainder => shared_series_cube_remainder,
			series_arithmetic_start => exponential_series_start,
			series_cube_divide => exponential_series_cube,
			series_divide_by_six => exponential_series_divide_by_six,
			series_arithmetic_source => exponential_series_source,
			series_square_high => exponential_series_square_high,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => exponential_done,
			round_input => exponential_round_input,
			base_exception_status => exponential_base_status
		);

	logarithm_start <= '1' when state = EXECUTE and
		logarithm_latched = '1' else '0';

	logarithm : entity work.TG68K_FPU_Logarithm
		generic map(
			INCLUDE_ROUNDING_STAGE => false,
			INCLUDE_SERIES_ARITHMETIC => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => logarithm_start,
			source => source_latched,
			add_one => logarithm_add_one_latched,
			logarithm_base => logarithm_base_latched,
			inverse_hyperbolic_tangent =>
				inverse_hyperbolic_tangent_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			cordic_start => logarithm_cordic_start,
			cordic_x_input => logarithm_cordic_x_input,
			cordic_y_input => logarithm_cordic_y_input,
			cordic_z_input => logarithm_cordic_z_input,
			cordic_z_result => hyperbolic_cordic_z_result,
			cordic_done => hyperbolic_cordic_done,
			series_arithmetic_done => shared_series_done,
			series_square_result => shared_series_square_result,
			series_cube_quotient => shared_series_cube_quotient,
			series_arithmetic_start => logarithm_series_start,
			series_cube_divide => logarithm_series_cube,
			series_divide_by_six => logarithm_series_divide_by_six,
			series_arithmetic_source => logarithm_series_source,
			series_square_high => logarithm_series_square_high,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => logarithm_done,
			round_input => logarithm_round_input,
			base_exception_status => logarithm_base_status
		);

	arc_tangent_start <= '1' when state = EXECUTE and
		arc_tangent_latched = '1' else '0';
	circular_cordic_x_input <= resize(hyperbolic_cordic_x_input,
		circular_cordic_x_input'length) when shared_cordic_hyperbolic = '1' else
		arc_cordic_x_input when
		arc_cordic_start = '1' else sine_cordic_x_input;
	circular_cordic_y_input <= resize(hyperbolic_cordic_y_input,
		circular_cordic_y_input'length) when shared_cordic_hyperbolic = '1' else
		arc_cordic_y_input when
		arc_cordic_start = '1' else sine_cordic_y_input;
	circular_cordic_z_input <= resize(hyperbolic_cordic_z_input,
		circular_cordic_z_input'length) when shared_cordic_hyperbolic = '1' else
		arc_cordic_z_input when
		arc_cordic_start = '1' else sine_cordic_z_input;

	circular_cordic : entity work.TG68K_FPU_Circular_CORDIC
		generic map(
			INCLUDE_SHIFT_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => shared_cordic_hyperbolic or arc_cordic_start or
				sine_cordic_start,
			vectoring => logarithm_cordic_start or arc_cordic_start,
			narrow_precision => arc_cordic_start,
			hyperbolic => shared_cordic_hyperbolic,
			rotate_on_start => exponential_cordic_start or sine_cordic_start,
			x_input => circular_cordic_x_input,
			y_input => circular_cordic_y_input,
			z_input => circular_cordic_z_input,
			external_shifted_coordinate => circular_shift_result,
			shift_source_out => circular_shift_source,
			shift_amount_out => circular_shift_amount,
			x_result => circular_cordic_x_result,
			y_result => circular_cordic_y_result,
			z_result => circular_cordic_z_result,
			busy => open,
			done => circular_cordic_done
		);

	arc_tangent : entity work.TG68K_FPU_Arc_Tangent
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => arc_tangent_start,
			source => source_latched,
			arc_sine => arc_sine_latched,
			arc_cosine => arc_cosine_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			cordic_start => arc_cordic_start,
			cordic_x_input => arc_cordic_x_input,
			cordic_y_input => arc_cordic_y_input,
			cordic_z_input => arc_cordic_z_input,
			cordic_z_result => circular_cordic_z_result,
			cordic_done => circular_cordic_done,
			root_start => arc_root_start,
			root_radicand => arc_root_radicand,
			root_result => shared_root_result,
			root_done => shared_root_done,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => arc_tangent_done,
			round_input => arc_tangent_round_input,
			base_exception_status => arc_tangent_base_status
		);

	sine_cosine_start <= '1' when state = EXECUTE and
		sine_cosine_latched = '1' else '0';

	sine_cosine : entity work.TG68K_FPU_Sine_Cosine
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => sine_cosine_start,
			cosine => sine_cosine_cosine_latched,
			tangent => sine_cosine_tangent_latched,
			simultaneous => sine_cosine_simultaneous_latched,
			source => source_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			cordic_start => sine_cordic_start,
			cordic_x_input => sine_cordic_x_input,
			cordic_y_input => sine_cordic_y_input,
			cordic_z_input => sine_cordic_z_input,
			cordic_x_result => circular_cordic_x_result,
			cordic_y_result => circular_cordic_y_result,
			cordic_done => circular_cordic_done,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => sine_cosine_done,
			round_input => sine_cosine_round_input,
			secondary_round_input => sine_cosine_secondary_round_input,
			base_exception_status => sine_cosine_base_status
		);

	integral_value : entity work.TG68K_FPU_Integer
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			source => source_latched,
			force_round_zero => force_round_zero_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => open,
			condition_codes => open,
			exception_status => open,
			round_input => integer_round_input,
			base_exception_status => integer_base_status
		);

	scale_exponent : entity work.TG68K_FPU_Scale
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			source => source_latched,
			destination => destination_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => open,
			condition_codes => open,
			exception_status => open,
			round_input => scale_round_input,
			base_exception_status => scale_base_status
		);

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		shared_round : entity work.TG68K_FPU_Round
			port map(
				input_class => selected_round_input.data_class,
				input_sign => selected_round_input.sign,
				input_exponent => selected_round_input.exponent,
				input_significand => selected_round_input.significand,
				special_value => selected_round_input.special,
				rounding_precision => selected_rounding_precision,
				rounding_mode => selected_rounding_mode,
				single_extended_range => single_precision_latched,
				result => rounded_result,
				inexact => rounded_inexact,
				overflow => rounded_overflow,
				underflow => rounded_underflow,
				signaling_nan => open
			);
	end generate;

	without_rounding : if not INCLUDE_ROUNDING_STAGE generate
		rounded_result <= external_rounded_result;
		rounded_inexact <= external_rounded_inexact;
		rounded_overflow <= external_rounded_overflow;
		rounded_underflow <= external_rounded_underflow;
	end generate;

	outputs : process(state, format_latched, address_latched,
		function_code_latched, transfer_index, external_buffer, result_latched,
		cosine_result_latched,
		condition_codes_latched, status_latched, write_result_latched,
		quotient_latched, remainder_latched, snan_enable_latched,
		operr_enable_latched, dz_enable_latched)
		variable suppress_write : boolean;
	begin
		memory_request <= '0';
		memory_write <= '0';
		memory_address <= std_logic_vector(unsigned(address_latched) +
			to_unsigned(transfer_index * 2, 32));
		memory_write_data <= (others => '0');
		memory_nuds <= '0';
		memory_nlds <= '0';
		memory_function_code <= function_code_latched;
		packed_conversion_start <= '0';
		packed_conversion_source <= external_buffer;
		fp_register_write <= '0';
		fp_register_write_data <= result_latched;
		fp_register_write_cosine <= '0';
		operation_status_write <= '0';
		condition_codes_write <= '0';
		operation_condition_codes <= condition_codes_latched;
		quotient_write <= '0';
		operation_quotient <= quotient_latched;
		operation_exception_status <= status_latched;
		done <= '0';
		bus_error_exception <= '0';
		if state = IDLE then
			busy <= '0';
		else
			busy <= '1';
		end if;

		if state = LOAD_MEMORY then
			memory_request <= '1';
			if format_latched = FPU_FORMAT_BYTE_INTEGER then
				memory_address <= address_latched;
				if address_latched(0) = '0' then
					memory_nlds <= '1';
				else
					memory_nuds <= '1';
				end if;
			end if;
		end if;

		suppress_write :=
			(status_latched(6) = '1' and snan_enable_latched = '1') or
			(status_latched(5) = '1' and operr_enable_latched = '1') or
			(status_latched(2) = '1' and dz_enable_latched = '1');
		case state is
			when START_PACKED_CONVERSION => packed_conversion_start <= '1';
			when COMMIT_COSINE =>
				fp_register_write_data <= cosine_result_latched;
				fp_register_write_cosine <= '1';
				if not suppress_write then
					fp_register_write <= '1';
				end if;
			when COMMIT =>
				operation_status_write <= '1';
				condition_codes_write <= '1';
				quotient_write <= remainder_latched;
				if write_result_latched = '1' and not suppress_write then
					fp_register_write <= '1';
				end if;
			when BUS_ERROR_WAIT => bus_error_exception <= '1';
			when COMPLETE => done <= '1';
			when others => null;
		end case;
	end process;

	sequencer : process(clk)
		variable read_word : std_logic_vector(15 downto 0);
		variable count : natural range 1 to 6;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				add_subtract_latched <= '0';
				subtract_latched <= '0';
				compare_latched <= '0';
				multiply_latched <= '0';
				divide_latched <= '0';
				single_precision_latched <= '0';
				square_root_latched <= '0';
				integer_latched <= '0';
				force_round_zero_latched <= '0';
				scale_latched <= '0';
				remainder_latched <= '0';
				ieee_remainder_latched <= '0';
				exponential_latched <= '0';
				exponential_base_latched <= FPU_EXP_BASE_TWO;
				exponential_minus_one_latched <= '0';
				hyperbolic_sine_latched <= '0';
				hyperbolic_cosine_latched <= '0';
				hyperbolic_tangent_latched <= '0';
				logarithm_latched <= '0';
				logarithm_add_one_latched <= '0';
				inverse_hyperbolic_tangent_latched <= '0';
				logarithm_base_latched <= FPU_LOG_BASE_E;
				arc_tangent_latched <= '0';
				arc_sine_latched <= '0';
				arc_cosine_latched <= '0';
				sine_cosine_latched <= '0';
				sine_cosine_cosine_latched <= '0';
				sine_cosine_tangent_latched <= '0';
				sine_cosine_simultaneous_latched <= '0';
				format_latched <= FPU_FORMAT_EXTENDED;
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				precision_latched <= FPU_PRECISION_EXTENDED;
				mode_latched <= FPU_ROUND_NEAREST;
				snan_enable_latched <= '0';
				operr_enable_latched <= '0';
				dz_enable_latched <= '0';
				external_buffer <= (others => '0');
				source_latched <= (others => '0');
				destination_latched <= (others => '0');
				result_latched <= (others => '0');
				cosine_result_latched <= (others => '0');
				condition_codes_latched <= (others => '0');
				status_latched <= (others => '0');
				conversion_status_latched <= (others => '0');
				quotient_latched <= (others => '0');
				write_result_latched <= '0';
				transfer_index <= 0;
			else
				case state is
					when IDLE =>
						if start = '1' then
							if operation = FPU_OP_ADD or
									operation = FPU_OP_SUB or
									operation = FPU_OP_CMP then
								add_subtract_latched <= '1';
							else
								add_subtract_latched <= '0';
							end if;
							if operation = FPU_OP_SUB then
								subtract_latched <= '1';
							else
								subtract_latched <= '0';
							end if;
							if operation = FPU_OP_CMP then
								compare_latched <= '1';
								write_result_latched <= '0';
							else
								compare_latched <= '0';
								write_result_latched <= '1';
							end if;
							if operation = FPU_OP_MUL or
									operation = FPU_OP_SGLMUL then
								multiply_latched <= '1';
							else
								multiply_latched <= '0';
							end if;
							if operation = FPU_OP_DIV or
									operation = FPU_OP_SGLDIV then
								divide_latched <= '1';
							else
								divide_latched <= '0';
							end if;
							if operation = FPU_OP_SGLMUL or
									operation = FPU_OP_SGLDIV then
								single_precision_latched <= '1';
							else
								single_precision_latched <= '0';
							end if;
							if operation = FPU_OP_SQRT then
								square_root_latched <= '1';
							else
								square_root_latched <= '0';
							end if;
							if operation = FPU_OP_INT or
									operation = FPU_OP_INTRZ then
								integer_latched <= '1';
							else
								integer_latched <= '0';
							end if;
							if operation = FPU_OP_INTRZ then
								force_round_zero_latched <= '1';
							else
								force_round_zero_latched <= '0';
							end if;
							if operation = FPU_OP_SCALE then
								scale_latched <= '1';
							else
								scale_latched <= '0';
							end if;
							if operation = FPU_OP_MOD or operation = FPU_OP_REM then
								remainder_latched <= '1';
							else
								remainder_latched <= '0';
							end if;
							if operation = FPU_OP_REM then
								ieee_remainder_latched <= '1';
							else
								ieee_remainder_latched <= '0';
							end if;
							if operation = FPU_OP_TWOTOX or
									operation = FPU_OP_ETOX or
									operation = FPU_OP_TENTOX or
									operation = FPU_OP_ETOXM1 or
									operation = FPU_OP_SINH or
									operation = FPU_OP_COSH or
									operation = FPU_OP_TANH then
								exponential_latched <= '1';
							else
								exponential_latched <= '0';
							end if;
							if operation = FPU_OP_ETOX or
									operation = FPU_OP_ETOXM1 or
									operation = FPU_OP_SINH or
									operation = FPU_OP_COSH or
									operation = FPU_OP_TANH then
								exponential_base_latched <= FPU_EXP_BASE_E;
							elsif operation = FPU_OP_TENTOX then
								exponential_base_latched <= FPU_EXP_BASE_TEN;
							else
								exponential_base_latched <= FPU_EXP_BASE_TWO;
							end if;
							if operation = FPU_OP_ETOXM1 then
								exponential_minus_one_latched <= '1';
							else
								exponential_minus_one_latched <= '0';
							end if;
							if operation = FPU_OP_SINH then
								hyperbolic_sine_latched <= '1';
							else
								hyperbolic_sine_latched <= '0';
							end if;
							if operation = FPU_OP_COSH then
								hyperbolic_cosine_latched <= '1';
							else
								hyperbolic_cosine_latched <= '0';
							end if;
							if operation = FPU_OP_TANH then
								hyperbolic_tangent_latched <= '1';
							else
								hyperbolic_tangent_latched <= '0';
							end if;
							if operation = FPU_OP_LOGNP1 or
									operation = FPU_OP_LOGN or
									operation = FPU_OP_LOG10 or
									operation = FPU_OP_LOG2 or
									operation = FPU_OP_ATANH then
								logarithm_latched <= '1';
							else
								logarithm_latched <= '0';
							end if;
							if operation = FPU_OP_LOGNP1 then
								logarithm_add_one_latched <= '1';
							else
								logarithm_add_one_latched <= '0';
							end if;
							if operation = FPU_OP_ATANH then
								inverse_hyperbolic_tangent_latched <= '1';
							else
								inverse_hyperbolic_tangent_latched <= '0';
							end if;
							if operation = FPU_OP_LOG2 then
								logarithm_base_latched <= FPU_LOG_BASE_TWO;
							elsif operation = FPU_OP_LOG10 then
								logarithm_base_latched <= FPU_LOG_BASE_TEN;
							else
								logarithm_base_latched <= FPU_LOG_BASE_E;
							end if;
							if operation = FPU_OP_ATAN or
									operation = FPU_OP_ASIN or
									operation = FPU_OP_ACOS then
								arc_tangent_latched <= '1';
							else
								arc_tangent_latched <= '0';
							end if;
							if operation = FPU_OP_ASIN then
								arc_sine_latched <= '1';
							else
								arc_sine_latched <= '0';
							end if;
							if operation = FPU_OP_ACOS then
								arc_cosine_latched <= '1';
							else
								arc_cosine_latched <= '0';
							end if;
							if operation = FPU_OP_SIN or
									operation = FPU_OP_COS or
									operation = FPU_OP_TAN or
									operation = FPU_OP_SINCOS then
								sine_cosine_latched <= '1';
							else
								sine_cosine_latched <= '0';
							end if;
							if operation = FPU_OP_COS then
								sine_cosine_cosine_latched <= '1';
							else
								sine_cosine_cosine_latched <= '0';
							end if;
							if operation = FPU_OP_TAN then
								sine_cosine_tangent_latched <= '1';
							else
								sine_cosine_tangent_latched <= '0';
							end if;
							if operation = FPU_OP_SINCOS then
								sine_cosine_simultaneous_latched <= '1';
							else
								sine_cosine_simultaneous_latched <= '0';
							end if;
							format_latched <= operand_format;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							precision_latched <= rounding_precision;
							mode_latched <= rounding_mode;
							snan_enable_latched <= exception_enable(6);
							operr_enable_latched <= exception_enable(5);
							dz_enable_latched <= exception_enable(2);
							external_buffer <= (others => '0');
							status_latched <= (others => '0');
							conversion_status_latched <= (others => '0');
							transfer_index <= 0;
							if resume_context = '1' then
								external_buffer <= saved_context_in(98 downto 3);
								transfer_index <= restored_transfer_index(
									saved_context_in(2 downto 0));
								state <= LOAD_MEMORY;
							elsif external_source = '0' then
								source_latched <= fp_register_data;
								state <= CAPTURE_DESTINATION;
							elsif external_data_register = '1' then
								external_buffer(31 downto 0) <=
									integer_register_data;
								state <= UNPACK_OPERAND;
							else
								state <= LOAD_MEMORY;
							end if;
						end if;

					when LOAD_MEMORY =>
						if memory_error = '1' then
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							count := transfer_word_count(format_latched);
							read_word := memory_read_data;
							if format_latched = FPU_FORMAT_BYTE_INTEGER then
								if address_latched(0) = '0' then
									read_word(7 downto 0) :=
										memory_read_data(15 downto 8);
								else
									read_word(7 downto 0) :=
										memory_read_data(7 downto 0);
								end if;
							end if;
							external_buffer <= external_buffer(79 downto 0) &
								read_word;
							if transfer_index = count - 1 then
								state <= UNPACK_OPERAND;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when UNPACK_OPERAND =>
						if format_latched = FPU_FORMAT_PACKED then
							state <= START_PACKED_CONVERSION;
						else
							source_latched <= unpacked_operand;
							state <= CAPTURE_DESTINATION;
						end if;

					when START_PACKED_CONVERSION =>
						state <= WAIT_PACKED_CONVERSION;

					when WAIT_PACKED_CONVERSION =>
						if packed_conversion_done = '1' then
							source_latched <= packed_conversion_result;
							conversion_status_latched <= packed_conversion_status;
							state <= CAPTURE_DESTINATION;
						end if;

					when CAPTURE_DESTINATION =>
						destination_latched <= fp_register_data;
						state <= EXECUTE;

					when EXECUTE =>
						if add_subtract_latched = '1' then
							state <= WAIT_ADD_SUBTRACT;
						elsif divide_latched = '1' then
							state <= WAIT_DIVIDE;
						elsif square_root_latched = '1' then
							state <= WAIT_SQUARE_ROOT;
						elsif remainder_latched = '1' then
							state <= WAIT_REMAINDER;
						elsif exponential_latched = '1' then
							state <= WAIT_EXPONENTIAL;
						elsif logarithm_latched = '1' then
							state <= WAIT_LOGARITHM;
						elsif arc_tangent_latched = '1' then
							state <= WAIT_ARC_TANGENT;
						elsif sine_cosine_latched = '1' then
							state <= WAIT_SINE_COSINE;
						else
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_ADD_SUBTRACT =>
						if add_subtract_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_DIVIDE =>
						if divide_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_SQUARE_ROOT =>
						if square_root_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_REMAINDER =>
						if remainder_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							quotient_latched <= remainder_quotient;
							state <= COMMIT;
						end if;

					when WAIT_EXPONENTIAL =>
						if exponential_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_LOGARITHM =>
						if logarithm_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_ARC_TANGENT =>
						if arc_tangent_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							state <= COMMIT;
						end if;

					when WAIT_SINE_COSINE =>
						if sine_cosine_done = '1' then
							result_latched <= rounded_result;
							condition_codes_latched <= rounded_condition_codes;
							status_latched <= rounded_status;
							if sine_cosine_simultaneous_latched = '1' then
								state <= WAIT_SINE_COSINE_SECONDARY;
							else
								state <= COMMIT;
							end if;
						end if;

					when WAIT_SINE_COSINE_SECONDARY =>
						if status_latched(3) = '1' then
							cosine_result_latched <= x"3FFF8000000000000000";
						else
							cosine_result_latched <= rounded_result;
						end if;
						state <= COMMIT_COSINE;

					when COMMIT_COSINE => state <= COMMIT;

					when COMMIT => state <= COMPLETE;

					when BUS_ERROR_WAIT =>
						if retry = '1' then
							state <= LOAD_MEMORY;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
