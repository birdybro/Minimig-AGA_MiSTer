library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_scale is
end entity;

architecture test of tb_tg68k_fpu_scale is
	signal source : fpu_extended_t := (others => '0');
	signal destination : fpu_extended_t := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
begin
	dut : entity work.TG68K_FPU_Scale
		port map(
			source => source,
			destination => destination,
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
			constant destination_value : fpu_extended_t;
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant message_text : string) is
		begin
			source <= source_value;
			destination <= destination_value;
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
		check(x"4000B000000000000000", x"3FFFC000000000000000",
			x"4001C000000000000000", "0000", x"00",
			"FSCALE positive chopped factor mismatch");
		check(x"BFFFE000000000000000", x"4001C000000000000000",
			x"4000C000000000000000", "0000", x"00",
			"FSCALE negative chopped factor mismatch");
		check(x"3FFEC000000000000000", x"BFFF9000000000000000",
			x"BFFF9000000000000000", "1000", x"00",
			"FSCALE sub-unit factor mismatch");
		check(x"40014000000000000000", x"40016000000000000000",
			x"4002C000000000000000", "0000", x"00",
			"FSCALE unnormalized operand mismatch");
		check(x"3FFF8000000000000000", x"00008000000000000000",
			x"00018000000000000000", "0000", x"00",
			"FSCALE minimum extended exponent mismatch");

		rounding_precision <= FPU_PRECISION_SINGLE;
		check(x"00000000000000000000", x"3FFF8000008000000000",
			x"3FFF8000000000000000", "0000", x"02",
			"FSCALE zero factor post-processing mismatch");
		rounding_precision <= FPU_PRECISION_EXTENDED;

		check(x"40008000000000000000", x"80000000000000000000",
			x"80000000000000000000", "1100", x"00",
			"FSCALE signed-zero destination mismatch");
		check(x"C0008000000000000000", x"FFFF8000000000000000",
			x"FFFF8000000000000000", "1010", x"00",
			"FSCALE infinity destination mismatch");
		check(x"7FFF8000000000000000", x"3FFF8000000000000000",
			FPU_RESET_NAN, "0001", x"20",
			"FSCALE infinite source operand-error mismatch");
		check(x"7FFFC000000000000123", x"FFFFC000000000000456",
			x"FFFFC000000000000456", "1001", x"00",
			"FSCALE destination NaN priority mismatch");
		check(x"FFFF8000000000000123", x"3FFF8000000000000000",
			x"FFFFC000000000000123", "1001", x"40",
			"FSCALE signaling-NaN mismatch");

		check(x"40008000000000000000", x"7FFEFFFFFFFFFFFFFFFF",
			x"7FFF8000000000000000", "0010", x"12",
			"FSCALE overflow mismatch");
		check(x"C0008000000000000000", x"00018000000000000000",
			x"00004000000000000000", "0000", x"08",
			"FSCALE gradual underflow mismatch");
		check(x"400D8000000000000000", x"3FFF8000000000000000",
			x"7FFF8000000000000000", "0010", x"12",
			"FSCALE catastrophic overflow mismatch");
		check(x"C00D8000000000000000", x"3FFF8000000000000000",
			x"00000000000000000000", "0100", x"0A",
			"FSCALE catastrophic underflow mismatch");

		report "PASS: MC68882 FSCALE exponent adjustment" severity note;
		stop;
	end process;
end architecture;
