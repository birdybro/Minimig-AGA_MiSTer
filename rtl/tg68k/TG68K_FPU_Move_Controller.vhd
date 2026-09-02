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

entity TG68K_FPU_Move_Controller is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true;
		INCLUDE_CONVERSION_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		direction : in fpu_move_direction_t;
		operand_format : in fpu_operand_format_t;
		external_data_register : in std_logic;
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		integer_register_data : in std_logic_vector(31 downto 0);
		fp_register_data : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		k_factor : in std_logic_vector(6 downto 0);
		packed_conversion_start : out std_logic;
		packed_conversion_source : out std_logic_vector(95 downto 0);
		packed_conversion_done : in std_logic;
		packed_conversion_result : in fpu_extended_t;
		packed_conversion_status : in std_logic_vector(7 downto 0);
		external_converted_data : in fpu_extended_t := (others => '0');
		external_conversion_valid : in std_logic := '0';
		conversion_source_format : out fpu_operand_format_t;
		conversion_source_data : out std_logic_vector(95 downto 0);
		external_rounded_result : in fpu_extended_t := (others => '0');
		external_rounded_inexact : in std_logic := '0';
		external_rounded_overflow : in std_logic := '0';
		external_rounded_underflow : in std_logic := '0';
		external_rounded_signaling_nan : in std_logic := '0';
		round_input : out fpu_round_input_t;
		rounding_precision_out : out fpu_rounding_precision_t;
		rounding_mode_out : out fpu_rounding_mode_t;

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
		resume_context : in std_logic;
		saved_context_in : in std_logic_vector(187 downto 0);
		saved_context_out : out std_logic_vector(187 downto 0);
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
		integer_register_write : out std_logic;
		integer_register_write_data : out std_logic_vector(31 downto 0);
		integer_register_write_format : out fpu_operand_format_t;
		operation_status_write : out std_logic;
		condition_codes_write : out std_logic;
		operation_condition_codes : out std_logic_vector(3 downto 0);
		operation_exception_status : out std_logic_vector(7 downto 0);
		exceptional_operand : out fpu_extended_t;

		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Move_Controller is
	type controller_state_t is (IDLE, LOAD_MEMORY, LOAD_UNPACK,
		START_PACKED_CONVERSION, WAIT_PACKED_CONVERSION,
		REGISTER_ROUND, REGISTER_REPACK, REGISTER_COMMIT, STORE_PREPARE,
		START_PACKED_OUTPUT, WAIT_PACKED_OUTPUT,
		STORE_MEMORY, STORE_DATA_REGISTER, STORE_STATUS, BUS_ERROR_WAIT,
		COMPLETE);

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

	function read_transfer_word(
		value : std_logic_vector(95 downto 0);
		word_count : natural;
		word_index : natural) return std_logic_vector is
	begin
		case word_count is
			when 1 => return value(15 downto 0);
			when 2 =>
				if word_index = 0 then
					return value(31 downto 16);
				else
					return value(15 downto 0);
				end if;
			when 4 =>
				case word_index is
					when 0 => return value(63 downto 48);
					when 1 => return value(47 downto 32);
					when 2 => return value(31 downto 16);
					when others => return value(15 downto 0);
				end case;
			when others =>
				case word_index is
					when 0 => return value(95 downto 80);
					when 1 => return value(79 downto 64);
					when 2 => return value(63 downto 48);
					when 3 => return value(47 downto 32);
					when 4 => return value(31 downto 16);
					when others => return value(15 downto 0);
				end case;
		end case;
	end function;

	function write_transfer_word(
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
	signal direction_latched : fpu_move_direction_t :=
		FPU_MOVE_REGISTER_TO_REGISTER;
	signal format_latched : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal data_register_latched : std_logic := '0';
	signal address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal precision_latched : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal k_factor_latched : std_logic_vector(6 downto 0) := (others => '0');
	signal source_latched : fpu_extended_t := (others => '0');
	signal external_buffer : std_logic_vector(95 downto 0) := (others => '0');
	signal rounded_external_latched : std_logic_vector(95 downto 0) :=
		(others => '0');
	signal result_latched : fpu_extended_t := (others => '0');
	signal status_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal transfer_index : natural range 0 to 5 := 0;
	signal fault_write_latched : std_logic := '0';

	signal precision_format : fpu_operand_format_t;
	signal unpack_format : fpu_operand_format_t;
	signal unpack_data : std_logic_vector(95 downto 0);
	signal unpacked_extended : fpu_extended_t;
	signal unpack_valid : std_logic;
	signal store_format : fpu_operand_format_t;
	signal store_data : std_logic_vector(95 downto 0);
	signal store_valid : std_logic;
	signal converted_status : std_logic_vector(7 downto 0);
	signal packed_output_result : std_logic_vector(95 downto 0);
	signal packed_output_status : std_logic_vector(7 downto 0);
	signal packed_output_done : std_logic;
	signal packed_output_start : std_logic;

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
begin
	exceptional_operand <= source_latched;
	saved_context_out <= external_buffer & source_latched & status_latched &
		std_logic_vector(to_unsigned(transfer_index, 3)) & fault_write_latched;
	packed_output_start <= '1' when state = START_PACKED_OUTPUT else '0';
	with precision_latched select precision_format <=
		FPU_FORMAT_SINGLE when FPU_PRECISION_SINGLE,
		FPU_FORMAT_DOUBLE when FPU_PRECISION_DOUBLE,
		FPU_FORMAT_EXTENDED when others;
	unpack_format <= precision_format when state = REGISTER_REPACK else
		format_latched;
	unpack_data <= rounded_external_latched when state = REGISTER_REPACK else
		external_buffer;
	conversion_source_format <= unpack_format;
	conversion_source_data <= unpack_data;
	store_format <= format_latched when
		direction_latched = FPU_MOVE_REGISTER_TO_EXTERNAL else precision_format;

	with_conversion : if INCLUDE_CONVERSION_STAGE generate
		unpack : entity work.TG68K_FPU_Convert
			port map(
				source_format => unpack_format,
				source_data => unpack_data,
				extended_data => unpacked_extended,
				conversion_valid => unpack_valid,
				extended_source => source_latched,
				external_extended_data => open
			);
	end generate;

	without_conversion : if not INCLUDE_CONVERSION_STAGE generate
		unpacked_extended <= external_converted_data;
		unpack_valid <= external_conversion_valid;
	end generate;

	store_converter : entity work.TG68K_FPU_Store_Convert
		generic map(
			INCLUDE_ROUNDING_STAGE => INCLUDE_ROUNDING_STAGE
		)
		port map(
			source => source_latched,
			destination_format => store_format,
			rounding_mode => mode_latched,
			external_rounded_result => external_rounded_result,
			external_rounded_inexact => external_rounded_inexact,
			external_rounded_overflow => external_rounded_overflow,
			external_rounded_underflow => external_rounded_underflow,
			external_rounded_signaling_nan =>
				external_rounded_signaling_nan,
			destination_data => store_data,
			conversion_valid => store_valid,
			exception_status => converted_status,
			round_input => round_input,
			rounding_precision_out => rounding_precision_out
		);
	rounding_mode_out <= mode_latched;

	packed_output_converter : entity work.TG68K_FPU_Extended_To_Packed
		port map(
			clk => clk,
			nReset => nReset,
			start => packed_output_start,
			source => source_latched,
			k_factor => k_factor_latched,
			rounding_mode => mode_latched,
			result => packed_output_result,
			exception_status => packed_output_status,
			busy => open,
			done => packed_output_done
		);

	outputs : process(state, format_latched, address_latched,
		function_code_latched, transfer_index, external_buffer, result_latched,
		status_latched)
		variable count : natural range 1 to 6;
		variable word_data : std_logic_vector(15 downto 0);
	begin
		memory_request <= '0';
		memory_write <= '0';
		memory_address <= address_latched;
		memory_write_data <= (others => '0');
		memory_nuds <= '0';
		memory_nlds <= '0';
		memory_function_code <= function_code_latched;
		packed_conversion_start <= '0';
		packed_conversion_source <= external_buffer;
		fp_register_write <= '0';
		fp_register_write_data <= result_latched;
		integer_register_write <= '0';
		integer_register_write_data <= external_buffer(31 downto 0);
		integer_register_write_format <= format_latched;
		operation_status_write <= '0';
		condition_codes_write <= '0';
		operation_condition_codes <= fpu_condition_codes(result_latched);
		operation_exception_status <= status_latched;
		done <= '0';
		bus_error_exception <= '0';
		if state = IDLE then
			busy <= '0';
		else
			busy <= '1';
		end if;

		count := transfer_word_count(format_latched);
		word_data := read_transfer_word(external_buffer, count, transfer_index);
		if state = LOAD_MEMORY or state = STORE_MEMORY then
			memory_request <= '1';
			memory_address <= std_logic_vector(unsigned(address_latched) +
				to_unsigned(transfer_index * 2, 32));
			if format_latched = FPU_FORMAT_BYTE_INTEGER then
				memory_address <= address_latched;
				memory_write_data <= external_buffer(7 downto 0) &
					external_buffer(7 downto 0);
				if address_latched(0) = '0' then
					memory_nuds <= '0';
					memory_nlds <= '1';
				else
					memory_nuds <= '1';
					memory_nlds <= '0';
				end if;
			else
				memory_write_data <= word_data;
			end if;
		end if;
		if state = STORE_MEMORY then
			memory_write <= '1';
		end if;

		case state is
			when START_PACKED_CONVERSION => packed_conversion_start <= '1';
			when REGISTER_COMMIT =>
				fp_register_write <= '1';
				operation_status_write <= '1';
				condition_codes_write <= '1';
			when STORE_DATA_REGISTER =>
				integer_register_write <= '1';
				operation_status_write <= '1';
			when STORE_STATUS =>
				operation_status_write <= '1';
			when BUS_ERROR_WAIT =>
				bus_error_exception <= '1';
			when COMPLETE =>
				done <= '1';
			when others => null;
		end case;
	end process;

	sequencer : process(clk)
		variable updated_buffer : std_logic_vector(95 downto 0);
		variable count : natural range 1 to 6;
		variable read_word : std_logic_vector(15 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				direction_latched <= FPU_MOVE_REGISTER_TO_REGISTER;
				format_latched <= FPU_FORMAT_EXTENDED;
				data_register_latched <= '0';
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				precision_latched <= FPU_PRECISION_EXTENDED;
				mode_latched <= FPU_ROUND_NEAREST;
				k_factor_latched <= (others => '0');
				source_latched <= (others => '0');
				external_buffer <= (others => '0');
				rounded_external_latched <= (others => '0');
				result_latched <= (others => '0');
				status_latched <= (others => '0');
				transfer_index <= 0;
				fault_write_latched <= '0';
			else
				case state is
					when IDLE =>
						if start = '1' then
							direction_latched <= direction;
							format_latched <= operand_format;
							data_register_latched <= external_data_register;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							precision_latched <= rounding_precision;
							mode_latched <= rounding_mode;
							k_factor_latched <= k_factor;
							transfer_index <= 0;
							fault_write_latched <= '0';
							if resume_context = '1' then
								external_buffer <= saved_context_in(187 downto 92);
								source_latched <= saved_context_in(91 downto 12);
								status_latched <= saved_context_in(11 downto 4);
								transfer_index <= restored_transfer_index(
									saved_context_in(3 downto 1));
								fault_write_latched <= saved_context_in(0);
								if saved_context_in(0) = '1' then
									state <= STORE_MEMORY;
								else
									state <= LOAD_MEMORY;
								end if;
							elsif direction = FPU_MOVE_REGISTER_TO_REGISTER then
								source_latched <= fp_register_data;
								state <= REGISTER_ROUND;
							elsif direction = FPU_MOVE_EXTERNAL_TO_REGISTER then
								if external_data_register = '1' then
									external_buffer(31 downto 0) <= integer_register_data;
									state <= LOAD_UNPACK;
								else
									state <= LOAD_MEMORY;
								end if;
							else
								source_latched <= fp_register_data;
								if operand_format = FPU_FORMAT_PACKED or
										operand_format = FPU_FORMAT_DYNAMIC_PACKED then
									state <= START_PACKED_OUTPUT;
								else
									state <= STORE_PREPARE;
								end if;
							end if;
						end if;

					when LOAD_MEMORY =>
						if memory_error = '1' then
							fault_write_latched <= '0';
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							count := transfer_word_count(format_latched);
							read_word := memory_read_data;
							if format_latched = FPU_FORMAT_BYTE_INTEGER then
								if address_latched(0) = '0' then
									read_word(7 downto 0) := memory_read_data(15 downto 8);
								else
									read_word(7 downto 0) := memory_read_data(7 downto 0);
								end if;
							end if;
							updated_buffer := write_transfer_word(external_buffer,
								count, transfer_index, read_word);
							external_buffer <= updated_buffer;
							if transfer_index + 1 = count then
								state <= LOAD_UNPACK;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when LOAD_UNPACK =>
						if format_latched = FPU_FORMAT_PACKED then
							state <= START_PACKED_CONVERSION;
						elsif unpack_valid = '1' then
							source_latched <= unpacked_extended;
							state <= REGISTER_ROUND;
						else
							state <= COMPLETE;
						end if;

					when START_PACKED_CONVERSION =>
						state <= WAIT_PACKED_CONVERSION;

					when WAIT_PACKED_CONVERSION =>
						if packed_conversion_done = '1' then
							result_latched <= packed_conversion_result;
							status_latched <= packed_conversion_status;
							state <= REGISTER_COMMIT;
						end if;

					when REGISTER_ROUND =>
						if store_valid = '1' then
							rounded_external_latched <= store_data;
							status_latched <= converted_status;
							state <= REGISTER_REPACK;
						else
							state <= COMPLETE;
						end if;

					when REGISTER_REPACK =>
						if unpack_valid = '1' then
							result_latched <= unpacked_extended;
							state <= REGISTER_COMMIT;
						else
							state <= COMPLETE;
						end if;

					when REGISTER_COMMIT => state <= COMPLETE;

					when START_PACKED_OUTPUT => state <= WAIT_PACKED_OUTPUT;

					when WAIT_PACKED_OUTPUT =>
						if packed_output_done = '1' then
							external_buffer <= packed_output_result;
							status_latched <= packed_output_status;
							state <= STORE_MEMORY;
						end if;

					when STORE_PREPARE =>
						if store_valid = '1' then
							external_buffer <= store_data;
							status_latched <= converted_status;
							if data_register_latched = '1' then
								state <= STORE_DATA_REGISTER;
							else
								state <= STORE_MEMORY;
							end if;
						else
							state <= COMPLETE;
						end if;

					when STORE_MEMORY =>
						if memory_error = '1' then
							fault_write_latched <= '1';
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							count := transfer_word_count(format_latched);
							if transfer_index + 1 = count then
								state <= STORE_STATUS;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when STORE_DATA_REGISTER | STORE_STATUS => state <= COMPLETE;

					when BUS_ERROR_WAIT =>
						if retry = '1' then
							if fault_write_latched = '1' then
								state <= STORE_MEMORY;
							else
								state <= LOAD_MEMORY;
							end if;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
