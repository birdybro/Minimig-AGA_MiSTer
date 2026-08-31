library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_instruction_decoder is
end entity;

architecture test of tb_tg68k_mmu_instruction_decoder is
	signal opcode : std_logic_vector(15 downto 0) := x"F010";
	signal extension_word : std_logic_vector(15 downto 0) := (others => '0');
	signal supervisor : std_logic := '1';
	signal instruction_match : std_logic;
	signal instruction_valid : std_logic;
	signal unimplemented_instruction : std_logic;
	signal privilege_violation : std_logic;
	signal operation : mmu_instruction_operation_t;
	signal register_select : mmu_register_t;
	signal operand_size : mmu_operand_size_t;
	signal flush_disable : std_logic;
	signal read_access : std_logic;
	signal requires_effective_address : std_logic;
	signal fc_source : mmu_fc_source_t;
	signal fc_immediate : std_logic_vector(2 downto 0);
	signal fc_data_register : std_logic_vector(2 downto 0);
	signal fc_mask : std_logic_vector(2 downto 0);
	signal ptest_level : std_logic_vector(2 downto 0);
	signal ptest_return_address : std_logic;
	signal ptest_address_register : std_logic_vector(2 downto 0);

	function valid_fc(value : std_logic_vector(4 downto 0)) return boolean is
	begin
		return value(4 downto 3) = "10" or value(4 downto 3) = "01" or
			value = "00000" or value = "00001";
	end function;

	function expected_valid(value : std_logic_vector(15 downto 0)) return boolean is
		variable pmove_register_valid : boolean;
	begin
		pmove_register_valid := value(15 downto 10) = "000010" or
			value(15 downto 10) = "000011" or
			value(15 downto 10) = "010000" or
			value(15 downto 10) = "010010" or
			value(15 downto 10) = "010011" or
			value(15 downto 10) = "011000";
		if pmove_register_valid then
			return value(7 downto 0) = x"00" and
				not (value(9) = '1' and value(8) = '1') and
				not (value(15 downto 10) = "011000" and value(8) = '1');
		elsif value(15 downto 13) = "001" then
			case value(12 downto 10) is
				when "000" =>
					return value(8 downto 5) = "0000" and
						valid_fc(value(4 downto 0));
				when "001" =>
					return value(9 downto 0) = "0000000000";
				when "100" | "110" =>
					return value(9 downto 8) = "00" and
						valid_fc(value(4 downto 0));
				when others =>
					return false;
			end case;
		elsif value(15 downto 13) = "100" then
			return valid_fc(value(4 downto 0)) and
				(value(8) = '1' or value(7 downto 5) = "000") and
				not (value(12 downto 10) = "000" and value(8) = '1');
		end if;
		return false;
	end function;
