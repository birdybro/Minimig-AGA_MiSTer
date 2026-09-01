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
		address_register_data : in std_logic_vector(31 downto 0);
		instruction_start : in std_logic;
		retry : in std_logic;

		instruction_match : out std_logic;
		instruction_valid : out std_logic;
		instruction_implemented : out std_logic;
		instruction_requires_command_word : out std_logic;
		instruction_requires_effective_address : out std_logic;
		instruction_operand_format : out fpu_operand_format_t;
		instruction_family : out fpu_instruction_family_t;
		integer_register_select : out std_logic_vector(2 downto 0);
		address_register_select : out std_logic_vector(2 downto 0);
		instruction_busy : out std_logic;
		instruction_done : out std_logic;
		fline_exception : out std_logic;
		unimplemented_exception : out std_logic;
		format_error_exception : out std_logic;
		bus_error_exception : out std_logic;
		floating_point_exception : out std_logic;
		floating_point_exception_class : out fpu_exception_t;
		conditional_branch_taken : out std_logic;
		conditional_trap_taken : out std_logic;

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
		address_register_write : out std_logic;
		address_register_write_data : out std_logic_vector(31 downto 0);

		fp_registers_out : out fpu_register_array_t;
		fpcr_out : out std_logic_vector(31 downto 0);
		fpsr_out : out std_logic_vector(31 downto 0);
		fpiar_out : out std_logic_vector(31 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_System is
	function move_byte_count(
		format_value : fpu_operand_format_t;
		register_select : std_logic_vector(2 downto 0)) return natural is
	begin
		case format_value is
			when FPU_FORMAT_BYTE_INTEGER =>
				if register_select = "111" then
					return 2;
				else
					return 1;
				end if;
			when FPU_FORMAT_WORD_INTEGER => return 2;
			when FPU_FORMAT_LONG_INTEGER | FPU_FORMAT_SINGLE => return 4;
			when FPU_FORMAT_DOUBLE => return 8;
			when others => return 12;
		end case;
	end function;

	function control_byte_count(
		register_mask : std_logic_vector(2 downto 0)) return natural is
		variable count : natural := 0;
	begin
		for index in register_mask'range loop
			if register_mask(index) = '1' then
				count := count + 1;
			end if;
		end loop;
		if count = 0 then
			return 4;
		end if;
		return count * 4;
	end function;

	function movem_byte_count(
		register_mask : std_logic_vector(7 downto 0)) return natural is
		variable count : natural := 0;
	begin
		for index in register_mask'range loop
			if register_mask(index) = '1' then
				count := count + 1;
			end if;
		end loop;
		return count * 12;
	end function;

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
	signal decoded_control_registers : std_logic_vector(2 downto 0);
	signal decoded_register_list : std_logic_vector(7 downto 0);
	signal decoded_predicate : std_logic_vector(5 downto 0);

	signal move_implemented : std_logic;
	signal control_implemented : std_logic;
	signal movem_implemented : std_logic;
	signal unary_implemented : std_logic;
	signal binary_implemented : std_logic;
	signal conditional_implemented : std_logic;
	signal state_frame_implemented : std_logic;
	signal operation_implemented : std_logic;
	signal operation_busy : std_logic;
	signal operation_done : std_logic;
	signal operation_byte_count : natural range 0 to 96;
	signal operation_effective_address : std_logic_vector(31 downto 0);
	signal address_update_base : std_logic_vector(31 downto 0);
	signal subsystem_reset : std_logic;
	signal integer_operand_select : std_logic_vector(2 downto 0);

	signal move_start : std_logic;
	signal move_direction : fpu_move_direction_t;
	signal move_external_data_register : std_logic;
	signal move_source_select : std_logic_vector(2 downto 0);
	signal source_select_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal destination_select_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal fp_data_select : std_logic_vector(2 downto 0);
	signal fp_data_read : fpu_extended_t;
	signal move_fp_write : std_logic;
	signal move_fp_write_data : fpu_extended_t;
	signal move_status_write : std_logic;
	signal move_condition_codes_write : std_logic;
	signal move_condition_codes : std_logic_vector(3 downto 0);
	signal move_exception_status : std_logic_vector(7 downto 0);
	signal move_exceptional_operand : fpu_extended_t;
	signal move_busy : std_logic;
	signal move_done : std_logic;
	signal move_bus_error : std_logic;
	signal move_memory_request : std_logic;
	signal move_memory_write : std_logic;
	signal move_memory_address : std_logic_vector(31 downto 0);
	signal move_memory_write_data : std_logic_vector(15 downto 0);
	signal move_memory_nuds : std_logic;
	signal move_memory_nlds : std_logic;
	signal move_memory_fc : std_logic_vector(2 downto 0);
	signal move_integer_write : std_logic;
	signal move_integer_write_data : std_logic_vector(31 downto 0);
	signal move_integer_write_format : fpu_operand_format_t;
	signal move_packed_start : std_logic;
	signal move_packed_source : std_logic_vector(95 downto 0);
	signal move_k_factor : std_logic_vector(6 downto 0);

	signal control_start : std_logic;
	signal control_external_to_control : std_logic;
	signal control_data_register_direct : std_logic;
	signal control_address_register_direct : std_logic;
	signal control_busy : std_logic;
	signal control_done : std_logic;
	signal control_bus_error : std_logic;
	signal control_register_select : fpu_control_register_t;
	signal control_register_read_data : std_logic_vector(31 downto 0);
	signal control_register_write : std_logic;
	signal control_register_write_data : std_logic_vector(31 downto 0);
	signal control_memory_request : std_logic;
	signal control_memory_write : std_logic;
	signal control_memory_address : std_logic_vector(31 downto 0);
	signal control_memory_write_data : std_logic_vector(15 downto 0);
	signal control_memory_fc : std_logic_vector(2 downto 0);
	signal control_integer_write : std_logic;
	signal control_integer_write_data : std_logic_vector(31 downto 0);
	signal control_address_write : std_logic;
	signal control_address_write_data : std_logic_vector(31 downto 0);

	signal movem_start : std_logic;
	signal movem_memory_to_register : std_logic;
	signal movem_predecrement : std_logic;
	signal movem_busy : std_logic;
	signal movem_done : std_logic;
	signal movem_bus_error : std_logic;
	signal movem_register_mask : std_logic_vector(7 downto 0);
	signal movem_fp_select : std_logic_vector(2 downto 0);
	signal movem_fp_write : std_logic;
	signal movem_fp_write_data : fpu_extended_t;
	signal movem_memory_request : std_logic;
	signal movem_memory_write : std_logic;
	signal movem_memory_address : std_logic_vector(31 downto 0);
	signal movem_memory_write_data : std_logic_vector(15 downto 0);
	signal movem_memory_fc : std_logic_vector(2 downto 0);

	signal unary_start : std_logic;
	signal unary_external_source : std_logic;
	signal unary_external_data_register : std_logic;
	signal unary_fp_write : std_logic;
	signal unary_fp_write_data : fpu_extended_t;
	signal unary_status_write : std_logic;
	signal unary_condition_codes_write : std_logic;
	signal unary_condition_codes : std_logic_vector(3 downto 0);
	signal unary_exception_status : std_logic_vector(7 downto 0);
	signal unary_exceptional_operand : fpu_extended_t;
	signal unary_busy : std_logic;
	signal unary_done : std_logic;
	signal unary_bus_error : std_logic;
	signal unary_memory_request : std_logic;
	signal unary_memory_write : std_logic;
	signal unary_memory_address : std_logic_vector(31 downto 0);
	signal unary_memory_write_data : std_logic_vector(15 downto 0);
	signal unary_memory_nuds : std_logic;
	signal unary_memory_nlds : std_logic;
	signal unary_memory_fc : std_logic_vector(2 downto 0);
	signal unary_packed_start : std_logic;
	signal unary_packed_source : std_logic_vector(95 downto 0);

	signal binary_start : std_logic;
	signal binary_external_source : std_logic;
	signal binary_external_data_register : std_logic;
	signal binary_fp_write : std_logic;
	signal binary_fp_write_data : fpu_extended_t;
	signal binary_fp_write_cosine : std_logic;
	signal binary_status_write : std_logic;
	signal binary_condition_codes_write : std_logic;
	signal binary_condition_codes : std_logic_vector(3 downto 0);
	signal binary_quotient_write : std_logic;
	signal binary_quotient : std_logic_vector(7 downto 0);
	signal binary_exception_status : std_logic_vector(7 downto 0);
	signal binary_exceptional_operand : fpu_extended_t;
	signal binary_busy : std_logic;
	signal binary_done : std_logic;
	signal binary_bus_error : std_logic;
	signal binary_memory_request : std_logic;
	signal binary_memory_write : std_logic;
	signal binary_memory_address : std_logic_vector(31 downto 0);
	signal binary_memory_write_data : std_logic_vector(15 downto 0);
	signal binary_memory_nuds : std_logic;
	signal binary_memory_nlds : std_logic;
	signal binary_memory_fc : std_logic_vector(2 downto 0);
	signal binary_packed_start : std_logic;
	signal binary_packed_source : std_logic_vector(95 downto 0);

	signal packed_conversion_start : std_logic;
	signal packed_conversion_source : std_logic_vector(95 downto 0);
	signal packed_conversion_result : fpu_extended_t;
	signal packed_conversion_status : std_logic_vector(7 downto 0);
	signal packed_conversion_done : std_logic;

	signal constant_implemented : std_logic;
	signal constant_start : std_logic;
	signal constant_fp_write : std_logic;
	signal constant_fp_write_data : fpu_extended_t;
	signal conditional_start : std_logic;
	signal conditional_data_register : std_logic;
	signal conditional_busy : std_logic;
	signal conditional_done : std_logic;
	signal conditional_bus_error : std_logic;
	signal conditional_memory_request : std_logic;
	signal conditional_memory_write : std_logic;
	signal conditional_memory_address : std_logic_vector(31 downto 0);
	signal conditional_memory_write_data : std_logic_vector(15 downto 0);
	signal conditional_memory_nuds : std_logic;
	signal conditional_memory_nlds : std_logic;
	signal conditional_memory_fc : std_logic_vector(2 downto 0);
	signal conditional_integer_write : std_logic;
	signal conditional_integer_write_data : std_logic_vector(31 downto 0);
	signal conditional_integer_write_format : fpu_operand_format_t;
	signal conditional_status_write : std_logic;
	signal conditional_bsun : std_logic;
	signal constant_status_write : std_logic;
	signal constant_condition_codes_write : std_logic;
	signal constant_condition_codes : std_logic_vector(3 downto 0);
	signal constant_exception_status : std_logic_vector(7 downto 0);
	signal constant_busy : std_logic;
	signal constant_done : std_logic;

	signal state_frame_start : std_logic;
	signal state_frame_busy : std_logic;
	signal state_frame_done : std_logic;
	signal state_frame_bus_error : std_logic;
	signal state_frame_format_error : std_logic;
	signal state_frame_memory_request : std_logic;
	signal state_frame_memory_write : std_logic;
	signal state_frame_memory_address : std_logic_vector(31 downto 0);
	signal state_frame_memory_write_data : std_logic_vector(15 downto 0);
	signal state_frame_memory_nuds : std_logic;
	signal state_frame_memory_nlds : std_logic;
	signal state_frame_memory_fc : std_logic_vector(2 downto 0);
	signal state_frame_byte_count : natural range 0 to
		FPU_STATE_FRAME_IDLE_BYTES_68882;
	signal state_frame_save_complete : std_logic;
	signal state_frame_restore_null : std_logic;
	signal state_frame_restore_idle : std_logic;
	signal state_frame_restore_pending : std_logic;
	signal state_frame_restore_command : std_logic_vector(31 downto 0);
	signal state_frame_restore_operand : fpu_extended_t;

	signal effective_address_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal address_mode_latched : std_logic_vector(2 downto 0) := "000";
	signal address_select_latched : std_logic_vector(2 downto 0) := "000";
	signal cosine_destination_select_latched : std_logic_vector(2 downto 0) :=
		"000";
	signal integer_select_latched : std_logic_vector(2 downto 0) := "000";
	signal transfer_bytes_latched : natural range 0 to 96 := 1;
	signal rounding_precision : fpu_rounding_precision_t;
	signal rounding_mode : fpu_rounding_mode_t;
	signal fpcr : std_logic_vector(31 downto 0);
	signal fpsr : std_logic_vector(31 downto 0);
	signal unsupported_done : std_logic := '0';
	signal unsupported_exception : std_logic := '0';
	signal fpiar_write : std_logic;
	signal state_control_select : fpu_control_register_t;
	signal state_control_write : std_logic;
	signal state_control_write_data : std_logic_vector(31 downto 0);
	signal state_fp_write : std_logic;
	signal state_fp_write_data : fpu_extended_t;
	signal state_status_write : std_logic;
	signal state_condition_codes_write : std_logic;
	signal state_condition_codes : std_logic_vector(3 downto 0);
	signal state_exception_status : std_logic_vector(7 downto 0);
	signal state_initialized : std_logic;
	signal state_exception_pending : std_logic;
	signal state_pending_exception_class : fpu_exception_t;
	signal state_exception_trap : std_logic;
	signal state_exception_class : fpu_exception_t;
	signal pending_instruction_blocked : std_logic;
	signal pending_exception_done : std_logic := '0';
	signal pending_exception_trap : std_logic := '0';
	signal command_condition_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal issued_command_condition_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal exceptional_operand_latched : fpu_extended_t := (others => '0');
	signal operation_exceptional_operand : fpu_extended_t;
begin
	packed_conversion_start <= move_packed_start or unary_packed_start or
		binary_packed_start;
	packed_conversion_source <= binary_packed_source when
		binary_packed_start = '1' else unary_packed_source when
		unary_packed_start = '1' else move_packed_source;

	packed_converter : entity work.TG68K_FPU_Packed_To_Extended
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => packed_conversion_start,
			source => packed_conversion_source,
			rounding_mode => rounding_mode,
			result => packed_conversion_result,
			exception_status => packed_conversion_status,
			busy => open,
			done => packed_conversion_done
		);

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
			control_register_list => decoded_control_registers,
			register_list => decoded_register_list,
			conditional_predicate => decoded_predicate
		);

	move_implemented <= '1' when
		(decoded_family = FPU_FAMILY_REGISTER_OPERATION and
		decoded_operation = FPU_OP_MOVE) or
		(decoded_family = FPU_FAMILY_EXTERNAL_OPERATION and
		decoded_operation = FPU_OP_MOVE and
		decoded_format /= FPU_FORMAT_DYNAMIC_PACKED) or
		decoded_family = FPU_FAMILY_MOVE_TO_EXTERNAL else '0';
	control_implemented <= '1' when
		decoded_family = FPU_FAMILY_MOVE_TO_CONTROL or
		decoded_family = FPU_FAMILY_MOVE_FROM_CONTROL else '0';
	movem_implemented <= '1' when
		decoded_family = FPU_FAMILY_MOVEM_TO_FP or
		decoded_family = FPU_FAMILY_MOVEM_FROM_FP else '0';
	constant_implemented <= '1' when
		decoded_family = FPU_FAMILY_MOVE_CONSTANT else '0';
	unary_implemented <= '1' when
		(decoded_family = FPU_FAMILY_REGISTER_OPERATION or
		decoded_family = FPU_FAMILY_EXTERNAL_OPERATION) and
		(decoded_operation = FPU_OP_ABS or decoded_operation = FPU_OP_NEG or
		decoded_operation = FPU_OP_GETEXP or
		decoded_operation = FPU_OP_GETMAN or decoded_operation = FPU_OP_TST) and
		(decoded_family = FPU_FAMILY_REGISTER_OPERATION or
		decoded_format /= FPU_FORMAT_DYNAMIC_PACKED) else '0';
	binary_implemented <= '1' when
		(decoded_family = FPU_FAMILY_REGISTER_OPERATION or
		decoded_family = FPU_FAMILY_EXTERNAL_OPERATION) and
		(decoded_operation = FPU_OP_INT or decoded_operation = FPU_OP_INTRZ or
		decoded_operation = FPU_OP_SQRT or decoded_operation = FPU_OP_ADD or
		decoded_operation = FPU_OP_SUB or
		decoded_operation = FPU_OP_MUL or decoded_operation = FPU_OP_DIV or
		decoded_operation = FPU_OP_SGLMUL or
		decoded_operation = FPU_OP_SGLDIV or
		decoded_operation = FPU_OP_MOD or decoded_operation = FPU_OP_REM or
		decoded_operation = FPU_OP_SCALE or
		decoded_operation = FPU_OP_LOGNP1 or
		decoded_operation = FPU_OP_LOGN or
		decoded_operation = FPU_OP_LOG10 or
		decoded_operation = FPU_OP_LOG2 or
		decoded_operation = FPU_OP_ATAN or
		decoded_operation = FPU_OP_ASIN or
		decoded_operation = FPU_OP_ACOS or
		decoded_operation = FPU_OP_SIN or
		decoded_operation = FPU_OP_COS or
		decoded_operation = FPU_OP_TAN or
		decoded_operation = FPU_OP_SINCOS or
		decoded_operation = FPU_OP_ATANH or
		decoded_operation = FPU_OP_SINH or
		decoded_operation = FPU_OP_COSH or
		decoded_operation = FPU_OP_TANH or
		decoded_operation = FPU_OP_ETOXM1 or
		decoded_operation = FPU_OP_ETOX or
		decoded_operation = FPU_OP_TWOTOX or
		decoded_operation = FPU_OP_TENTOX or
		decoded_operation = FPU_OP_CMP) and
		(decoded_family = FPU_FAMILY_REGISTER_OPERATION or
		decoded_format /= FPU_FORMAT_DYNAMIC_PACKED) else '0';
	conditional_implemented <= '1' when
		decoded_family = FPU_FAMILY_SCC or
		decoded_family = FPU_FAMILY_DBCC or
		decoded_family = FPU_FAMILY_TRAPCC or
		decoded_family = FPU_FAMILY_BCC_WORD or
		decoded_family = FPU_FAMILY_BCC_LONG else '0';
	state_frame_implemented <= '1' when
		decoded_family = FPU_FAMILY_SAVE or
		decoded_family = FPU_FAMILY_RESTORE else '0';
	operation_implemented <= move_implemented or control_implemented or
		movem_implemented or constant_implemented or unary_implemented or
		binary_implemented or conditional_implemented or
		state_frame_implemented;
	operation_busy <= move_busy or control_busy or movem_busy or unary_busy or
		binary_busy or constant_busy or conditional_busy or state_frame_busy;
	operation_done <= move_done or control_done or movem_done or unary_done or
		binary_done or constant_done or conditional_done or state_frame_done;
	subsystem_reset <= nReset and not null_restore and
		not state_frame_restore_null;
	pending_instruction_blocked <= '1' when state_exception_pending = '1' and
		decoded_family /= FPU_FAMILY_MOVEM_TO_FP and
		decoded_family /= FPU_FAMILY_MOVEM_FROM_FP and
		decoded_family /= FPU_FAMILY_MOVE_TO_CONTROL and
		decoded_family /= FPU_FAMILY_MOVE_FROM_CONTROL and
		decoded_family /= FPU_FAMILY_SAVE and
		decoded_family /= FPU_FAMILY_RESTORE else '0';

	move_start <= instruction_start and decoded_match and decoded_valid and
		move_implemented and not operation_busy and
		not pending_instruction_blocked;
	control_start <= instruction_start and decoded_match and decoded_valid and
		control_implemented and not operation_busy;
	movem_start <= instruction_start and decoded_match and decoded_valid and
		movem_implemented and not operation_busy;
	constant_start <= instruction_start and decoded_match and decoded_valid and
		constant_implemented and not operation_busy and
		not pending_instruction_blocked;
	unary_start <= instruction_start and decoded_match and decoded_valid and
		unary_implemented and not operation_busy and
		not pending_instruction_blocked;
	binary_start <= instruction_start and decoded_match and decoded_valid and
		binary_implemented and not operation_busy and
		not pending_instruction_blocked;
	conditional_start <= instruction_start and decoded_match and decoded_valid and
		conditional_implemented and not operation_busy and
		not pending_instruction_blocked;
	state_frame_start <= instruction_start and decoded_match and decoded_valid and
		state_frame_implemented and not operation_busy;
	unary_external_source <= '1' when
		decoded_family = FPU_FAMILY_EXTERNAL_OPERATION else '0';
	unary_external_data_register <= '1' when
		opcode(5 downto 3) = "000" else '0';
	binary_external_source <= '1' when
		decoded_family = FPU_FAMILY_EXTERNAL_OPERATION else '0';
	binary_external_data_register <= '1' when
		opcode(5 downto 3) = "000" else '0';
	movem_memory_to_register <= '1' when
		decoded_family = FPU_FAMILY_MOVEM_TO_FP else '0';
	movem_predecrement <= '1' when opcode(5 downto 3) = "100" else '0';
	control_external_to_control <= '1' when
		decoded_family = FPU_FAMILY_MOVE_TO_CONTROL else '0';
	control_data_register_direct <= '1' when
		opcode(5 downto 3) = "000" else '0';
	control_address_register_direct <= '1' when
		opcode(5 downto 3) = "001" else '0';
	move_external_data_register <= '1' when opcode(5 downto 3) = "000" else '0';
	move_direction <= FPU_MOVE_REGISTER_TO_REGISTER when
		decoded_family = FPU_FAMILY_REGISTER_OPERATION else
		FPU_MOVE_EXTERNAL_TO_REGISTER when
		decoded_family = FPU_FAMILY_EXTERNAL_OPERATION else
		FPU_MOVE_REGISTER_TO_EXTERNAL;
	move_source_select <= decoded_destination_register when
		decoded_family = FPU_FAMILY_MOVE_TO_EXTERNAL else
		decoded_source_register;
	move_k_factor <= integer_register_data(6 downto 0) when
		decoded_format = FPU_FORMAT_DYNAMIC_PACKED else command_word(6 downto 0);
	fp_data_select <= movem_fp_select when movem_busy = '1' else
		decoded_source_register when binary_start = '1' else
		decoded_source_register when unary_start = '1' else
		move_source_select when move_start = '1' else
		cosine_destination_select_latched when
			binary_fp_write_cosine = '1' else
		destination_select_latched when binary_busy = '1' else
		destination_select_latched when constant_fp_write = '1' else
		destination_select_latched when unary_fp_write = '1' else
		destination_select_latched when move_fp_write = '1' else
		source_select_latched;
	fpiar_write <= move_start or unary_start or binary_start or constant_start or
		conditional_start when
		fpcr(15 downto 8) /= x"00" else '0';

	movem_register_mask <= integer_register_data(7 downto 0) when
		command_word(11) = '1' else decoded_register_list;
	operation_byte_count <= 1 when decoded_family = FPU_FAMILY_SCC else
		0 when conditional_implemented = '1' or constant_implemented = '1' else
		FPU_STATE_FRAME_IDLE_BYTES_68882 when
			decoded_family = FPU_FAMILY_SAVE and state_initialized = '1' else
		FPU_STATE_FRAME_NULL_BYTES when state_frame_implemented = '1' else
		movem_byte_count(movem_register_mask) when
		movem_implemented = '1' else
		control_byte_count(decoded_control_registers) when
		control_implemented = '1' else
		move_byte_count(decoded_format, opcode(2 downto 0));
	operation_effective_address <= effective_address when movem_implemented = '1' else
		std_logic_vector(unsigned(effective_address) -
		to_unsigned(operation_byte_count, 32)) when
		opcode(5 downto 3) = "100" else effective_address;
	address_update_base <= std_logic_vector(unsigned(effective_address) -
		to_unsigned(operation_byte_count, 32)) when
		opcode(5 downto 3) = "100" else effective_address;
	integer_operand_select <= command_word(6 downto 4) when
		(movem_implemented = '1' and command_word(11) = '1') or
		(decoded_family = FPU_FAMILY_MOVE_TO_EXTERNAL and
		decoded_format = FPU_FORMAT_DYNAMIC_PACKED) else
		opcode(2 downto 0);
	conditional_data_register <= '1' when opcode(5 downto 3) = "000" else '0';

	instruction_match <= decoded_match;
	instruction_valid <= decoded_valid;
	instruction_implemented <= operation_implemented;
	instruction_requires_command_word <= decoded_requires_command;
	instruction_requires_effective_address <= '0' when
		opcode(5 downto 3) = "000" or
		(control_implemented = '1' and opcode(5 downto 3) = "001" and
		decoded_control_registers = "001") else decoded_requires_ea;
	instruction_operand_format <= FPU_FORMAT_EXTENDED when
		constant_implemented = '1' else FPU_FORMAT_LONG_INTEGER when
		control_implemented = '1' else FPU_FORMAT_EXTENDED when
		movem_implemented = '1' else FPU_FORMAT_BYTE_INTEGER when
		decoded_family = FPU_FAMILY_SCC else FPU_FORMAT_WORD_INTEGER when
		decoded_family = FPU_FAMILY_DBCC else decoded_format;
	instruction_family <= decoded_family;
	integer_register_select <= integer_operand_select when operation_busy = '0' else
		integer_select_latched;
	address_register_select <= opcode(2 downto 0) when operation_busy = '0' else
		address_select_latched;
	instruction_busy <= operation_busy;
	instruction_done <= operation_done or unsupported_done or
		pending_exception_done;
	fline_exception <= decoded_fline;
	unimplemented_exception <= unsupported_exception;
	format_error_exception <= state_frame_format_error;
	bus_error_exception <= move_bus_error or control_bus_error or
		movem_bus_error or unary_bus_error or binary_bus_error or
		conditional_bus_error or state_frame_bus_error;
	floating_point_exception <= state_exception_trap or pending_exception_trap;
	floating_point_exception_class <= state_pending_exception_class when
		pending_exception_trap = '1' else state_exception_class;
	fpcr_out <= fpcr;
	fpsr_out <= fpsr;

	memory_request <= state_frame_memory_request when state_frame_busy = '1' else
		conditional_memory_request when conditional_busy = '1' else
		binary_memory_request when binary_busy = '1' else
		unary_memory_request when unary_busy = '1' else
		movem_memory_request when movem_busy = '1' else
		control_memory_request when control_busy = '1' else
		move_memory_request;
	memory_write <= state_frame_memory_write when state_frame_busy = '1' else
		conditional_memory_write when conditional_busy = '1' else
		binary_memory_write when binary_busy = '1' else
		unary_memory_write when unary_busy = '1' else
		movem_memory_write when movem_busy = '1' else
		control_memory_write when control_busy = '1' else
		move_memory_write;
	memory_address <= state_frame_memory_address when state_frame_busy = '1' else
		conditional_memory_address when conditional_busy = '1' else
		binary_memory_address when binary_busy = '1' else
		unary_memory_address when unary_busy = '1' else
		movem_memory_address when movem_busy = '1' else
		control_memory_address when control_busy = '1' else
		move_memory_address;
	memory_write_data <= state_frame_memory_write_data when
		state_frame_busy = '1' else conditional_memory_write_data when
		conditional_busy = '1' else
		binary_memory_write_data when binary_busy = '1' else
		unary_memory_write_data when unary_busy = '1' else
		movem_memory_write_data when movem_busy = '1' else
		control_memory_write_data when control_busy = '1' else
		move_memory_write_data;
	memory_nuds <= state_frame_memory_nuds when state_frame_busy = '1' else
		conditional_memory_nuds when conditional_busy = '1' else
		binary_memory_nuds when binary_busy = '1' else
		unary_memory_nuds when unary_busy = '1' else
		'0' when movem_busy = '1' or control_busy = '1' else
		move_memory_nuds;
	memory_nlds <= state_frame_memory_nlds when state_frame_busy = '1' else
		conditional_memory_nlds when conditional_busy = '1' else
		binary_memory_nlds when binary_busy = '1' else
		unary_memory_nlds when unary_busy = '1' else
		'0' when movem_busy = '1' or control_busy = '1' else
		move_memory_nlds;
	memory_function_code <= state_frame_memory_fc when state_frame_busy = '1' else
		conditional_memory_fc when conditional_busy = '1' else
		binary_memory_fc when binary_busy = '1' else
		unary_memory_fc when unary_busy = '1' else
		movem_memory_fc when movem_busy = '1' else
		control_memory_fc when control_busy = '1' else
		move_memory_fc;

	integer_register_write <= control_integer_write or move_integer_write or
		conditional_integer_write;
	integer_register_write_data <= conditional_integer_write_data when
		conditional_integer_write = '1' else control_integer_write_data when
		control_integer_write = '1' else move_integer_write_data;
	integer_register_write_format <= conditional_integer_write_format when
		conditional_integer_write = '1' else FPU_FORMAT_LONG_INTEGER when
		control_integer_write = '1' else move_integer_write_format;
	address_register_write <= '1' when control_address_write = '1' or
		(operation_done = '1' and (address_mode_latched = "011" or
		address_mode_latched = "100") and transfer_bytes_latched /= 0 and
		state_frame_format_error = '0') else '0';
	address_register_write_data <= control_address_write_data when
		control_address_write = '1' else std_logic_vector(
		unsigned(effective_address_latched) +
		to_unsigned(state_frame_byte_count, 32)) when
		address_mode_latched = "011" and state_frame_done = '1' else
		std_logic_vector(unsigned(effective_address_latched) +
		to_unsigned(transfer_bytes_latched, 32)) when
		address_mode_latched = "011" else effective_address_latched;

	state_control_select <= FPU_REG_FPIAR when fpiar_write = '1' else
		control_register_select;
	state_control_write <= fpiar_write or control_register_write;
	state_control_write_data <= instruction_address when fpiar_write = '1' else
		control_register_write_data;
	state_fp_write <= move_fp_write or movem_fp_write or constant_fp_write or
		unary_fp_write or binary_fp_write;
	state_fp_write_data <= binary_fp_write_data when binary_fp_write = '1' else
		constant_fp_write_data when constant_fp_write = '1' else
		unary_fp_write_data when unary_fp_write = '1' else
		movem_fp_write_data when movem_fp_write = '1' else
		move_fp_write_data;
	state_status_write <= move_status_write or constant_status_write or
		unary_status_write or binary_status_write;
	state_condition_codes_write <= binary_condition_codes_write when
		binary_status_write = '1' else unary_condition_codes_write when
		unary_status_write = '1' else constant_condition_codes_write when
		constant_status_write = '1' else move_condition_codes_write;
	state_condition_codes <= binary_condition_codes when
		binary_status_write = '1' else unary_condition_codes when
		unary_status_write = '1' else constant_condition_codes when
		constant_status_write = '1' else move_condition_codes;
	state_exception_status <= binary_exception_status when
		binary_status_write = '1' else unary_exception_status when
		unary_status_write = '1' else constant_exception_status when
		constant_status_write = '1' else move_exception_status;
	operation_exceptional_operand <= binary_exceptional_operand when
		binary_status_write = '1' else unary_exceptional_operand when
		unary_status_write = '1' else move_exceptional_operand;

	dispatch_state : process(clk)
	begin
		if rising_edge(clk) then
			unsupported_done <= '0';
			unsupported_exception <= '0';
			pending_exception_done <= '0';
			pending_exception_trap <= '0';
			if nReset = '0' or null_restore = '1' or
					state_frame_restore_null = '1' then
				source_select_latched <= (others => '0');
				destination_select_latched <= (others => '0');
				cosine_destination_select_latched <= (others => '0');
				integer_select_latched <= (others => '0');
				effective_address_latched <= (others => '0');
				address_mode_latched <= "000";
				address_select_latched <= "000";
				transfer_bytes_latched <= 1;
				command_condition_latched <= (others => '0');
				issued_command_condition_latched <= (others => '0');
				exceptional_operand_latched <= (others => '0');
			else
				if state_frame_restore_idle = '1' then
					command_condition_latched <= state_frame_restore_command;
					exceptional_operand_latched <= state_frame_restore_operand;
				elsif state_status_write = '1' and
						(state_exception_status and fpcr(15 downto 8)) /= x"00" then
					command_condition_latched <=
						issued_command_condition_latched;
					exceptional_operand_latched <=
						operation_exceptional_operand;
				elsif conditional_status_write = '1' and
						conditional_bsun = '1' and
						fpcr(FPU_FPSR_BSUN_BIT) = '1' then
					command_condition_latched <= command_word & command_word;
					exceptional_operand_latched <= (others => '0');
				end if;

				if instruction_start = '1' and operation_busy = '0' and
						decoded_match = '1' and decoded_valid = '1' then
					if operation_implemented = '1' then
						if pending_instruction_blocked = '1' then
							pending_exception_done <= '1';
							pending_exception_trap <= '1';
						else
							source_select_latched <= move_source_select;
							destination_select_latched <= decoded_destination_register;
							cosine_destination_select_latched <=
								command_word(2 downto 0);
							integer_select_latched <= integer_operand_select;
							effective_address_latched <= address_update_base;
							address_mode_latched <= opcode(5 downto 3);
							address_select_latched <= opcode(2 downto 0);
							transfer_bytes_latched <= operation_byte_count;
							if decoded_family = FPU_FAMILY_MOVE_TO_EXTERNAL then
								issued_command_condition_latched <=
									command_word & command_word;
							elsif conditional_implemented = '1' then
								issued_command_condition_latched <=
									command_word & command_word;
							else
								issued_command_condition_latched <=
									(opcode or x"0080") & command_word;
							end if;
						end if;
					else
						unsupported_done <= '1';
						unsupported_exception <= '1';
					end if;
				end if;
			end if;
		end if;
	end process;

	move_controller : entity work.TG68K_FPU_Move_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => move_start,
			direction => move_direction,
			operand_format => decoded_format,
			external_data_register => move_external_data_register,
			effective_address => operation_effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			fp_register_data => fp_data_read,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			k_factor => move_k_factor,
			packed_conversion_start => move_packed_start,
			packed_conversion_source => move_packed_source,
			packed_conversion_done => packed_conversion_done,
			packed_conversion_result => packed_conversion_result,
			packed_conversion_status => packed_conversion_status,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => move_memory_request,
			memory_write => move_memory_write,
			memory_address => move_memory_address,
			memory_write_data => move_memory_write_data,
			memory_nuds => move_memory_nuds,
			memory_nlds => move_memory_nlds,
			memory_function_code => move_memory_fc,
			fp_register_write => move_fp_write,
			fp_register_write_data => move_fp_write_data,
			integer_register_write => move_integer_write,
			integer_register_write_data => move_integer_write_data,
			integer_register_write_format => move_integer_write_format,
			operation_status_write => move_status_write,
			condition_codes_write => move_condition_codes_write,
			operation_condition_codes => move_condition_codes,
			operation_exception_status => move_exception_status,
			exceptional_operand => move_exceptional_operand,
			busy => move_busy,
			done => move_done,
			bus_error_exception => move_bus_error
		);

	control_controller : entity work.TG68K_FPU_Control_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => control_start,
			external_to_control => control_external_to_control,
			register_mask => decoded_control_registers,
			data_register_direct => control_data_register_direct,
			address_register_direct => control_address_register_direct,
			effective_address => operation_effective_address,
			function_code => function_code,
			data_register_data => integer_register_data,
			address_register_data => address_register_data,
			control_register_read_data => control_register_read_data,
			control_register_select => control_register_select,
			control_register_write => control_register_write,
			control_register_write_data => control_register_write_data,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => control_memory_request,
			memory_write => control_memory_write,
			memory_address => control_memory_address,
			memory_write_data => control_memory_write_data,
			memory_function_code => control_memory_fc,
			data_register_write => control_integer_write,
			data_register_write_data => control_integer_write_data,
			address_register_write => control_address_write,
			address_register_write_data => control_address_write_data,
			busy => control_busy,
			done => control_done,
			bus_error_exception => control_bus_error
		);

	movem_controller : entity work.TG68K_FPU_Movem_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => movem_start,
			memory_to_register => movem_memory_to_register,
			predecrement => movem_predecrement,
			dynamic_list => command_word(11),
			static_register_list => decoded_register_list,
			dynamic_register_data => integer_register_data,
			effective_address => effective_address,
			function_code => function_code,
			fp_register_read_data => fp_data_read,
			fp_register_select => movem_fp_select,
			fp_register_write => movem_fp_write,
			fp_register_write_data => movem_fp_write_data,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => movem_memory_request,
			memory_write => movem_memory_write,
			memory_address => movem_memory_address,
			memory_write_data => movem_memory_write_data,
			memory_function_code => movem_memory_fc,
			busy => movem_busy,
			done => movem_done,
			bus_error_exception => movem_bus_error
		);

	constant_controller : entity work.TG68K_FPU_Constant_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => constant_start,
			rom_offset => command_word(5 downto 0),
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			fp_register_write => constant_fp_write,
			fp_register_write_data => constant_fp_write_data,
			operation_status_write => constant_status_write,
			condition_codes_write => constant_condition_codes_write,
			operation_condition_codes => constant_condition_codes,
			operation_exception_status => constant_exception_status,
			busy => constant_busy,
			done => constant_done
		);

	unary_controller : entity work.TG68K_FPU_Unary_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => unary_start,
			operation => decoded_operation,
			external_source => unary_external_source,
			operand_format => decoded_format,
			external_data_register => unary_external_data_register,
			effective_address => operation_effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			fp_register_data => fp_data_read,
			exception_enable => fpcr(15 downto 8),
			packed_conversion_start => unary_packed_start,
			packed_conversion_source => unary_packed_source,
			packed_conversion_done => packed_conversion_done,
			packed_conversion_result => packed_conversion_result,
			packed_conversion_status => packed_conversion_status,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => unary_memory_request,
			memory_write => unary_memory_write,
			memory_address => unary_memory_address,
			memory_write_data => unary_memory_write_data,
			memory_nuds => unary_memory_nuds,
			memory_nlds => unary_memory_nlds,
			memory_function_code => unary_memory_fc,
			fp_register_write => unary_fp_write,
			fp_register_write_data => unary_fp_write_data,
			operation_status_write => unary_status_write,
			condition_codes_write => unary_condition_codes_write,
			operation_condition_codes => unary_condition_codes,
			operation_exception_status => unary_exception_status,
			exceptional_operand => unary_exceptional_operand,
			busy => unary_busy,
			done => unary_done,
			bus_error_exception => unary_bus_error
		);

	binary_controller : entity work.TG68K_FPU_Binary_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => binary_start,
			operation => decoded_operation,
			external_source => binary_external_source,
			operand_format => decoded_format,
			external_data_register => binary_external_data_register,
			effective_address => operation_effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			fp_register_data => fp_data_read,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			exception_enable => fpcr(15 downto 8),
			packed_conversion_start => binary_packed_start,
			packed_conversion_source => binary_packed_source,
			packed_conversion_done => packed_conversion_done,
			packed_conversion_result => packed_conversion_result,
			packed_conversion_status => packed_conversion_status,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => binary_memory_request,
			memory_write => binary_memory_write,
			memory_address => binary_memory_address,
			memory_write_data => binary_memory_write_data,
			memory_nuds => binary_memory_nuds,
			memory_nlds => binary_memory_nlds,
			memory_function_code => binary_memory_fc,
			fp_register_write => binary_fp_write,
			fp_register_write_data => binary_fp_write_data,
			fp_register_write_cosine => binary_fp_write_cosine,
			operation_status_write => binary_status_write,
			condition_codes_write => binary_condition_codes_write,
			operation_condition_codes => binary_condition_codes,
			quotient_write => binary_quotient_write,
			operation_quotient => binary_quotient,
			operation_exception_status => binary_exception_status,
			exceptional_operand => binary_exceptional_operand,
			busy => binary_busy,
			done => binary_done,
			bus_error_exception => binary_bus_error
		);

	conditional_controller : entity work.TG68K_FPU_Conditional_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => conditional_start,
			family => decoded_family,
			predicate => decoded_predicate,
			condition_codes => fpsr(31 downto 28),
			bsun_enable => fpcr(FPU_FPSR_BSUN_BIT),
			data_register_direct => conditional_data_register,
			integer_register_data => integer_register_data,
			effective_address => operation_effective_address,
			function_code => function_code,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_request => conditional_memory_request,
			memory_write => conditional_memory_write,
			memory_address => conditional_memory_address,
			memory_write_data => conditional_memory_write_data,
			memory_nuds => conditional_memory_nuds,
			memory_nlds => conditional_memory_nlds,
			memory_function_code => conditional_memory_fc,
			integer_register_write => conditional_integer_write,
			integer_register_write_data => conditional_integer_write_data,
			integer_register_write_format => conditional_integer_write_format,
			conditional_status_write => conditional_status_write,
			conditional_bsun => conditional_bsun,
			condition_result => open,
			branch_taken => conditional_branch_taken,
			trap_taken => conditional_trap_taken,
			busy => conditional_busy,
			done => conditional_done,
			bus_error_exception => conditional_bus_error
		);

	state_frame_controller : entity work.TG68K_FPU_State_Frame_Controller
		port map(
			clk => clk,
			nReset => subsystem_reset,
			start => state_frame_start,
			family => decoded_family,
			initialized => state_initialized,
			exception_pending => state_exception_pending,
			command_condition => command_condition_latched,
			exceptional_operand => exceptional_operand_latched,
			effective_address => operation_effective_address,
			function_code => function_code,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => state_frame_memory_request,
			memory_write => state_frame_memory_write,
			memory_address => state_frame_memory_address,
			memory_write_data => state_frame_memory_write_data,
			memory_nuds => state_frame_memory_nuds,
			memory_nlds => state_frame_memory_nlds,
			memory_function_code => state_frame_memory_fc,
			frame_byte_count => state_frame_byte_count,
			save_complete => state_frame_save_complete,
			restore_null => state_frame_restore_null,
			restore_idle => state_frame_restore_idle,
			restore_exception_pending => state_frame_restore_pending,
			restore_command_condition => state_frame_restore_command,
			restore_exceptional_operand => state_frame_restore_operand,
			format_error_exception => state_frame_format_error,
			busy => state_frame_busy,
			done => state_frame_done,
			bus_error_exception => state_frame_bus_error
		);

	state : entity work.TG68K_FPU
		port map(
			clk => clk,
			nReset => nReset,
			null_restore => null_restore or state_frame_restore_null,
			idle_restore => state_frame_restore_idle,
			restore_exception_pending => state_frame_restore_pending,
			instruction_complete => operation_done and not state_frame_done,
			save_complete => state_frame_save_complete,
			data_register_select => fp_data_select,
			data_register_write => state_fp_write,
			data_register_write_data => state_fp_write_data,
			data_register_read_data => fp_data_read,
			control_register_select => state_control_select,
			control_register_write => state_control_write,
			control_register_write_data => state_control_write_data,
			control_register_read_data => control_register_read_data,
			operation_status_write => state_status_write,
			condition_codes_write => state_condition_codes_write,
			operation_condition_codes => state_condition_codes,
			quotient_write => binary_quotient_write,
			operation_quotient => binary_quotient,
			operation_exception_status => state_exception_status,
			conditional_status_write => conditional_status_write,
			conditional_bsun => conditional_bsun,
			fp_registers_out => fp_registers_out,
			fpcr_out => fpcr,
			fpsr_out => fpsr,
			fpiar_out => fpiar_out,
			rounding_precision_out => rounding_precision,
			rounding_mode_out => rounding_mode,
			initialized_out => state_initialized,
			exception_pending_out => state_exception_pending,
			pending_exception_class => state_pending_exception_class,
			exception_trap => state_exception_trap,
			exception_class => state_exception_class
		);
end architecture;
