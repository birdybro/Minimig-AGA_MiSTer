library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_extract is
end entity;

architecture test of tb_tg68k_fpu_extract is
	signal source : fpu_extended_t := (others => '0');
	signal get_exponent : std_logic := '0';
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
begin
	dut : entity work.TG68K_FPU_Extract
		port map(
			source => source,
			get_exponent => get_exponent,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status
		);

	stimulus : process
		procedure check(
			constant source_value : fpu_extended_t;
			constant exponent_select : std_logic;
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant message_text : string) is
		begin
			source <= source_value;
			get_exponent <= exponent_select;
			wait for 1 ns;
			assert result = expected_result and
				condition_codes = expected_cc and
				exception_status = expected_status
				report message_text & ": result=" & to_hstring(result) &
					" cc=" & to_hstring(condition_codes) &
					" status=" & to_hstring(exception_status)
				severity failure;
		end procedure;
	begin
		check(x"3FFF8000000000000000", '1', x"00000000000000000000",
			"0100", x"00", "FGETEXP exponent-zero mismatch");
		check(x"40008000000000000000", '1', x"3FFF8000000000000000",
			"0000", x"00", "FGETEXP positive exponent mismatch");
		check(x"3FFE8000000000000000", '1', x"BFFF8000000000000000",
			"1000", x"00", "FGETEXP negative exponent mismatch");
		check(x"C001C000000000000000", '1', x"40008000000000000000",
			"0000", x"00", "FGETEXP ignored source sign mismatch");
		check(x"00000000000000000001", '1', x"C00D807A000000000000",
			"1000", x"00", "FGETEXP denormal mismatch");
		check(x"00008000000000000000", '1', x"C00CFFF8000000000000",
			"1000", x"00", "FGETEXP minimum normal exponent mismatch");
		check(x"40004000000000000000", '1', x"00000000000000000000",
			"0100", x"00", "FGETEXP unnormalized operand mismatch");
		check(x"80000000000000000000", '1', x"80000000000000000000",
			"1100", x"00", "FGETEXP signed zero mismatch");
		check(x"7FFF8000000000000000", '1', FPU_RESET_NAN,
			"0001", x"20", "FGETEXP infinity mismatch");
		check(x"FFFF8000000000000123", '1', x"FFFFC000000000000123",
			"1001", x"40", "FGETEXP signaling-NaN mismatch");

		check(x"4001C000000000000000", '0', x"3FFFC000000000000000",
			"0000", x"00", "FGETMAN positive mismatch");
		check(x"C001C000000000000000", '0', x"BFFFC000000000000000",
			"1000", x"00", "FGETMAN negative mismatch");
		check(x"00000000000000000001", '0', x"3FFF8000000000000000",
			"0000", x"00", "FGETMAN denormal mismatch");
		check(x"40004000000000000000", '0', x"3FFF8000000000000000",
			"0000", x"00", "FGETMAN unnormalized mismatch");
		check(x"80000000000000000000", '0', x"80000000000000000000",
			"1100", x"00", "FGETMAN signed zero mismatch");
		check(x"FFFF8000000000000000", '0', FPU_RESET_NAN,
			"0001", x"20", "FGETMAN infinity mismatch");
		check(x"FFFFC000000000000123", '0', x"FFFFC000000000000123",
			"1001", x"00", "FGETMAN quiet-NaN mismatch");

		report "PASS: MC68882 FGETEXP and FGETMAN extraction" severity note;
		stop;
	end process;
end architecture;
