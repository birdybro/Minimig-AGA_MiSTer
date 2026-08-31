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
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_System is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		null_restore : in std_logic;

		opcode : in std_logic_vector(15 downto 0);
		command_word : in std_logic_vector(15 downto 0);
		instruction_address : in std_logic_vector(31 downto 0);
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		integer_register_data : in std_logic_vector(31 downto 0);
		instruction_start : in std_logic;
		retry : in std_logic;

		instruction_match : out std_logic;
		instruction_valid : out std_logic;
		instruction_implemented : out std_logic;
		instruction_requires_command_word : out std_logic;
		instruction_requires_effective_address : out std_logic;
		integer_register_select : out std_logic_vector(2 downto 0);
		instruction_busy : out std_logic;
		instruction_done : out std_logic;
		fline_exception : out std_logic;
		unimplemented_exception : out std_logic;
		bus_error_exception : out std_logic;
		floating_point_exception : out std_logic;
		floating_point_exception_class : out fpu_exception_t;

		memory_ready : in std_logic;
		memory_error : in std_logic;
		memory_read_data : in std_logic_vector(15 downto 0);
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_nuds : out std_logic;
		memory_nlds : out std_logic;
		memory_function_code : out std_logic_vector(2 downto 0);

		integer_register_write : out std_logic;
		integer_register_write_data : out std_logic_vector(31 downto 0);
		integer_register_write_format : out fpu_operand_format_t;

		fp_registers_out : out fpu_register_array_t;
		fpcr_out : out std_logic_vector(31 downto 0);
		fpsr_out : out std_logic_vector(31 downto 0);
		fpiar_out : out std_logic_vector(31 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_System is
	signal decoded_match : std_logic;
	signal decoded_valid : std_logic;
	signal decoded_fline : std_logic;
	signal decoded_requires_command : std_logic;
	signal decoded_requires_ea : std_logic;
	signal decoded_family : fpu_instruction_family_t;
	signal decoded_operation : fpu_operation_t;
	signal decoded_format : fpu_operand_format_t;
	signal decoded_source_register : std_logic_vector(2 downto 0);
	signal decoded_destination_register : std_logic_vector(2 downto 0);
	signal move_implemented : std_logic;
	signal move_start : std_logic;
	signal move_reset : std_logic;
	signal move_direction : fpu_move_direction_t;
	signal move_external_data_register : std_logic;
	signal move_source_select : std_logic_vector(2 downto 0);
	signal source_select_latched : std_logic_vector(2 downto 0) := (others => '0');
	signal destination_select_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal integer_select_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal fp_data_select : std_logic_vector(2 downto 0);
	signal fp_data_read : fpu_extended_t;
	signal move_fp_write : std_logic;
	signal move_fp_write_data : fpu_extended_t;
	signal move_status_write : std_logic;
	signal move_condition_codes_write : std_logic;
	signal move_condition_codes : std_logic_vector(3 downto 0);
	signal move_exception_status : std_logic_vector(7 downto 0);
	signal move_busy : std_logic;
	signal move_done : std_logic;
	signal move_bus_error : std_logic;
	signal rounding_precision : fpu_rounding_precision_t;
	signal rounding_mode : fpu_rounding_mode_t;
	signal fpcr : std_logic_vector(31 downto 0);
	signal unsupported_done : std_logic := '0';
	signal unsupported_exception : std_logic := '0';
	signal fpiar_write : std_logic;
begin
	decoder : entity work.TG68K_FPU_Decoder
		port map(
			opcode => opcode,
			command_word => command_word,
			instruction_match => decoded_match,
			instruction_valid => decoded_valid,
			fline_exception => decoded_fline,
			requires_command_word => decoded_requires_command,
			requires_effective_address => decoded_requires_ea,
			family => decoded_family,
			operation => decoded_operation,
			operand_format => decoded_format,
			source_register => decoded_source_register,
			destination_register => decoded_destination_register,
			control_register_list => open,
			register_list => open,
			conditional_predicate => open
		);

	move_implemented <= '1' when
		(decoded_family = FPU_FAMILY_REGISTER_OPERATION and
		decoded_operation = FPU_OP_MOVE) or
		(decoded_family = FPU_FAMILY_EXTERNAL_OPERATION and
		decoded_operation = FPU_OP_MOVE and
		decoded_format /= FPU_FORMAT_PACKED and
		decoded_format /= FPU_FORMAT_DYNAMIC_PACKED) or
		(decoded_family = FPU_FAMILY_MOVE_TO_EXTERNAL and
		decoded_format /= FPU_FORMAT_PACKED and
		decoded_format /= FPU_FORMAT_DYNAMIC_PACKED) else '0';
	move_start <= instruction_start and decoded_match and decoded_valid and
		move_implemented and not move_busy;
	move_reset <= nReset and not null_restore;
	move_external_data_register <= '1' when opcode(5 downto 3) = "000" else '0';
	move_direction <= FPU_MOVE_REGISTER_TO_REGISTER when
		decoded_family = FPU_FAMILY_REGISTER_OPERATION else
		FPU_MOVE_EXTERNAL_TO_REGISTER when
		decoded_family = FPU_FAMILY_EXTERNAL_OPERATION else
		FPU_MOVE_REGISTER_TO_EXTERNAL;
	move_source_select <= decoded_destination_register when
		decoded_family = FPU_FAMILY_MOVE_TO_EXTERNAL else
		decoded_source_register;
	fp_data_select <= move_source_select when move_start = '1' else
		destination_select_latched when move_fp_write = '1' else
		source_select_latched;
	fpiar_write <= move_start when fpcr(15 downto 8) /= x"00" else '0';

	instruction_match <= decoded_match;
	instruction_valid <= decoded_valid;
	instruction_implemented <= move_implemented;
	instruction_requires_command_word <= decoded_requires_command;
	instruction_requires_effective_address <= decoded_requires_ea when
		opcode(5 downto 3) /= "000" else '0';
	integer_register_select <= opcode(2 downto 0) when move_busy = '0' else
		integer_select_latched;
	instruction_busy <= move_busy;
	instruction_done <= move_done or unsupported_done;
	fline_exception <= decoded_fline;
	unimplemented_exception <= unsupported_exception;
	bus_error_exception <= move_bus_error;
	fpcr_out <= fpcr;

	dispatch_state : process(clk)
	begin
		if rising_edge(clk) then
			unsupported_done <= '0';
			unsupported_exception <= '0';
			if nReset = '0' or null_restore = '1' then
				source_select_latched <= (others => '0');
				destination_select_latched <= (others => '0');
				integer_select_latched <= (others => '0');
			elsif instruction_start = '1' and move_busy = '0' and
					decoded_match = '1' and decoded_valid = '1' then
				if move_implemented = '1' then
					source_select_latched <= move_source_select;
					destination_select_latched <= decoded_destination_register;
					integer_select_latched <= opcode(2 downto 0);
				else
					unsupported_done <= '1';
					unsupported_exception <= '1';
				end if;
			end if;
		end if;
	end process;

	move_controller : entity work.TG68K_FPU_Move_Controller
		port map(
			clk => clk,
			nReset => move_reset,
			start => move_start,
			direction => move_direction,
			operand_format => decoded_format,
			external_data_register => move_external_data_register,
			effective_address => effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			fp_register_data => fp_data_read,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => memory_request,
			memory_write => memory_write,
			memory_address => memory_address,
			memory_write_data => memory_write_data,
			memory_nuds => memory_nuds,
			memory_nlds => memory_nlds,
			memory_function_code => memory_function_code,
			fp_register_write => move_fp_write,
			fp_register_write_data => move_fp_write_data,
			integer_register_write => integer_register_write,
			integer_register_write_data => integer_register_write_data,
			integer_register_write_format => integer_register_write_format,
			operation_status_write => move_status_write,
			condition_codes_write => move_condition_codes_write,
			operation_condition_codes => move_condition_codes,
			operation_exception_status => move_exception_status,
			busy => move_busy,
			done => move_done,
			bus_error_exception => move_bus_error
		);

	state : entity work.TG68K_FPU
		port map(
			clk => clk,
			nReset => nReset,
			null_restore => null_restore,
			data_register_select => fp_data_select,
			data_register_write => move_fp_write,
			data_register_write_data => move_fp_write_data,
			data_register_read_data => fp_data_read,
			control_register_select => FPU_REG_FPIAR,
			control_register_write => fpiar_write,
			control_register_write_data => instruction_address,
			control_register_read_data => open,
			operation_status_write => move_status_write,
			condition_codes_write => move_condition_codes_write,
			operation_condition_codes => move_condition_codes,
			quotient_write => '0',
			operation_quotient => (others => '0'),
			operation_exception_status => move_exception_status,
			fp_registers_out => fp_registers_out,
			fpcr_out => fpcr,
			fpsr_out => fpsr_out,
			fpiar_out => fpiar_out,
			rounding_precision_out => rounding_precision,
			rounding_mode_out => rounding_mode,
			exception_trap => floating_point_exception,
			exception_class => floating_point_exception_class
		);
end architecture;
