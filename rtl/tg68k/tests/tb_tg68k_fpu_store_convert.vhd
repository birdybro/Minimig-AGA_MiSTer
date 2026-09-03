library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_store_convert is
end entity;

architecture test of tb_tg68k_fpu_store_convert is
	signal source : fpu_extended_t := (others => '0');
	signal destination_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal destination_data : std_logic_vector(95 downto 0);
	signal conversion_valid : std_logic;
	signal exception_status : std_logic_vector(7 downto 0);
	signal external_destination_data : std_logic_vector(95 downto 0);
	signal external_conversion_valid : std_logic;
	signal external_exception_status : std_logic_vector(7 downto 0);
begin
	dut : entity work.TG68K_FPU_Store_Convert
		port map(
			source => source,
			destination_format => destination_format,
			rounding_mode => rounding_mode,
			destination_data => destination_data,
			conversion_valid => conversion_valid,
			exception_status => exception_status,
			round_input => open,
			rounding_precision_out => open
		);

	external_round_dut : entity work.TG68K_FPU_Store_Convert
		generic map(
			INCLUDE_ROUNDING_STAGE => false
		)
		port map(
			source => source,
			destination_format => destination_format,
			rounding_mode => rounding_mode,
			external_rounded_result => source,
			destination_data => external_destination_data,
			conversion_valid => external_conversion_valid,
			exception_status => external_exception_status,
			round_input => open,
			rounding_precision_out => open
		);

	stimulus : process
		procedure check_store(
			constant source_value : fpu_extended_t;
			constant format_value : fpu_operand_format_t;
			constant mode_value : fpu_rounding_mode_t;
			constant expected_data : std_logic_vector(95 downto 0);
			constant expected_status : std_logic_vector(7 downto 0) := x"00";
			constant expected_valid : std_logic := '1') is
		begin
			source <= source_value;
			destination_format <= format_value;
			rounding_mode <= mode_value;
			wait for 1 ns;
			assert conversion_valid = expected_valid
				report "FPU store conversion validity mismatch" severity failure;
			assert destination_data = expected_data
				report "FPU store conversion data mismatch" severity failure;
			assert exception_status = expected_status
				report "FPU store conversion exception mismatch" severity failure;
		end procedure;

		procedure check_deep_underflow(
			constant source_value : fpu_extended_t;
			constant format_value : fpu_operand_format_t) is
		begin
			source <= source_value;
			destination_format <= format_value;
			wait for 1 ns;
			assert external_conversion_valid = '1' and
				external_destination_data = x"000000000000000000000000" and
				external_exception_status = x"00"
				report "FPU store saturated shift mismatch" severity failure;
		end procedure;
	begin
		check_store(x"3FFF8000000000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"00000000000000003F800000");
		check_store(x"3FFF8000008000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"00000000000000003F800000", x"02");
		check_store(x"3FFF8000008000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_PLUS_INFINITY, x"00000000000000003F800001", x"02");
		check_store(x"BFFF8000008000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_MINUS_INFINITY, x"0000000000000000BF800001", x"02");
		check_store(x"3F818000000000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"000000000000000000800000", x"08");
		check_store(x"3F6A8000000000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"000000000000000000000001", x"08");
		check_store(x"3F698000000000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"000000000000000000000000", x"0A");
		check_store(x"407F8000000000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"00000000000000007F800000", x"12");
		check_store(x"407F8000000000000000", FPU_FORMAT_SINGLE,
			FPU_ROUND_ZERO, x"00000000000000007F7FFFFF", x"12");
		check_store(x"7FFF8000000000000000", FPU_FORMAT_DOUBLE,
			FPU_ROUND_NEAREST, x"000000007FF0000000000000");
		check_store(x"7FFF8000000000000001", FPU_FORMAT_DOUBLE,
			FPU_ROUND_NEAREST, x"000000007FF8000000000000", x"40");
		check_store(x"7FFFC123456789ABCDEF", FPU_FORMAT_SINGLE,
			FPU_ROUND_NEAREST, x"00000000000000007FC12345");
		check_store(x"3BCD8000000000000000", FPU_FORMAT_DOUBLE,
			FPU_ROUND_NEAREST, x"000000000000000000000001", x"08");
		check_store(x"3BCC8000000000000000", FPU_FORMAT_DOUBLE,
			FPU_ROUND_NEAREST, x"000000000000000000000000", x"0A");
		check_store(x"00000000000000000001", FPU_FORMAT_EXTENDED,
			FPU_ROUND_NEAREST, x"000000000000000000000001", x"08");
		check_store(x"00008000000000000000", FPU_FORMAT_EXTENDED,
			FPU_ROUND_NEAREST, x"000000008000000000000000");
		check_store(x"C000A000000000000000", FPU_FORMAT_EXTENDED,
			FPU_ROUND_NEAREST, x"C0000000A000000000000000");

		check_store(x"3FFFC000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000000002", x"02");
		check_store(x"3FFFC000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_ZERO, x"000000000000000000000001", x"02");
		check_store(x"4000A000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000000002", x"02");
		check_store(x"3FFE8000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000000000", x"02");
		check_store(x"3FFE8000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_PLUS_INFINITY, x"000000000000000000000001", x"02");
		check_store(x"BFFEC000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_MINUS_INFINITY, x"0000000000000000000000FF", x"02");
		check_store(x"BFFE8000000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000000000", x"02");
		check_store(x"4005FE00000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"00000000000000000000007F");
		check_store(x"4005FF00000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"00000000000000000000007F", x"22");
		check_store(x"C0068080000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000000080", x"02");
		check_store(x"C0068080000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_MINUS_INFINITY, x"000000000000000000000080", x"22");
		check_store(x"C0068100000000000000", FPU_FORMAT_BYTE_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000000080", x"20");
		check_store(x"C01E8000000000000000", FPU_FORMAT_LONG_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000080000000");
		check_store(x"401E8000000000000000", FPU_FORMAT_LONG_INTEGER,
			FPU_ROUND_NEAREST, x"00000000000000007FFFFFFF", x"20");
		check_store(x"401F8000000000000000", FPU_FORMAT_LONG_INTEGER,
			FPU_ROUND_NEAREST, x"00000000000000007FFFFFFF", x"20");
		check_store(x"C01F8000000000000000", FPU_FORMAT_LONG_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000080000000", x"20");
		check_store(x"7FFF8000000000000000", FPU_FORMAT_WORD_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000007FFF", x"20");
		check_store(x"FFFF8000000000000000", FPU_FORMAT_WORD_INTEGER,
			FPU_ROUND_NEAREST, x"000000000000000000008000", x"20");
		check_store(x"7FFFC123456789ABCDEF", FPU_FORMAT_LONG_INTEGER,
			FPU_ROUND_NEAREST, x"0000000000000000C1234567", x"20");
		check_store(x"7FFF8123456789ABCDEF", FPU_FORMAT_WORD_INTEGER,
			FPU_ROUND_NEAREST, x"00000000000000000000C123", x"40");

		check_deep_underflow(x"3F428000000000000000", FPU_FORMAT_SINGLE);
		check_deep_underflow(x"3F418000000000000000", FPU_FORMAT_SINGLE);
		check_deep_underflow(x"3BC28000000000000000", FPU_FORMAT_DOUBLE);
		check_deep_underflow(x"3BC18000000000000000", FPU_FORMAT_DOUBLE);

		check_store(x"00000000000000000000", FPU_FORMAT_PACKED,
			FPU_ROUND_NEAREST, (others => '0'), x"00", '0');
		check_store(x"00000000000000000000", FPU_FORMAT_DYNAMIC_PACKED,
			FPU_ROUND_NEAREST, (others => '0'), x"00", '0');

		report "PASS: MC68882 outbound binary and integer conversions"
			severity note;
		stop;
	end process;
end architecture;
