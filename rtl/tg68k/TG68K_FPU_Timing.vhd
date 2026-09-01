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

entity TG68K_FPU_Timing is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		abort_operation : in std_logic;

		family : in fpu_instruction_family_t;
		operation : in fpu_operation_t;
		operand_format : in fpu_operand_format_t;
		address_mode : in std_logic_vector(2 downto 0);
		address_register : in std_logic_vector(2 downto 0);
		control_register_mask : in std_logic_vector(2 downto 0);
		data_register_mask : in std_logic_vector(7 downto 0);
		dynamic_register_mask : in std_logic;
		condition_true : in std_logic;
		integer_register_data : in std_logic_vector(31 downto 0);
		initialized : in std_logic;
		suspended : in std_logic;
		frame_byte_count : in natural range 0 to
			FPU_STATE_FRAME_BUSY_BYTES_68882;

		core_done : in std_logic;
		core_branch_taken : in std_logic;
		core_trap_taken : in std_logic;
		core_format_error : in std_logic;
		core_exception_trap : in std_logic;
		core_exception_class : in fpu_exception_t;

		busy : out std_logic;
		done : out std_logic;
		branch_taken : out std_logic;
		trap_taken : out std_logic;
		format_error : out std_logic;
		exception_trap : out std_logic;
		exception_class : out fpu_exception_t
	);
end entity;

