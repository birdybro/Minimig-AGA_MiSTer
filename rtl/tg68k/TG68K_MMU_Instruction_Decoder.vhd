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
use work.TG68K_MMU_Pack.all;

entity TG68K_MMU_Instruction_Decoder is
	port(
		opcode : in std_logic_vector(15 downto 0);
		extension_word : in std_logic_vector(15 downto 0);
		supervisor : in std_logic;

		instruction_match : out std_logic;
		instruction_valid : out std_logic;
		unimplemented_instruction : out std_logic;
		privilege_violation : out std_logic;
		operation : out mmu_instruction_operation_t;
		register_select : out mmu_register_t;
		operand_size : out mmu_operand_size_t;
		flush_disable : out std_logic;
		read_access : out std_logic;
		requires_effective_address : out std_logic;
		fc_source : out mmu_fc_source_t;
		fc_immediate : out std_logic_vector(2 downto 0);
		fc_data_register : out std_logic_vector(2 downto 0);
		fc_mask : out std_logic_vector(2 downto 0);
		ptest_level : out std_logic_vector(2 downto 0);
		ptest_return_address : out std_logic;
		ptest_address_register : out std_logic_vector(2 downto 0)
	);
end entity;

architecture rtl of TG68K_MMU_Instruction_Decoder is
	function control_alterable(
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
	decode : process(opcode, extension_word, supervisor)
		variable matched : boolean;
		variable valid : boolean;
		variable needs_ea : boolean;
		variable fc_valid : boolean;
		variable decoded_operation : mmu_instruction_operation_t;
		variable decoded_register : mmu_register_t;
		variable decoded_size : mmu_operand_size_t;
		variable decoded_fc_source : mmu_fc_source_t;
	begin
		matched := opcode(15 downto 6) = "1111000000";
		valid := false;
		needs_ea := false;
		fc_valid := false;
		decoded_operation := MMU_OP_NONE;
		decoded_register := MMU_REG_TC;
		decoded_size := MMU_SIZE_NONE;
		decoded_fc_source := MMU_FC_SOURCE_SFC;

		flush_disable <= extension_word(8);
		read_access <= extension_word(9);
		fc_immediate <= extension_word(2 downto 0);
		fc_data_register <= extension_word(2 downto 0);
		fc_mask <= extension_word(7 downto 5);
		ptest_level <= extension_word(12 downto 10);
		ptest_return_address <= extension_word(8);
		ptest_address_register <= extension_word(7 downto 5);

		case extension_word(4 downto 3) is
			when "10" =>
				fc_valid := true;
				decoded_fc_source := MMU_FC_SOURCE_IMMEDIATE;
			when "01" =>
				fc_valid := true;
				decoded_fc_source := MMU_FC_SOURCE_DATA_REGISTER;
			when "00" =>
				if extension_word(4 downto 0) = "00000" then
					fc_valid := true;
					decoded_fc_source := MMU_FC_SOURCE_SFC;
				elsif extension_word(4 downto 0) = "00001" then
					fc_valid := true;
					decoded_fc_source := MMU_FC_SOURCE_DFC;
				end if;
			when others =>
				null;
		end case;

		if matched then
			case extension_word(15 downto 13) is
				when "000" | "010" | "011" =>
					case extension_word(15 downto 10) is
						when "000010" =>
							decoded_register := MMU_REG_TT0;
							decoded_size := MMU_SIZE_LONG;
							valid := true;
						when "000011" =>
							decoded_register := MMU_REG_TT1;
							decoded_size := MMU_SIZE_LONG;
							valid := true;
						when "010000" =>
							decoded_register := MMU_REG_TC;
							decoded_size := MMU_SIZE_LONG;
							valid := true;
						when "010010" =>
							decoded_register := MMU_REG_SRP;
							decoded_size := MMU_SIZE_QUAD;
							valid := true;
						when "010011" =>
							decoded_register := MMU_REG_CRP;
							decoded_size := MMU_SIZE_QUAD;
							valid := true;
						when "011000" =>
							decoded_register := MMU_REG_MMUSR;
							decoded_size := MMU_SIZE_WORD;
							valid := true;
						when others =>
							null;
					end case;
					if valid then
						needs_ea := true;
						if extension_word(9) = '1' then
							decoded_operation := MMU_OP_PMOVE_FROM_MMU;
						else
							decoded_operation := MMU_OP_PMOVE_TO_MMU;
						end if;
						if extension_word(7 downto 0) /= x"00" or
								(extension_word(9) = '1' and extension_word(8) = '1') or
								(decoded_register = MMU_REG_MMUSR and
								 extension_word(8) = '1') then
							valid := false;
						end if;
					end if;

				when "001" =>
					case extension_word(12 downto 10) is
						when "000" =>
							decoded_operation := MMU_OP_PLOAD;
							needs_ea := true;
							valid := extension_word(8 downto 5) = "0000" and
								fc_valid;
						when "001" =>
							decoded_operation := MMU_OP_PFLUSH_ALL;
							valid := extension_word(9 downto 0) =
								"0000000000";
						when "100" =>
							decoded_operation := MMU_OP_PFLUSH_FC;
							valid := extension_word(9 downto 8) = "00" and
								fc_valid;
						when "110" =>
							decoded_operation := MMU_OP_PFLUSH_PAGE;
							needs_ea := true;
							valid := extension_word(9 downto 8) = "00" and
								fc_valid;
						when others =>
							null;
					end case;

				when "100" =>
					decoded_operation := MMU_OP_PTEST;
					needs_ea := true;
					valid := fc_valid;
					if extension_word(8) = '0' and
							extension_word(7 downto 5) /= "000" then
						valid := false;
					elsif extension_word(12 downto 10) = "000" and
							extension_word(8) = '1' then
						valid := false;
					end if;

				when others =>
					null;
			end case;

			if valid and needs_ea and not control_alterable(opcode(5 downto 0)) then
				valid := false;
			end if;
		end if;

		instruction_match <= '0';
		instruction_valid <= '0';
		unimplemented_instruction <= '0';
		privilege_violation <= '0';
		if matched then
			instruction_match <= '1';
			if valid then
				instruction_valid <= '1';
			end if;
			if supervisor = '0' then
				privilege_violation <= '1';
			elsif not valid then
				unimplemented_instruction <= '1';
			end if;
		end if;
		if needs_ea then
			requires_effective_address <= '1';
		else
			requires_effective_address <= '0';
		end if;
		operation <= decoded_operation;
		register_select <= decoded_register;
		operand_size <= decoded_size;
		fc_source <= decoded_fc_source;
	end process;
end architecture;
