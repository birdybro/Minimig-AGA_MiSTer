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

entity TG68K_FPU_Decoder is
	port(
		opcode : in std_logic_vector(15 downto 0);
		command_word : in std_logic_vector(15 downto 0);

		instruction_match : out std_logic;
		instruction_valid : out std_logic;
		fline_exception : out std_logic;
		requires_command_word : out std_logic;
		requires_effective_address : out std_logic;
		family : out fpu_instruction_family_t;
		operation : out fpu_operation_t;
		operand_format : out fpu_operand_format_t;
		source_register : out std_logic_vector(2 downto 0);
		destination_register : out std_logic_vector(2 downto 0);
		control_register_list : out std_logic_vector(2 downto 0);
		register_list : out std_logic_vector(7 downto 0);
		conditional_predicate : out std_logic_vector(5 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Decoder is
	function standard_ea(value : std_logic_vector(5 downto 0)) return boolean is
	begin
		if value(5 downto 3) /= "111" then
			return true;
		end if;
		case value(2 downto 0) is
			when "000" | "001" | "010" | "011" | "100" =>
				return true;
			when others =>
				return false;
		end case;
	end function;

	function memory_ea(value : std_logic_vector(5 downto 0)) return boolean is
	begin
		case value(5 downto 3) is
			when "010" | "011" | "100" | "101" | "110" =>
				return true;
			when "111" =>
				case value(2 downto 0) is
					when "000" | "001" | "010" | "011" | "100" =>
						return true;
					when others =>
						return false;
				end case;
			when others =>
				return false;
		end case;
	end function;

	function data_ea(value : std_logic_vector(5 downto 0)) return boolean is
	begin
		return value(5 downto 3) = "000" or memory_ea(value);
	end function;

	function memory_alterable_ea(
		value : std_logic_vector(5 downto 0)) return boolean is
	begin
		case value(5 downto 3) is
			when "010" | "011" | "100" | "101" | "110" =>
				return true;
			when "111" =>
				return value(2 downto 0) = "000" or
					value(2 downto 0) = "001";
			when others =>
				return false;
		end case;
	end function;

	function data_alterable_ea(
		value : std_logic_vector(5 downto 0)) return boolean is
	begin
		return value(5 downto 3) = "000" or memory_alterable_ea(value);
	end function;

	function alterable_ea(value : std_logic_vector(5 downto 0)) return boolean is
	begin
		return value(5 downto 3) = "000" or value(5 downto 3) = "001" or
			memory_alterable_ea(value);
	end function;

	function control_ea(value : std_logic_vector(5 downto 0)) return boolean is
	begin
		case value(5 downto 3) is
			when "010" | "101" | "110" =>
				return true;
			when "111" =>
				return value(2 downto 0) = "000" or
					value(2 downto 0) = "001" or
					value(2 downto 0) = "010" or
					value(2 downto 0) = "011";
			when others =>
				return false;
		end case;
	end function;

	function control_alterable_ea(
		value : std_logic_vector(5 downto 0)) return boolean is
	begin
		case value(5 downto 3) is
			when "010" | "101" | "110" =>
				return true;
			when "111" =>
				return value(2 downto 0) = "000" or
					value(2 downto 0) = "001";
			when others =>
				return false;
		end case;
	end function;
begin
	decode : process(opcode, command_word)
		variable matched : boolean;
		variable valid : boolean;
		variable command_required : boolean;
		variable needs_ea : boolean;
		variable decoded_family : fpu_instruction_family_t;
		variable decoded_operation : fpu_operation_t;
		variable decoded_format : fpu_operand_format_t;
		variable ea : std_logic_vector(5 downto 0);
		variable register_select : std_logic_vector(2 downto 0);
	begin
		matched := opcode(15 downto 12) = "1111" and
			opcode(11 downto 9) = FPU_COPROCESSOR_ID;
		valid := false;
		command_required := false;
		needs_ea := false;
		decoded_family := FPU_FAMILY_NONE;
		decoded_operation := FPU_OP_UNDEFINED;
		decoded_format := fpu_decode_format(command_word(12 downto 10));
		ea := opcode(5 downto 0);
		register_select := command_word(12 downto 10);

		if matched then
			case opcode(8 downto 6) is
				when "000" =>
					command_required := true;
					case command_word(15 downto 13) is
						when "000" =>
							decoded_family := FPU_FAMILY_REGISTER_OPERATION;
							decoded_operation := fpu_decode_operation(
								command_word(6 downto 0));
							valid := fpu_operation_encoding_valid(
								command_word(6 downto 0));
						when "001" =>
							null;
						when "010" =>
							if command_word(12 downto 10) = "111" then
								decoded_family := FPU_FAMILY_MOVE_CONSTANT;
								valid := true;
							else
								decoded_family := FPU_FAMILY_EXTERNAL_OPERATION;
								decoded_operation := fpu_decode_operation(
									command_word(6 downto 0));
								needs_ea := true;
								if command_word(12 downto 10) = "000" or
										command_word(12 downto 10) = "001" or
										command_word(12 downto 10) = "100" or
										command_word(12 downto 10) = "110" then
									valid := data_ea(ea);
								else
									valid := memory_ea(ea);
								end if;
								valid := valid and fpu_operation_encoding_valid(
									command_word(6 downto 0));
							end if;
						when "011" =>
							decoded_family := FPU_FAMILY_MOVE_TO_EXTERNAL;
							needs_ea := true;
							if command_word(12 downto 10) = "000" or
									command_word(12 downto 10) = "001" or
									command_word(12 downto 10) = "100" or
									command_word(12 downto 10) = "110" then
								valid := data_alterable_ea(ea);
							else
								valid := memory_alterable_ea(ea);
							end if;
						when "100" =>
							decoded_family := FPU_FAMILY_MOVE_TO_CONTROL;
							needs_ea := true;
							if register_select = "000" or register_select = "001" then
								valid := standard_ea(ea);
							elsif register_select = "010" or register_select = "100" then
								valid := data_ea(ea);
							else
								valid := memory_ea(ea);
							end if;
						when "101" =>
							decoded_family := FPU_FAMILY_MOVE_FROM_CONTROL;
							needs_ea := true;
							if register_select = "000" or register_select = "001" then
								valid := alterable_ea(ea);
							elsif register_select = "010" or register_select = "100" then
								valid := data_alterable_ea(ea);
							else
								valid := memory_alterable_ea(ea);
							end if;
						when "110" =>
							decoded_family := FPU_FAMILY_MOVEM_TO_FP;
							needs_ea := true;
							valid := command_word(12) = '1' and
								(opcode(5 downto 3) = "011" or control_ea(ea));
						when "111" =>
							decoded_family := FPU_FAMILY_MOVEM_FROM_FP;
							needs_ea := true;
							if command_word(12) = '0' then
								valid := opcode(5 downto 3) = "100";
							else
								valid := control_alterable_ea(ea);
							end if;
						when others =>
							null;
					end case;

				when "001" =>
					command_required := true;
					case opcode(5 downto 3) is
						when "001" =>
							decoded_family := FPU_FAMILY_DBCC;
							valid := true;
						when "111" =>
							if opcode(2 downto 0) = "010" or
									opcode(2 downto 0) = "011" or
									opcode(2 downto 0) = "100" then
								decoded_family := FPU_FAMILY_TRAPCC;
								valid := true;
							end if;
						when others =>
							if data_alterable_ea(ea) then
								decoded_family := FPU_FAMILY_SCC;
								needs_ea := true;
								valid := true;
							end if;
					end case;

				when "010" =>
					decoded_family := FPU_FAMILY_BCC_WORD;
					valid := true;
				when "011" =>
					decoded_family := FPU_FAMILY_BCC_LONG;
					valid := true;
				when "100" =>
					decoded_family := FPU_FAMILY_SAVE;
					needs_ea := true;
					valid := control_alterable_ea(ea) or
						opcode(5 downto 3) = "100";
				when "101" =>
					decoded_family := FPU_FAMILY_RESTORE;
					needs_ea := true;
					valid := control_ea(ea) or opcode(5 downto 3) = "011";
				when others =>
					null;
			end case;
		end if;

		if matched then
			instruction_match <= '1';
		else
			instruction_match <= '0';
		end if;
		if valid then
			instruction_valid <= '1';
		else
			instruction_valid <= '0';
		end if;
		if matched and not valid then
			fline_exception <= '1';
		else
			fline_exception <= '0';
		end if;
		if command_required then
			requires_command_word <= '1';
		else
			requires_command_word <= '0';
		end if;
		if needs_ea then
			requires_effective_address <= '1';
		else
			requires_effective_address <= '0';
		end if;
		family <= decoded_family;
		operation <= decoded_operation;
		operand_format <= decoded_format;
		source_register <= command_word(12 downto 10);
		destination_register <= command_word(9 downto 7);
		control_register_list <= command_word(12 downto 10);
		register_list <= command_word(7 downto 0);
		if opcode(8 downto 6) = "001" then
			conditional_predicate <= command_word(5 downto 0);
		else
			conditional_predicate <= opcode(5 downto 0);
		end if;
	end process;
end architecture;