architecture rtl of TG68K_FPU_Timing is
	constant MAXIMUM_TIMING_CYCLES : natural := 2047;
	-- MC68882 manual tables 8-3 and 8-6 through 8-8, best-case aligned
	-- zero-wait, no-overlap profile. TG68K calculates the EA before start.

	function selected_total(
		format_value : fpu_operand_format_t;
		integer_total : natural;
		single_total : natural;
		double_total : natural;
		extended_total : natural;
		packed_total : natural) return natural is
	begin
		case format_value is
			when FPU_FORMAT_BYTE_INTEGER | FPU_FORMAT_WORD_INTEGER |
					FPU_FORMAT_LONG_INTEGER => return integer_total;
			when FPU_FORMAT_SINGLE => return single_total;
			when FPU_FORMAT_DOUBLE => return double_total;
			when FPU_FORMAT_EXTENDED => return extended_total;
			when FPU_FORMAT_PACKED | FPU_FORMAT_DYNAMIC_PACKED =>
				return packed_total;
		end case;
	end function;

	function register_operation_total(
		operation_value : fpu_operation_t) return natural is
	begin
		case operation_value is
			when FPU_OP_MOVE => return 21;
			when FPU_OP_ABS | FPU_OP_NEG | FPU_OP_CMP => return 38;
			when FPU_OP_ACOS => return 628;
			when FPU_OP_ADD | FPU_OP_SUB => return 56;
			when FPU_OP_ASIN => return 584;
			when FPU_OP_ATAN => return 406;
			when FPU_OP_ATANH => return 696;
			when FPU_OP_COS | FPU_OP_SIN => return 394;
			when FPU_OP_COSH => return 610;
			when FPU_OP_DIV => return 108;
			when FPU_OP_ETOX => return 500;
			when FPU_OP_ETOXM1 => return 548;
			when FPU_OP_GETEXP => return 48;
			when FPU_OP_GETMAN => return 34;
			when FPU_OP_INT | FPU_OP_INTRZ => return 58;
			when FPU_OP_LOGN => return 528;
			when FPU_OP_LOGNP1 => return 574;
			when FPU_OP_LOG10 | FPU_OP_LOG2 => return 584;
			when FPU_OP_MOD => return 75;
			when FPU_OP_MUL => return 76;
			when FPU_OP_REM => return 105;
			when FPU_OP_SCALE => return 46;
			when FPU_OP_SGLDIV => return 74;
			when FPU_OP_SGLMUL => return 54;
			when FPU_OP_SINCOS => return 454;
			when FPU_OP_SINH => return 690;
			when FPU_OP_SQRT => return 110;
			when FPU_OP_TAN => return 475;
			when FPU_OP_TANH => return 664;
			when FPU_OP_TENTOX | FPU_OP_TWOTOX => return 570;
			when FPU_OP_TST => return 36;
			when others => return 1;
		end case;
	end function;

	function external_operation_total(
		operation_value : fpu_operation_t;
		format_value : fpu_operand_format_t) return natural is
	begin
		case operation_value is
			when FPU_OP_MOVE =>
				return selected_total(format_value, 48, 34, 40, 46, 891);
			when FPU_OP_ABS | FPU_OP_NEG =>
				return selected_total(format_value, 68, 51, 57, 63, 893);
			when FPU_OP_ACOS =>
				return selected_total(format_value, 658, 641, 647, 653, 1483);
			when FPU_OP_ADD | FPU_OP_SUB =>
				return selected_total(format_value, 94, 69, 75, 81, 909);
			when FPU_OP_ASIN =>
				return selected_total(format_value, 614, 597, 603, 609, 1439);
			when FPU_OP_ATAN =>
				return selected_total(format_value, 436, 419, 425, 431, 1261);
			when FPU_OP_ATANH =>
				return selected_total(format_value, 725, 709, 715, 721, 1551);
			when FPU_OP_CMP =>
				return selected_total(format_value, 76, 51, 57, 63, 891);
			when FPU_OP_COS | FPU_OP_SIN =>
				return selected_total(format_value, 424, 407, 413, 419, 1249);
			when FPU_OP_COSH =>
				return selected_total(format_value, 640, 623, 629, 635, 1465);
			when FPU_OP_DIV =>
				return selected_total(format_value, 146, 121, 127, 133, 961);
			when FPU_OP_ETOX =>
				return selected_total(format_value, 530, 513, 519, 525, 1355);
			when FPU_OP_ETOXM1 =>
				return selected_total(format_value, 578, 561, 567, 573, 1403);
			when FPU_OP_GETEXP =>
				return selected_total(format_value, 78, 61, 67, 73, 903);
			when FPU_OP_GETMAN =>
				return selected_total(format_value, 64, 47, 53, 59, 889);
			when FPU_OP_INT | FPU_OP_INTRZ =>
				return selected_total(format_value, 88, 71, 77, 83, 913);
			when FPU_OP_LOGN =>
				return selected_total(format_value, 558, 541, 547, 553, 1383);
			when FPU_OP_LOGNP1 =>
				return selected_total(format_value, 604, 587, 593, 599, 1429);
			when FPU_OP_LOG10 | FPU_OP_LOG2 =>
				return selected_total(format_value, 614, 597, 603, 609, 1439);
			when FPU_OP_MOD =>
				return selected_total(format_value, 113, 88, 94, 100, 928);
			when FPU_OP_MUL =>
				return selected_total(format_value, 114, 89, 95, 101, 929);
			when FPU_OP_REM =>
				return selected_total(format_value, 143, 118, 124, 130, 958);
			when FPU_OP_SCALE =>
				return selected_total(format_value, 84, 59, 65, 71, 899);
			when FPU_OP_SGLDIV =>
				return selected_total(format_value, 112, 87, 93, 99, 927);
			when FPU_OP_SGLMUL =>
				return selected_total(format_value, 102, 77, 83, 89, 917);
			when FPU_OP_SINCOS =>
				return selected_total(format_value, 484, 467, 473, 479, 1309);
			when FPU_OP_SINH =>
				return selected_total(format_value, 720, 703, 709, 715, 1545);
			when FPU_OP_SQRT =>
				return selected_total(format_value, 140, 123, 129, 135, 965);
			when FPU_OP_TAN =>
				return selected_total(format_value, 506, 489, 495, 501, 1331);
			when FPU_OP_TANH =>
				return selected_total(format_value, 694, 677, 683, 689, 1519);
			when FPU_OP_TENTOX | FPU_OP_TWOTOX =>
				return selected_total(format_value, 600, 583, 589, 595, 1425);
			when FPU_OP_TST =>
				return selected_total(format_value, 66, 49, 55, 61, 891);
			when others => return 1;
		end case;
	end function;

	function count_bits(value : std_logic_vector) return natural is
		variable count : natural := 0;
	begin
		for index in value'range loop
			if value(index) = '1' then
				count := count + 1;
			end if;
		end loop;
		return count;
	end function;

	function timing_total(
		family_value : fpu_instruction_family_t;
		operation_value : fpu_operation_t;
		format_value : fpu_operand_format_t;
		mode_value : std_logic_vector(2 downto 0);
		register_value : std_logic_vector(2 downto 0);
		control_mask_value : std_logic_vector(2 downto 0);
		data_mask_value : std_logic_vector(7 downto 0);
		dynamic_mask_value : std_logic;
		condition_value : std_logic;
		integer_data_value : std_logic_vector(31 downto 0);
		initialized_value : std_logic;
		suspended_value : std_logic) return natural is
		variable total : natural;
		variable register_count : natural;
	begin
		case family_value is
			when FPU_FAMILY_REGISTER_OPERATION =>
				return register_operation_total(operation_value);
			when FPU_FAMILY_EXTERNAL_OPERATION =>
				total := external_operation_total(operation_value, format_value);
				if mode_value = "000" then
					return total - 5;
				end if;
				return total;
			when FPU_FAMILY_MOVE_CONSTANT => return 32;
			when FPU_FAMILY_MOVE_TO_EXTERNAL =>
				total := selected_total(format_value, 110, 38, 44, 50, 2006);
				if format_value = FPU_FORMAT_DYNAMIC_PACKED then
					total := total + 14;
				end if;
				if mode_value = "000" then
					return total - 2;
				end if;
				return total;
			when FPU_FAMILY_MOVE_TO_CONTROL =>
				register_count := count_bits(control_mask_value);
				if register_count = 1 then
					if mode_value = "000" or mode_value = "001" then
						return 28;
					elsif mode_value = "111" and register_value = "100" then
						return 32;
					else
						return 33;
					end if;
				elsif mode_value = "111" and register_value = "100" then
					return 26 + 6 * register_count;
				else
					return 27 + 6 * register_count;
				end if;
			when FPU_FAMILY_MOVE_FROM_CONTROL =>
				register_count := count_bits(control_mask_value);
				if register_count = 1 then
					if mode_value = "000" or mode_value = "001" then
						return 31;
					else
						return 33;
					end if;
				end if;
				return 27 + 6 * register_count;
			when FPU_FAMILY_MOVEM_TO_FP =>
				register_count := count_bits(data_mask_value);
				if dynamic_mask_value = '1' then
					return 49 + 31 * register_count;
				end if;
				return 35 + 31 * register_count;
			when FPU_FAMILY_MOVEM_FROM_FP =>
				register_count := count_bits(data_mask_value);
				if dynamic_mask_value = '1' then
					return 51 + 25 * register_count;
				end if;
				return 37 + 25 * register_count;
			when FPU_FAMILY_SCC =>
				if mode_value = "011" or mode_value = "100" then
					return 18;
				end if;
				return 16;
			when FPU_FAMILY_DBCC =>
				if condition_value = '1' then
					return 18;
				elsif integer_data_value(15 downto 0) = x"0000" then
					return 22;
				else
					return 18;
				end if;
			when FPU_FAMILY_TRAPCC =>
				if register_value = "100" then
					total := 16;
				elsif register_value = "010" then
					total := 18;
				else
					total := 20;
				end if;
				if condition_value = '1' then
					case register_value is
						when "100" => return 36;
						when "010" => return 38;
						when others => return 40;
					end case;
				end if;
				return total;
			when FPU_FAMILY_BCC_WORD | FPU_FAMILY_BCC_LONG =>
				if condition_value = '1' then
					return 18;
				end if;
				return 16;
			when FPU_FAMILY_SAVE =>
				if suspended_value = '1' then
					return 332;
				elsif initialized_value = '1' then
					return 98;
				end if;
				return 14;
			when FPU_FAMILY_RESTORE => return 19;
			when others => return 1;
		end case;
	end function;

	function restore_total(byte_count : natural) return natural is
	begin
		if byte_count = FPU_STATE_FRAME_BUSY_BYTES_68882 then
			return 337;
		elsif byte_count = FPU_STATE_FRAME_IDLE_BYTES_68882 then
			return 103;
		end if;
		return 19;
	end function;

	signal active : std_logic := '0';
	signal restore_active : std_logic := '0';
	signal elapsed_cycles : natural range 0 to MAXIMUM_TIMING_CYCLES := 0;
	signal target_cycles : natural range 1 to MAXIMUM_TIMING_CYCLES := 1;
	signal core_complete : std_logic := '0';
	signal branch_latched : std_logic := '0';
	signal trap_latched : std_logic := '0';
	signal format_error_latched : std_logic := '0';
	signal exception_latched : std_logic := '0';
	signal exception_class_latched : fpu_exception_t := FPU_EXCEPTION_NONE;
