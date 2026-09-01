library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_add_subtract is
end entity;

architecture test of tb_tg68k_fpu_add_subtract is
	signal source : fpu_extended_t := (others => '0');
	signal destination : fpu_extended_t := (others => '0');
	signal subtract : std_logic := '0';
	signal compare_only : std_logic := '0';
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
begin
	dut : entity work.TG68K_FPU_Add_Subtract
		port map(
			source => source,
			destination => destination,
			subtract => subtract,
			compare_only => compare_only,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status
		);

	stimulus : process
		procedure check(
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant message_text : string) is
		begin
			wait for 1 ns;
			assert result = expected_result and condition_codes = expected_cc and
				exception_status = expected_status
				report message_text & ": result=" & to_hstring(result) &
					" cc=" & to_hstring(condition_codes) &
					" status=" & to_hstring(exception_status)
				severity failure;
		end procedure;
	begin
		source <= x"3FFF8000000000000000";
		destination <= x"40008000000000000000";
		check(x"4000C000000000000000", "0000", x"00",
			"exact FADD result mismatch");

		subtract <= '1';
		check(x"3FFF8000000000000000", "0000", x"00",
			"exact FSUB result mismatch");

		source <= x"3FFF8000000000000000";
		destination <= x"3FFF8000000000000001";
		check(x"3FC08000000000000000", "0000", x"00",
			"FSUB cancellation normalization mismatch");

		subtract <= '0';
		rounding_precision <= FPU_PRECISION_SINGLE;
		source <= x"3FE78000000000000000";
		destination <= x"3FFF8000000000000000";
		check(x"3FFF8000000000000000", "0000", x"02",
			"single tie-to-even FADD mismatch");

		destination <= x"3FFF8000010000000000";
		check(x"3FFF8000020000000000", "0000", x"02",
			"single odd tie-to-even FADD mismatch");

		rounding_precision <= FPU_PRECISION_EXTENDED;
		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		source <= x"3FBE8000000000000000";
		destination <= x"3FFF8000000000000000";
		check(x"3FFF8000000000000001", "0000", x"02",
			"directed rounding sticky-bit mismatch");

		rounding_mode <= FPU_ROUND_NEAREST;
		source <= x"80000000000000000000";
		destination <= x"00000000000000000000";
		check(x"00000000000000000000", "0100", x"00",
			"opposite signed-zero FADD mismatch");

		rounding_mode <= FPU_ROUND_MINUS_INFINITY;
		check(x"80000000000000000000", "1100", x"00",
			"round-minus opposite signed-zero FADD mismatch");

		rounding_mode <= FPU_ROUND_NEAREST;
		source <= x"80000000000000000000";
		destination <= x"80000000000000000000";
		check(x"80000000000000000000", "1100", x"00",
			"negative-zero FADD mismatch");

		rounding_precision <= FPU_PRECISION_SINGLE;
		source <= x"407EFFFFFF0000000000";
		destination <= x"407EFFFFFF0000000000";
		check(x"7FFF8000000000000000", "0010", x"12",
			"single-precision FADD overflow mismatch");

		subtract <= '1';
		source <= x"3F80FFFFFE0000000000";
		destination <= x"3F818000000000000000";
		check(x"3F6A8000000000000000", "0000", x"08",
			"single-precision exact underflow mismatch");

		rounding_precision <= FPU_PRECISION_EXTENDED;
		subtract <= '0';
		source <= x"FFFF8000000000000123";
		destination <= x"7FFFC000000000004567";
		check(x"7FFFC000000000004567", "0001", x"40",
			"destination NaN propagation mismatch");

		source <= x"FFFFC000000000000123";
		destination <= x"3FFF8000000000000000";
		check(x"FFFFC000000000000123", "1001", x"00",
			"source quiet-NaN propagation mismatch");

		source <= x"FFFF8000000000000123";
		check(x"FFFFC000000000000123", "1001", x"40",
			"source signaling-NaN quieting mismatch");

		source <= x"FFFF8000000000000000";
		destination <= x"7FFF8000000000000000";
		check(FPU_RESET_NAN, "0001", x"20",
			"opposite-infinity FADD operand error mismatch");

		subtract <= '1';
		source <= x"7FFF8000000000000000";
		destination <= x"7FFF8000000000000000";
		check(FPU_RESET_NAN, "0001", x"20",
			"like-infinity FSUB operand error mismatch");

		compare_only <= '1';
		subtract <= '0';
		source <= x"40008000000000000000";
		destination <= x"4000C000000000000000";
		check(x"3FFF8000000000000000", "0000", x"00",
			"FCMP greater-than mismatch");

		source <= x"C0008000000000000000";
		destination <= x"C000C000000000000000";
		check(x"BFFF8000000000000000", "1000", x"00",
			"FCMP negative less-than mismatch");

		source <= x"7FFF8000000000000000";
		destination <= x"7FFF8000000000000000";
		check(x"00000000000000000000", "0100", x"00",
			"FCMP equal infinity mismatch");

		source <= x"FFFF8000000000000000";
		destination <= x"7FFF8000000000000000";
		check(x"3FFF8000000000000000", "0000", x"00",
			"FCMP opposite infinity mismatch");

		source <= x"FFFFC000000000000123";
		destination <= x"3FFF8000000000000000";
		check(x"FFFFC000000000000123", "1001", x"00",
			"FCMP quiet-NaN unordered mismatch");

		source <= x"7FFF8000000000000123";
		check(x"7FFFC000000000000123", "0001", x"40",
			"FCMP signaling-NaN mismatch");

		report "PASS: MC68882 FADD, FSUB, and FCMP arithmetic datapath"
			severity note;
		stop;
	end process;
end architecture;
