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

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
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
		operation_status_write : out std_logic;
		condition_codes_write : out std_logic;
		operation_condition_codes : out std_logic_vector(3 downto 0);
		quotient_write : out std_logic;
		operation_quotient : out std_logic_vector(7 downto 0);
		operation_exception_status : out std_logic_vector(7 downto 0);

		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Binary_Controller is
	type controller_state_t is (IDLE, LOAD_MEMORY, UNPACK_OPERAND,
		CAPTURE_DESTINATION, EXECUTE, WAIT_DIVIDE, WAIT_SQUARE_ROOT,
		WAIT_REMAINDER, WAIT_EXPONENTIAL, WAIT_LOGARITHM, WAIT_ARC_TANGENT,
		WAIT_SINE_COSINE, COMMIT, BUS_ERROR_WAIT, COMPLETE);

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

	function replace_transfer_word(
		value : std_logic_vector(95 downto 0);
		word_count : natural;
		word_index : natural;
		word_data : std_logic_vector(15 downto 0))
		return std_logic_vector is
		variable updated : std_logic_vector(95 downto 0) := value;
	begin
		case word_count is
			when 1 => updated(15 downto 0) := word_data;
			when 2 =>
				if word_index = 0 then
					updated(31 downto 16) := word_data;
				else
					updated(15 downto 0) := word_data;
				end if;
			when 4 =>
				case word_index is
					when 0 => updated(63 downto 48) := word_data;
					when 1 => updated(47 downto 32) := word_data;
					when 2 => updated(31 downto 16) := word_data;
					when others => updated(15 downto 0) := word_data;
				end case;
			when others =>
				case word_index is
					when 0 => updated(95 downto 80) := word_data;
					when 1 => updated(79 downto 64) := word_data;
					when 2 => updated(63 downto 48) := word_data;
					when 3 => updated(47 downto 32) := word_data;
					when 4 => updated(31 downto 16) := word_data;
					when others => updated(15 downto 0) := word_data;
				end case;
		end case;
		return updated;
	end function;

	signal state : controller_state_t := IDLE;
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
	signal condition_codes_latched : std_logic_vector(3 downto 0) :=
		(others => '0');
	signal status_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal quotient_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal write_result_latched : std_logic := '0';
	signal transfer_index : natural range 0 to 5 := 0;

	signal unpacked_operand : fpu_extended_t;
	signal add_subtract_round_input : fpu_round_input_t;
	signal add_subtract_base_status : std_logic_vector(7 downto 0);
	signal add_subtract_compare_codes : std_logic_vector(3 downto 0);
	signal multiply_round_input : fpu_round_input_t;
	signal multiply_base_status : std_logic_vector(7 downto 0);
	signal divide_start : std_logic;
	signal divide_done : std_logic;
	signal divide_round_input : fpu_round_input_t;
	signal divide_base_status : std_logic_vector(7 downto 0);
	signal square_root_start : std_logic;
	signal square_root_done : std_logic;
	signal square_root_round_input : fpu_round_input_t;
	signal square_root_base_status : std_logic_vector(7 downto 0);
	signal integer_round_input : fpu_round_input_t;
	signal integer_base_status : std_logic_vector(7 downto 0);
	signal scale_round_input : fpu_round_input_t;
	signal scale_base_status : std_logic_vector(7 downto 0);
	signal remainder_start : std_logic;
	signal remainder_done : std_logic;
	signal remainder_round_input : fpu_round_input_t;
	signal remainder_base_status : std_logic_vector(7 downto 0);
	signal remainder_quotient : std_logic_vector(7 downto 0);
	signal exponential_start : std_logic;
	signal exponential_done : std_logic;
	signal exponential_round_input : fpu_round_input_t;
	signal exponential_base_status : std_logic_vector(7 downto 0);
	signal logarithm_start : std_logic;
	signal logarithm_done : std_logic;
	signal logarithm_round_input : fpu_round_input_t;
	signal logarithm_base_status : std_logic_vector(7 downto 0);
	signal arc_tangent_start : std_logic;
	signal arc_tangent_done : std_logic;
	signal arc_tangent_round_input : fpu_round_input_t;
	signal arc_tangent_base_status : std_logic_vector(7 downto 0);
	signal sine_cosine_start : std_logic;
	signal sine_cosine_done : std_logic;
	signal sine_cosine_round_input : fpu_round_input_t;
	signal sine_cosine_base_status : std_logic_vector(7 downto 0);
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
	divide_start <= '1' when state = EXECUTE and divide_latched = '1' else '0';
	selected_round_input <= divide_round_input when divide_latched = '1' else
		square_root_round_input when square_root_latched = '1' else
		remainder_round_input when remainder_latched = '1' else
		exponential_round_input when exponential_latched = '1' else
		logarithm_round_input when logarithm_latched = '1' else
		arc_tangent_round_input when arc_tangent_latched = '1' else
		sine_cosine_round_input when sine_cosine_latched = '1' else
		integer_round_input when integer_latched = '1' else
		scale_round_input when scale_latched = '1' else
		multiply_round_input when multiply_latched = '1' else
		add_subtract_round_input;
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

	rounded_exceptions : process(selected_base_status, compare_latched,
			rounded_inexact, rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := selected_base_status;
		if compare_latched = '0' then
			status(4) := rounded_overflow;
			status(3) := rounded_underflow;
			status(1) := selected_base_status(1) or rounded_inexact;
		end if;
		rounded_status <= status;
	end process;

	unpack : entity work.TG68K_FPU_Convert
		port map(
			source_format => format_latched,
			source_data => external_buffer,
			extended_data => unpacked_operand,
			conversion_valid => open,
			extended_source => (others => '0'),
			external_extended_data => open
		);

	add_subtract : entity work.TG68K_FPU_Add_Subtract
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			source => source_latched,
			destination => destination_latched,
			subtract => subtract_latched,
			compare_only => compare_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => open,
			condition_codes => open,
			exception_status => open,
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
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => divide_done,
			round_input => divide_round_input,
			base_exception_status => divide_base_status
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
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => square_root_done,
			round_input => square_root_round_input,
			base_exception_status => square_root_base_status
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

	exponential : entity work.TG68K_FPU_Exponential
		generic map(
			INCLUDE_ROUNDING_STAGE => false
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
			INCLUDE_ROUNDING_STAGE => false
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
			source => source_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => open,
			condition_codes => open,
			exception_status => open,
			busy => open,
			done => sine_cosine_done,
			round_input => sine_cosine_round_input,
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

	outputs : process(state, format_latched, address_latched,
		function_code_latched, transfer_index, result_latched,
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
		fp_register_write <= '0';
		fp_register_write_data <= result_latched;
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
		variable updated_buffer : std_logic_vector(95 downto 0);
		variable read_word : std_logic_vector(15 downto 0);
		variable count : natural range 1 to 6;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
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
				condition_codes_latched <= (others => '0');
				status_latched <= (others => '0');
				quotient_latched <= (others => '0');
				write_result_latched <= '0';
				transfer_index <= 0;
			else
				case state is
					when IDLE =>
						if start = '1' then
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
							if operation = FPU_OP_SIN then
								sine_cosine_latched <= '1';
							else
								sine_cosine_latched <= '0';
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
							transfer_index <= 0;
							if external_source = '0' then
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
							updated_buffer := replace_transfer_word(external_buffer,
								count, transfer_index, read_word);
							external_buffer <= updated_buffer;
							if transfer_index = count - 1 then
								state <= UNPACK_OPERAND;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when UNPACK_OPERAND =>
						source_latched <= unpacked_operand;
						state <= CAPTURE_DESTINATION;

					when CAPTURE_DESTINATION =>
						destination_latched <= fp_register_data;
						state <= EXECUTE;

					when EXECUTE =>
						if divide_latched = '1' then
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
							state <= COMMIT;
						end if;

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