begin
	busy <= active;

	timing : process(clk)
		variable completed : std_logic;
		variable current_target : natural range 1 to MAXIMUM_TIMING_CYCLES;
	begin
		if rising_edge(clk) then
			done <= '0';
			branch_taken <= '0';
			trap_taken <= '0';
			format_error <= '0';
			exception_trap <= '0';
			exception_class <= FPU_EXCEPTION_NONE;
			if nReset = '0' then
				active <= '0';
				restore_active <= '0';
				elapsed_cycles <= 0;
				target_cycles <= 1;
				core_complete <= '0';
				branch_latched <= '0';
				trap_latched <= '0';
				format_error_latched <= '0';
				exception_latched <= '0';
				exception_class_latched <= FPU_EXCEPTION_NONE;
			elsif abort_operation = '1' then
				active <= '0';
				restore_active <= '0';
				elapsed_cycles <= 0;
				core_complete <= '0';
				branch_latched <= '0';
				trap_latched <= '0';
				format_error_latched <= '0';
				exception_latched <= '0';
				exception_class_latched <= FPU_EXCEPTION_NONE;
			elsif start = '1' then
				active <= '1';
				if family = FPU_FAMILY_RESTORE then
					restore_active <= '1';
				else
					restore_active <= '0';
				end if;
				elapsed_cycles <= 1;
				target_cycles <= timing_total(family, operation,
					operand_format, address_mode, address_register,
					control_register_mask, data_register_mask,
					dynamic_register_mask, condition_true,
					integer_register_data, initialized, suspended);
				core_complete <= '0';
				branch_latched <= '0';
				trap_latched <= '0';
				format_error_latched <= '0';
				exception_latched <= '0';
				exception_class_latched <= FPU_EXCEPTION_NONE;
			elsif active = '1' then
				completed := core_complete or core_done;
				current_target := target_cycles;
				if restore_active = '1' and core_done = '1' then
					current_target := restore_total(frame_byte_count);
					target_cycles <= current_target;
				end if;
				if core_branch_taken = '1' then
					branch_latched <= '1';
				end if;
				if core_trap_taken = '1' then
					trap_latched <= '1';
				end if;
				if core_format_error = '1' then
					format_error_latched <= '1';
				end if;
				if core_exception_trap = '1' then
					exception_latched <= '1';
					exception_class_latched <= core_exception_class;
				end if;
				if completed = '1' and elapsed_cycles >= current_target then
					active <= '0';
					restore_active <= '0';
					core_complete <= '0';
					done <= '1';
					branch_taken <= branch_latched or core_branch_taken;
					trap_taken <= trap_latched or core_trap_taken;
					format_error <= format_error_latched or core_format_error;
					exception_trap <= exception_latched or core_exception_trap;
					if core_exception_trap = '1' then
						exception_class <= core_exception_class;
					else
						exception_class <= exception_class_latched;
					end if;
				else
					core_complete <= completed;
					if elapsed_cycles < MAXIMUM_TIMING_CYCLES then
						elapsed_cycles <= elapsed_cycles + 1;
					end if;
				end if;
			end if;
		end if;
	end process;
end architecture;
