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
		operation_exception_status : out std_logic_vector(7 downto 0);

		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Binary_Controller is
	type controller_state_t is (IDLE, LOAD_MEMORY, UNPACK_OPERAND,
		CAPTURE_DESTINATION, EXECUTE, WAIT_DIVIDE, COMMIT, BUS_ERROR_WAIT,
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
	signal write_result_latched : std_logic := '0';
	signal transfer_index : natural range 0 to 5 := 0;

	signal unpacked_operand : fpu_extended_t;
	signal add_subtract_result : fpu_extended_t;
	signal add_subtract_condition_codes : std_logic_vector(3 downto 0);
	signal add_subtract_status : std_logic_vector(7 downto 0);
	signal multiply_result : fpu_extended_t;
	signal multiply_condition_codes : std_logic_vector(3 downto 0);
	signal multiply_status : std_logic_vector(7 downto 0);
	signal divide_start : std_logic;
	signal divide_done : std_logic;
	signal divide_result : fpu_extended_t;
	signal divide_condition_codes : std_logic_vector(3 downto 0);
	signal divide_status : std_logic_vector(7 downto 0);
begin
	divide_start <= '1' when state = EXECUTE and divide_latched = '1' else '0';

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
		port map(
			source => source_latched,
			destination => destination_latched,
			subtract => subtract_latched,
			compare_only => compare_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => add_subtract_result,
			condition_codes => add_subtract_condition_codes,
			exception_status => add_subtract_status
		);

	multiply : entity work.TG68K_FPU_Multiply
		port map(
			source => source_latched,
			destination => destination_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => multiply_result,
			condition_codes => multiply_condition_codes,
			exception_status => multiply_status
		);

	divide : entity work.TG68K_FPU_Divide
		port map(
			clk => clk,
			nReset => nReset,
			start => divide_start,
			source => source_latched,
			destination => destination_latched,
			rounding_precision => precision_latched,
			rounding_mode => mode_latched,
			result => divide_result,
			condition_codes => divide_condition_codes,
			exception_status => divide_status,
			busy => open,
			done => divide_done
		);

	outputs : process(state, format_latched, address_latched,
		function_code_latched, transfer_index, result_latched,
		condition_codes_latched, status_latched, write_result_latched,
		snan_enable_latched, operr_enable_latched, dz_enable_latched)
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
							if operation = FPU_OP_MUL then
								multiply_latched <= '1';
							else
								multiply_latched <= '0';
							end if;
							if operation = FPU_OP_DIV then
								divide_latched <= '1';
							else
								divide_latched <= '0';
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
						elsif multiply_latched = '1' then
							result_latched <= multiply_result;
							condition_codes_latched <= multiply_condition_codes;
							status_latched <= multiply_status;
							state <= COMMIT;
						else
							result_latched <= add_subtract_result;
							condition_codes_latched <=
								add_subtract_condition_codes;
							status_latched <= add_subtract_status;
							state <= COMMIT;
						end if;

					when WAIT_DIVIDE =>
						if divide_done = '1' then
							result_latched <= divide_result;
							condition_codes_latched <= divide_condition_codes;
							status_latched <= divide_status;
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
