library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_multiply is
end entity;

architecture test of tb_tg68k_fpu_multiply is
	signal source : fpu_extended_t := (others => '0');
	signal destination : fpu_extended_t := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal single_precision_operation : std_logic := '0';
	signal shared_product_request : std_logic := '0';
	signal shared_product_left : unsigned(63 downto 0) := (others => '0');
	signal shared_product_right : unsigned(63 downto 0) := (others => '0');
	signal shared_product_result : unsigned(127 downto 0);
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
begin
	dut : entity work.TG68K_FPU_Multiply
		port map(
			source => source,
			destination => destination,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			single_precision_operation => single_precision_operation,
			shared_product_request => shared_product_request,
			shared_product_left => shared_product_left,
			shared_product_right => shared_product_right,
			shared_product_result => shared_product_result,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			round_input => open,
			base_exception_status => open
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
		source <= x"40008000000000000000";
		destination <= x"3FFFC000000000000000";
		check(x"4000C000000000000000", "0000", x"00",
			"exact FMUL result mismatch");

		source <= x"C0008000000000000000";
		destination <= x"4000C000000000000000";
		check(x"C001C000000000000000", "1000", x"00",
			"negative FMUL result mismatch");

		source <= x"3FFF8000000000000001";
		destination <= x"3FFF8000000000000001";
		check(x"3FFF8000000000000002", "0000", x"02",
			"extended FMUL rounding mismatch");

		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		check(x"3FFF8000000000000003", "0000", x"02",
			"directed FMUL rounding mismatch");

		rounding_mode <= FPU_ROUND_NEAREST;
		rounding_precision <= FPU_PRECISION_SINGLE;
		source <= x"3FFF8000010000000000";
		destination <= x"3FFF8000010000000000";
		check(x"3FFF8000020000000000", "0000", x"02",
			"single-precision FMUL rounding mismatch");

		source <= x"40008000000000000000";
		destination <= x"407EFFFFFF0000000000";
		check(x"7FFF8000000000000000", "0010", x"12",
			"single-precision FMUL overflow mismatch");

		single_precision_operation <= '1';
		rounding_precision <= FPU_PRECISION_DOUBLE;
		source <= x"3FFF8000000000000001";
		destination <= x"3FFF8000000000000001";
		check(x"3FFF8000000000000000", "0000", x"00",
			"FSGLMUL operand truncation mismatch");

		source <= x"3FFF8000010000000000";
		destination <= x"3FFF8000010000000000";
		check(x"3FFF8000020000000000", "0000", x"02",
			"FSGLMUL result rounding mismatch");

		source <= x"40638000000000000000";
		destination <= x"40638000000000000000";
		check(x"40C78000000000000000", "0000", x"00",
			"FSGLMUL extended exponent range mismatch");

		source <= x"00008000000000000000";
		destination <= x"3FFE8000000000000000";
		check(x"00004000000000000000", "0000", x"08",
			"FSGLMUL extended underflow boundary mismatch");

		rounding_mode <= FPU_ROUND_ZERO;
		source <= x"7FFE8000000000000000";
		destination <= x"40008000000000000000";
		check(x"7FFEFFFFFFFFFFFFFFFF", "0000", x"12",
			"FSGLMUL extended overflow boundary mismatch");

		single_precision_operation <= '0';
		rounding_mode <= FPU_ROUND_NEAREST;
		rounding_precision <= FPU_PRECISION_EXTENDED;
		source <= x"00008000000000000000";
		destination <= x"7FFE8000000000000000";
		check(x"3FFF8000000000000000", "0000", x"00",
			"extended minimum-exponent FMUL mismatch");

		source <= x"80000000000000000000";
		destination <= x"4000C000000000000000";
		check(x"80000000000000000000", "1100", x"00",
			"signed-zero FMUL mismatch");

		source <= x"FFFF8000000000000000";
		destination <= x"C0008000000000000000";
		check(x"7FFF8000000000000000", "0010", x"00",
			"signed-infinity FMUL mismatch");

		source <= x"00000000000000000000";
		destination <= x"FFFF8000000000000000";
		check(FPU_RESET_NAN, "0001", x"20",
			"zero-times-infinity operand error mismatch");

		source <= x"FFFF8000000000000123";
		destination <= x"7FFFC000000000004567";
		check(x"7FFFC000000000004567", "0001", x"40",
			"FMUL destination NaN propagation mismatch");

		source <= x"FFFFC000000000000123";
		destination <= x"3FFF8000000000000000";
		check(x"FFFFC000000000000123", "1001", x"00",
			"FMUL source NaN propagation mismatch");

		shared_product_left <= x"FEDCBA9876543210";
		shared_product_right <= x"0123456789ABCDEF";
		shared_product_request <= '1';
		wait for 1 ns;
		assert shared_product_result =
			unsigned'(x"FEDCBA9876543210") * unsigned'(x"0123456789ABCDEF")
			report "shared raw multiplier result mismatch" severity failure;
		shared_product_request <= '0';
		source <= x"40008000000000000000";
		destination <= x"3FFFC000000000000000";
		check(x"4000C000000000000000", "0000", x"00",
			"FMUL result did not recover after shared product");

		report "PASS: MC68882 FMUL arithmetic datapath" severity note;
		stop;
	end process;
end architecture;
