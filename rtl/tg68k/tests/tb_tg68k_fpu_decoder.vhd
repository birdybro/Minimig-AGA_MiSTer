library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_decoder is
end entity;

architecture test of tb_tg68k_fpu_decoder is
	signal opcode : std_logic_vector(15 downto 0) := (others => '0');
	signal command_word : std_logic_vector(15 downto 0) := (others => '0');
	signal instruction_match : std_logic;
	signal instruction_valid : std_logic;
	signal fline_exception : std_logic;
	signal requires_command_word : std_logic;
	signal requires_effective_address : std_logic;
	signal family : fpu_instruction_family_t;
	signal operation : fpu_operation_t;
	signal operand_format : fpu_operand_format_t;
	signal source_register : std_logic_vector(2 downto 0);
	signal destination_register : std_logic_vector(2 downto 0);
	signal control_register_list : std_logic_vector(2 downto 0);
	signal register_list : std_logic_vector(7 downto 0);
	signal conditional_predicate : std_logic_vector(5 downto 0);
begin
	dut : entity work.TG68K_FPU_Decoder
		port map(
			opcode => opcode,
			command_word => command_word,
			instruction_match => instruction_match,
			instruction_valid => instruction_valid,
			fline_exception => fline_exception,
			requires_command_word => requires_command_word,
			requires_effective_address => requires_effective_address,
			family => family,
			operation => operation,
			operand_format => operand_format,
			source_register => source_register,
			destination_register => destination_register,
			control_register_list => control_register_list,
			register_list => register_list,
			conditional_predicate => conditional_predicate
		);

	stimulus : process
		procedure check_decode(
			constant test_opcode : std_logic_vector(15 downto 0);
			constant test_command : std_logic_vector(15 downto 0);
			constant expected_match : std_logic;
			constant expected_valid : std_logic;
			constant expected_command : std_logic;
			constant expected_ea : std_logic;
			constant expected_family : fpu_instruction_family_t) is
		begin
			opcode <= test_opcode;
			command_word <= test_command;
			wait for 1 ns;
			assert instruction_match = expected_match
				report "FPU match classification mismatch" severity failure;
			assert instruction_valid = expected_valid
				report "FPU validity classification mismatch" severity failure;
			assert requires_command_word = expected_command
				report "FPU command-word classification mismatch" severity failure;
			assert requires_effective_address = expected_ea
				report "FPU effective-address classification mismatch" severity failure;
			assert family = expected_family
				report "FPU instruction-family classification mismatch" severity failure;
			assert fline_exception = (expected_match and not expected_valid)
				report "F-line exception classification mismatch" severity failure;
		end procedure;

		variable arithmetic_command : std_logic_vector(15 downto 0);
	begin
		check_decode(x"4E71", x"0000", '0', '0', '0', '0',
			FPU_FAMILY_NONE);
		check_decode(x"F000", x"0000", '0', '0', '0', '0',
			FPU_FAMILY_NONE);

		for extension in 0 to 127 loop
			arithmetic_command := (others => '0');
			arithmetic_command(6 downto 0) :=
				std_logic_vector(to_unsigned(extension, 7));
			opcode <= x"F200";
			command_word <= arithmetic_command;
			wait for 1 ns;
			assert instruction_valid = not arithmetic_command(6)
				report "arithmetic extension validity mismatch" severity failure;
			assert family = FPU_FAMILY_REGISTER_OPERATION
				report "register arithmetic family mismatch" severity failure;
		end loop;
		assert fpu_decode_operation("0110000") = FPU_OP_SINCOS and
			fpu_decode_operation("0110111") = FPU_OP_SINCOS and
			fpu_decode_operation("0100010") = FPU_OP_ADD and
			fpu_decode_operation("0000101") = FPU_OP_RESERVED_ALIAS and
			fpu_decode_operation("1000000") = FPU_OP_UNDEFINED
			report "arithmetic operation mapping mismatch" severity failure;

		check_decode(x"F200", x"4000", '1', '1', '1', '1',
			FPU_FAMILY_EXTERNAL_OPERATION);
		assert operand_format = FPU_FORMAT_LONG_INTEGER
			report "external long format was not decoded" severity failure;
		check_decode(x"F208", x"4800", '1', '0', '1', '1',
			FPU_FAMILY_EXTERNAL_OPERATION);
		check_decode(x"F23C", x"4800", '1', '1', '1', '1',
			FPU_FAMILY_EXTERNAL_OPERATION);
		assert operand_format = FPU_FORMAT_EXTENDED
			report "external extended format was not decoded" severity failure;
		check_decode(x"F23F", x"5C7F", '1', '1', '1', '0',
			FPU_FAMILY_MOVE_CONSTANT);

		check_decode(x"F200", x"6400", '1', '1', '1', '1',
			FPU_FAMILY_MOVE_TO_EXTERNAL);
		check_decode(x"F200", x"6800", '1', '0', '1', '1',
			FPU_FAMILY_MOVE_TO_EXTERNAL);
		check_decode(x"F220", x"6800", '1', '1', '1', '1',
			FPU_FAMILY_MOVE_TO_EXTERNAL);

		check_decode(x"F208", x"8000", '1', '0', '1', '1',
			FPU_FAMILY_MOVE_TO_CONTROL);
		check_decode(x"F200", x"9000", '1', '1', '1', '1',
			FPU_FAMILY_MOVE_TO_CONTROL);
		check_decode(x"F208", x"8800", '1', '0', '1', '1',
			FPU_FAMILY_MOVE_TO_CONTROL);
		check_decode(x"F208", x"A400", '1', '1', '1', '1',
			FPU_FAMILY_MOVE_FROM_CONTROL);
		check_decode(x"F200", x"9001", '1', '0', '1', '1',
			FPU_FAMILY_MOVE_TO_CONTROL);

		check_decode(x"F218", x"D0A5", '1', '1', '1', '1',
			FPU_FAMILY_MOVEM_TO_FP);
		assert register_list = x"A5"
			report "FMOVEM register list mismatch" severity failure;
		check_decode(x"F218", x"C000", '1', '0', '1', '1',
			FPU_FAMILY_MOVEM_TO_FP);
		check_decode(x"F218", x"C810", '1', '0', '1', '1',
			FPU_FAMILY_MOVEM_TO_FP);
		check_decode(x"F220", x"E000", '1', '1', '1', '1',
			FPU_FAMILY_MOVEM_FROM_FP);
		check_decode(x"F238", x"E000", '1', '0', '1', '1',
			FPU_FAMILY_MOVEM_FROM_FP);
		check_decode(x"F238", x"F000", '1', '1', '1', '1',
			FPU_FAMILY_MOVEM_FROM_FP);
		check_decode(x"F218", x"D830", '1', '1', '1', '1',
			FPU_FAMILY_MOVEM_TO_FP);
		check_decode(x"F218", x"D831", '1', '0', '1', '1',
			FPU_FAMILY_MOVEM_TO_FP);
		check_decode(x"F218", x"D100", '1', '0', '1', '1',
			FPU_FAMILY_MOVEM_TO_FP);

		check_decode(x"F240", x"001F", '1', '1', '1', '1',
			FPU_FAMILY_SCC);
		assert conditional_predicate = "011111"
			report "FScc predicate mismatch" severity failure;
		check_decode(x"F248", x"0001", '1', '1', '1', '0',
			FPU_FAMILY_DBCC);
		check_decode(x"F278", x"0000", '1', '0', '1', '0',
			FPU_FAMILY_NONE);
		check_decode(x"F27A", x"0002", '1', '1', '1', '0',
			FPU_FAMILY_TRAPCC);

		check_decode(x"F280", x"0000", '1', '1', '0', '0',
			FPU_FAMILY_BCC_WORD);
		check_decode(x"F2FF", x"0000", '1', '1', '0', '0',
			FPU_FAMILY_BCC_LONG);
		assert conditional_predicate = "111111"
			report "FBcc predicate mismatch" severity failure;
		check_decode(x"F320", x"0000", '1', '1', '0', '1',
			FPU_FAMILY_SAVE);
		check_decode(x"F318", x"0000", '1', '0', '0', '1',
			FPU_FAMILY_SAVE);
		check_decode(x"F358", x"0000", '1', '1', '0', '1',
			FPU_FAMILY_RESTORE);
		check_decode(x"F37A", x"0000", '1', '1', '0', '1',
			FPU_FAMILY_RESTORE);
		check_decode(x"F380", x"0000", '1', '0', '0', '0',
			FPU_FAMILY_NONE);

		report "PASS: MC68882 F-line instruction decoder" severity note;
		stop;
	end process;
end architecture;
