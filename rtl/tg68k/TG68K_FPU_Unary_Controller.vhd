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

entity TG68K_FPU_Unary_Controller is
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

architecture rtl of TG68K_FPU_Unary_Controller is
	type controller_state_t is (IDLE, LOAD_MEMORY, UNPACK_OPERAND, EXECUTE,
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
	signal negate_latched : std_logic := '0';
	signal test_latched : std_logic := '0';
	signal extract_latched : std_logic := '0';
	signal get_exponent_latched : std_logic := '0';
	signal format_latched : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal snan_enable_latched : std_logic := '0';
	signal operand_error_enable_latched : std_logic := '0';
	signal external_buffer : std_logic_vector(95 downto 0) := (others => '0');
	signal operand_latched : fpu_extended_t := (others => '0');
	signal result_latched : fpu_extended_t := (others => '0');
	signal status_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal write_result_latched : std_logic := '0';
	signal transfer_index : natural range 0 to 5 := 0;

	signal unpacked_operand : fpu_extended_t;
	signal operand_class : fpu_data_class_t;
	signal extracted_result : fpu_extended_t;
	signal extracted_status : std_logic_vector(7 downto 0);
begin
	operand_class <= fpu_classify(operand_latched);

	unpack : entity work.TG68K_FPU_Convert
		port map(
			source_format => format_latched,
			source_data => external_buffer,
			extended_data => unpacked_operand,
			conversion_valid => open,
			extended_source => (others => '0'),
			external_extended_data => open
		);

	extract : entity work.TG68K_FPU_Extract
		port map(
			source => operand_latched,
			get_exponent => get_exponent_latched,
			result => extracted_result,
			condition_codes => open,
			exception_status => extracted_status
		);

	outputs : process(state, format_latched, address_latched,
		function_code_latched, transfer_index, result_latched, status_latched,
		write_result_latched, snan_enable_latched,
		operand_error_enable_latched)
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
		operation_condition_codes <= fpu_condition_codes(result_latched);
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

		suppress_write := (status_latched(6) = '1' and
			snan_enable_latched = '1') or
			(status_latched(5) = '1' and
			operand_error_enable_latched = '1');
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
		variable status : std_logic_vector(7 downto 0);
		variable count : natural range 1 to 6;
		variable result : fpu_extended_t;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				negate_latched <= '0';
				test_latched <= '0';
				extract_latched <= '0';
				get_exponent_latched <= '0';
				format_latched <= FPU_FORMAT_EXTENDED;
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				snan_enable_latched <= '0';
				operand_error_enable_latched <= '0';
				external_buffer <= (others => '0');
				operand_latched <= (others => '0');
				result_latched <= (others => '0');
				status_latched <= (others => '0');
				write_result_latched <= '0';
				transfer_index <= 0;
			else
				case state is
					when IDLE =>
						if start = '1' then
							if operation = FPU_OP_NEG then
								negate_latched <= '1';
							else
								negate_latched <= '0';
							end if;
							if operation = FPU_OP_TST then
								test_latched <= '1';
							else
								test_latched <= '0';
							end if;
							if operation = FPU_OP_GETEXP or
									operation = FPU_OP_GETMAN then
								extract_latched <= '1';
							else
								extract_latched <= '0';
							end if;
							if operation = FPU_OP_GETEXP then
								get_exponent_latched <= '1';
							else
								get_exponent_latched <= '0';
							end if;
							format_latched <= operand_format;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							snan_enable_latched <= exception_enable(6);
							operand_error_enable_latched <= exception_enable(5);
							external_buffer <= (others => '0');
							status_latched <= (others => '0');
							write_result_latched <= '0';
							transfer_index <= 0;
							if external_source = '0' then
								operand_latched <= fp_register_data;
								state <= EXECUTE;
							elsif external_data_register = '1' then
								external_buffer(31 downto 0) <= integer_register_data;
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
									read_word(7 downto 0) := memory_read_data(15 downto 8);
								else
									read_word(7 downto 0) := memory_read_data(7 downto 0);
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
						operand_latched <= unpacked_operand;
						state <= EXECUTE;

					when EXECUTE =>
						if extract_latched = '1' then
							result_latched <= extracted_result;
							status_latched <= extracted_status;
							write_result_latched <= '1';
						else
							status := (others => '0');
							result := operand_latched;
							if operand_class = FPU_CLASS_SIGNALING_NAN then
								status(6) := '1';
								result(62) := '1';
							elsif operand_class = FPU_CLASS_NORMAL and
									operand_latched(78 downto 64) =
									"000000000000000" then
								status(3) := '1';
							end if;
							if test_latched = '1' then
								result_latched <= operand_latched;
								status(3) := '0';
								write_result_latched <= '0';
							else
								if operand_class /= FPU_CLASS_QUIET_NAN and
										operand_class /= FPU_CLASS_SIGNALING_NAN then
									if negate_latched = '1' then
										result(79) := not operand_latched(79);
									else
										result(79) := '0';
									end if;
								end if;
								result_latched <= result;
								write_result_latched <= '1';
							end if;
							status_latched <= status;
						end if;
						state <= COMMIT;

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
