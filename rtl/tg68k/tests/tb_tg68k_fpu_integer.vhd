library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_integer is
end entity;

architecture test of tb_tg68k_fpu_integer is
	signal source : fpu_extended_t := (others => '0');
	signal force_round_zero : std_logic := '0';
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
begin
	dut : entity work.TG68K_FPU_Integer
		port map(
			source => source,
			force_round_zero => force_round_zero,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			round_input => open,
			base_exception_status => open
		);

	stimulus : process
		procedure check(
			constant source_value : fpu_extended_t;
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant message_text : string) is
		begin
			source <= source_value;
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
		check(x"3FFFC000000000000000", x"40008000000000000000",
			"0000", x"02", "FINT positive nearest tie mismatch");
		check(x"BFFFC000000000000000", x"C0008000000000000000",
			"1000", x"02", "FINT negative nearest tie mismatch");
		check(x"4000A000000000000000", x"40008000000000000000",
			"0000", x"02", "FINT nearest-even mismatch");
		check(x"3FFE8000000000000000", x"00000000000000000000",
			"0100", x"02", "FINT half-to-even zero mismatch");
		check(x"3FFE8000000000000001", x"3FFF8000000000000000",
			"0000", x"02", "FINT above-half mismatch");

		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		check(x"4000A000000000000000", x"4000C000000000000000",
			"0000", x"02", "FINT round-plus mismatch");
		check(x"BFFD8000000000000000", x"80000000000000000000",
			"1100", x"02", "FINT negative round-plus zero mismatch");

		rounding_mode <= FPU_ROUND_MINUS_INFINITY;
		check(x"C000A000000000000000", x"C000C000000000000000",
			"1000", x"02", "FINT round-minus mismatch");
		check(x"3FFD8000000000000000", x"00000000000000000000",
			"0100", x"02", "FINT positive round-minus zero mismatch");

		rounding_mode <= FPU_ROUND_NEAREST;
		check(x"40068900000000000000", x"40068900000000000000",
			"0000", x"00", "FINT exact integer mismatch");
		check(x"00000000000000000001", x"00000000000000000000",
			"0100", x"02", "FINT denormal mismatch");
		check(x"3FFF4000000000000000", x"00000000000000000000",
			"0100", x"02", "FINT unnormalized operand mismatch");
		check(x"80000000000000000000", x"80000000000000000000",
			"1100", x"00", "FINT signed zero mismatch");
		check(x"FFFF8000000000000000", x"FFFF8000000000000000",
			"1010", x"00", "FINT infinity mismatch");
		check(x"7FFFC000000000000456", x"7FFFC000000000000456",
			"0001", x"00", "FINT quiet-NaN mismatch");
		check(x"FFFF8000000000000123", x"FFFFC000000000000123",
			"1001", x"40", "FINT signaling-NaN mismatch");

		force_round_zero <= '1';
		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		check(x"3FFFF333333333333333", x"3FFF8000000000000000",
			"0000", x"02", "FINTRZ forced positive truncation mismatch");
		check(x"BFFFF333333333333333", x"BFFF8000000000000000",
			"1000", x"02", "FINTRZ forced negative truncation mismatch");

		force_round_zero <= '0';
		rounding_precision <= FPU_PRECISION_SINGLE;
		rounding_mode <= FPU_ROUND_NEAREST;
		check(x"40178000008000000000", x"40178000000000000000",
			"0000", x"02", "FINT final single-precision rounding mismatch");
		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		check(x"40178000008000000000", x"40178000010000000000",
			"0000", x"02", "FINT directed final precision mismatch");
		force_round_zero <= '1';
		check(x"40178000008000000000", x"40178000000000000000",
			"0000", x"02", "FINTRZ final precision mode mismatch");

		report "PASS: MC68882 FINT and FINTRZ integral rounding" severity note;
		stop;
	end process;
end architecture;