begin
	dut : entity work.TG68K_MMU_Instruction_Decoder
		port map(
			opcode => opcode,
			extension_word => extension_word,
			supervisor => supervisor,
			instruction_match => instruction_match,
			instruction_valid => instruction_valid,
			unimplemented_instruction => unimplemented_instruction,
			privilege_violation => privilege_violation,
			operation => operation,
			register_select => register_select,
			operand_size => operand_size,
			flush_disable => flush_disable,
			read_access => read_access,
			requires_effective_address => requires_effective_address,
			fc_source => fc_source,
			fc_immediate => fc_immediate,
			fc_data_register => fc_data_register,
			fc_mask => fc_mask,
			ptest_level => ptest_level,
			ptest_return_address => ptest_return_address,
			ptest_address_register => ptest_address_register
		);

	stimulus : process
		variable value : std_logic_vector(15 downto 0);
		variable valid_count : natural := 0;
		variable invalid_ea_valid_count : natural := 0;
	begin
		for number in 0 to 65535 loop
			value := std_logic_vector(to_unsigned(number, 16));
			extension_word <= value;
			wait for 1 ns;
			if expected_valid(value) then
				assert instruction_valid = '1'
					report "valid extension word rejected at " & integer'image(number)
					severity failure;
			else
				assert instruction_valid = '0'
					report "reserved extension word accepted at " & integer'image(number)
					severity failure;
			end if;
			if instruction_valid = '1' then
				valid_count := valid_count + 1;
				assert operation /= MMU_OP_NONE
					report "valid command decoded without an operation" severity failure;
			else
				assert unimplemented_instruction = '1'
					report "reserved command did not request F-line exception"
					severity failure;
			end if;
		end loop;
		assert valid_count = 2646
			report "wrong number of valid extension words" severity failure;

		opcode <= x"F000";
		extension_word <= x"4000";
		wait for 1 ns;
		assert operation = MMU_OP_PMOVE_TO_MMU and
			register_select = MMU_REG_TC and operand_size = MMU_SIZE_LONG and
			requires_effective_address = '1'
			report "PMOVE TC decode failed" severity failure;
		extension_word <= x"4300";
		wait for 1 ns;
		assert instruction_valid = '0'
			report "PMOVE read accepted FD=1" severity failure;
		extension_word <= x"4800";
		wait for 1 ns;
		assert register_select = MMU_REG_SRP and operand_size = MMU_SIZE_QUAD
			report "PMOVE SRP decode failed" severity failure;
		extension_word <= x"4C00";
		wait for 1 ns;
		assert register_select = MMU_REG_CRP and operand_size = MMU_SIZE_QUAD
			report "PMOVE CRP decode failed" severity failure;
		extension_word <= x"0800";
		wait for 1 ns;
		assert register_select = MMU_REG_TT0 and operand_size = MMU_SIZE_LONG
			report "PMOVE TT0 decode failed" severity failure;
		extension_word <= x"0C00";
		wait for 1 ns;
		assert register_select = MMU_REG_TT1 and operand_size = MMU_SIZE_LONG
			report "PMOVE TT1 decode failed" severity failure;
		extension_word <= x"6000";
		wait for 1 ns;
		assert register_select = MMU_REG_MMUSR and operand_size = MMU_SIZE_WORD
			report "PMOVE MMUSR decode failed" severity failure;

		opcode <= x"F010";
		extension_word <= x"2215";
		wait for 1 ns;
		assert operation = MMU_OP_PLOAD and read_access = '1' and
			fc_source = MMU_FC_SOURCE_IMMEDIATE and fc_immediate = "101"
			report "PLOAD immediate FC decode failed" severity failure;
		extension_word <= x"220B";
		wait for 1 ns;
		assert fc_source = MMU_FC_SOURCE_DATA_REGISTER and
			fc_data_register = "011"
			report "PLOAD data-register FC decode failed" severity failure;
		extension_word <= x"2200";
		wait for 1 ns;
		assert fc_source = MMU_FC_SOURCE_SFC
			report "PLOAD SFC decode failed" severity failure;
		extension_word <= x"2201";
		wait for 1 ns;
		assert fc_source = MMU_FC_SOURCE_DFC
			report "PLOAD DFC decode failed" severity failure;

		extension_word <= x"2400";
		wait for 1 ns;
		assert operation = MMU_OP_PFLUSH_ALL and
			requires_effective_address = '0'
			report "PFLUSHA decode failed" severity failure;
		extension_word <= x"30B2";
		wait for 1 ns;
		assert operation = MMU_OP_PFLUSH_FC and fc_mask = "101" and
			fc_immediate = "010" and requires_effective_address = '0'
			report "PFLUSH FC decode failed" severity failure;
		extension_word <= x"38B2";
		wait for 1 ns;
		assert operation = MMU_OP_PFLUSH_PAGE and
			requires_effective_address = '1'
			report "PFLUSH page decode failed" severity failure;

		extension_word <= x"93D5";
		wait for 1 ns;
		assert operation = MMU_OP_PTEST and ptest_level = "100" and
			ptest_return_address = '1' and ptest_address_register = "110" and
			read_access = '1'
			report "PTEST decode failed" severity failure;
		extension_word <= x"8315";
		wait for 1 ns;
		assert instruction_valid = '0'
			report "level-zero PTEST accepted address-register return"
			severity failure;

		opcode <= x"F008";
		for number in 0 to 65535 loop
			extension_word <= std_logic_vector(to_unsigned(number, 16));
			wait for 1 ns;
			if instruction_valid = '1' then
				invalid_ea_valid_count := invalid_ea_valid_count + 1;
			end if;
		end loop;
		assert invalid_ea_valid_count = 145
			report "invalid EA accepted by an address-bearing command"
			severity failure;

		opcode <= x"F010";
		extension_word <= x"2400";
		supervisor <= '0';
		wait for 1 ns;
		assert privilege_violation = '1' and instruction_valid = '1'
			report "user-mode PMMU command did not request privilege exception"
			severity failure;
		opcode <= x"F210";
		wait for 1 ns;
		assert instruction_match = '0' and instruction_valid = '0' and
			unimplemented_instruction = '0' and privilege_violation = '0'
			report "non-PMMU coprocessor opcode matched" severity failure;

		report "tb_tg68k_mmu_instruction_decoder PASS" severity note;
		wait;
	end process;
end architecture;
