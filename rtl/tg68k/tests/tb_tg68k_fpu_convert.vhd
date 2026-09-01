library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_convert is
end entity;

architecture test of tb_tg68k_fpu_convert is
	signal source_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal source_data : std_logic_vector(95 downto 0) := (others => '0');
	signal extended_data : fpu_extended_t;
	signal conversion_valid : std_logic;
	signal extended_source : fpu_extended_t := (others => '0');
	signal external_extended_data : std_logic_vector(95 downto 0);
begin
	dut : entity work.TG68K_FPU_Convert
		port map(
			source_format => source_format,
			source_data => source_data,
			extended_data => extended_data,
			conversion_valid => conversion_valid,
			extended_source => extended_source,
			external_extended_data => external_extended_data
		);

	stimulus : process
		procedure check_unpack(
			constant format_value : fpu_operand_format_t;
			constant external_value : std_logic_vector(95 downto 0);
			constant expected_value : fpu_extended_t;
			constant expected_valid : std_logic := '1') is
		begin
			source_format <= format_value;
			source_data <= external_value;
			wait for 1 ns;
			assert conversion_valid = expected_valid
				report "FPU input conversion validity mismatch" severity failure;
			assert extended_data = expected_value
				report "FPU input conversion data mismatch" severity failure;
		end procedure;
	begin
		check_unpack(FPU_FORMAT_BYTE_INTEGER,
			x"000000000000000000000000", x"00000000000000000000");
		check_unpack(FPU_FORMAT_BYTE_INTEGER,
			x"000000000000000000000080", x"C0068000000000000000");
		check_unpack(FPU_FORMAT_BYTE_INTEGER,
			x"0000000000000000000000FF", x"BFFF8000000000000000");
		check_unpack(FPU_FORMAT_WORD_INTEGER,
			x"000000000000000000008000", x"C00E8000000000000000");
		check_unpack(FPU_FORMAT_LONG_INTEGER,
			x"000000000000000080000000", x"C01E8000000000000000");
		check_unpack(FPU_FORMAT_LONG_INTEGER,
			x"00000000000000007FFFFFFF", x"401DFFFFFFFE00000000");
		check_unpack(FPU_FORMAT_LONG_INTEGER,
			x"000000000000000000000003", x"4000C000000000000000");

		check_unpack(FPU_FORMAT_SINGLE,
			x"000000000000000000000000", x"00000000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"000000000000000080000000", x"80000000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"00000000000000003F800000", x"3FFF8000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"0000000000000000C0200000", x"C000A000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"000000000000000000000001", x"3F6A8000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"0000000000000000007FFFFF", x"3F80FFFFFE0000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"00000000000000007F800000", x"7FFF8000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"0000000000000000FF800000", x"FFFF8000000000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"00000000000000007FC00001", x"7FFFC000010000000000");
		check_unpack(FPU_FORMAT_SINGLE,
			x"00000000000000007F800001", x"7FFF8000010000000000");

		check_unpack(FPU_FORMAT_DOUBLE,
			x"000000003FF0000000000000", x"3FFF8000000000000000");
		check_unpack(FPU_FORMAT_DOUBLE,
			x"000000000000000000000001", x"3BCD8000000000000000");
		check_unpack(FPU_FORMAT_DOUBLE,
			x"000000007FF0000000000000", x"7FFF8000000000000000");
		check_unpack(FPU_FORMAT_DOUBLE,
			x"000000007FF8000000000001", x"7FFFC000000000000800");

		check_unpack(FPU_FORMAT_EXTENDED,
			x"3FFFDEAD8000000000000000", x"3FFF8000000000000000");
		check_unpack(FPU_FORMAT_EXTENDED,
			x"4000ABCD4000000000000000", x"3FFF8000000000000000");
		check_unpack(FPU_FORMAT_EXTENDED,
			x"0001ABCD4000000000000000", x"00008000000000000000");
		check_unpack(FPU_FORMAT_EXTENDED,
			x"0002ABCD1000000000000000", x"00004000000000000000");
		check_unpack(FPU_FORMAT_EXTENDED,
			x"C000ABCD0000000000000000", x"80000000000000000000");
		check_unpack(FPU_FORMAT_EXTENDED,
			x"7FFF12340000000000000000", x"7FFF0000000000000000");

		check_unpack(FPU_FORMAT_PACKED,
			x"000000000000000000000000", FPU_RESET_NAN, '0');
		check_unpack(FPU_FORMAT_DYNAMIC_PACKED,
			x"000000000000000000000000", FPU_RESET_NAN, '0');

		extended_source <= x"C000A000000000000000";
		wait for 1 ns;
		assert external_extended_data = x"C0000000A000000000000000"
			report "external extended memory layout mismatch" severity failure;

		report "PASS: MC68882 exact inbound binary and integer conversions"
			severity note;
		stop;
	end process;
end architecture;
