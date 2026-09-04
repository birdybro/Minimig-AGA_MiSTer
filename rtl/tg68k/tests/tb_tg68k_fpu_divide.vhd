library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_divide is
end entity;

architecture test of tb_tg68k_fpu_divide is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal destination : fpu_extended_t := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal single_precision_operation : std_logic := '0';
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
	signal digit_start : std_logic;
	signal digit_divisor : unsigned(64 downto 0);
	signal digit_dividend : unsigned(64 downto 0);
	signal digit_remainder : unsigned(64 downto 0);
	signal digit_quotient : unsigned(65 downto 0);
	signal digit_exponent_decrement : std_logic;
	signal digit_done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Divide
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			destination => destination,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			single_precision_operation => single_precision_operation,
			divide_start => digit_start,
			divide_divisor => digit_divisor,
			divide_dividend => digit_dividend,
			divide_remainder => digit_remainder,
			divide_quotient => digit_quotient,
			divide_exponent_decrement => digit_exponent_decrement,
			divide_done => digit_done,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			busy => busy,
			done => done,
			round_input => open,
			base_exception_status => open
		);

	digit_engine : entity work.TG68K_FPU_Divide_Engine
		port map(
			clk => clk,
			nReset => nReset,
			start => digit_start,
			initial_mode => FPU_DIVIDE_FRACTION,
			divisor => digit_divisor,
			dividend => digit_dividend,
			forced_subtrahend => (others => '0'),
			iterations => 65,
			nearest_adjust => '0',
			divisor_result => open,
			remainder_result => digit_remainder,
			quotient_result => digit_quotient,
			exponent_decrement => digit_exponent_decrement,
			sign_invert => open,
			busy => open,
			done => digit_done
		);

	stimulus : process
		procedure check(
			constant source_value : fpu_extended_t;
			constant destination_value : fpu_extended_t;
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant expected_cycles : natural;
			constant message_text : string) is
			variable cycle_count : natural := 0;
		begin
			wait until falling_edge(clk);
			source <= source_value;
			destination <= destination_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 70
					report message_text & ": divider did not complete"
					severity failure;
			end loop;
			assert result = expected_result and
				condition_codes = expected_cc and
				exception_status = expected_status and
				cycle_count = expected_cycles and busy = '1'
				report message_text & ": result=" & to_hstring(result) &
					" cc=" & to_hstring(condition_codes) &
					" status=" & to_hstring(exception_status) &
					" cycles=" & integer'image(cycle_count)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report message_text & ": divider did not return idle"
				severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		check(x"40008000000000000000", x"4001C000000000000000",
			x"4000C000000000000000", "0000", x"00", 65,
			"exact FDIV mismatch");
		check(x"C0008000000000000000", x"4001C000000000000000",
			x"C000C000000000000000", "1000", x"00", 65,
			"negative FDIV mismatch");

		check(x"4000C000000000000000", x"3FFF8000000000000000",
			x"3FFDAAAAAAAAAAAAAAAB", "0000", x"02", 65,
			"extended FDIV rounding mismatch");
		rounding_mode <= FPU_ROUND_ZERO;
		check(x"4000C000000000000000", x"3FFF8000000000000000",
			x"3FFDAAAAAAAAAAAAAAAA", "0000", x"02", 65,
			"directed FDIV rounding mismatch");

		rounding_mode <= FPU_ROUND_NEAREST;
		rounding_precision <= FPU_PRECISION_SINGLE;
		check(x"4000C000000000000000", x"3FFF8000000000000000",
			x"3FFDAAAAAB0000000000", "0000", x"02", 65,
			"single-precision FDIV rounding mismatch");
		check(x"3FFE8000000000000000", x"407EFFFFFF0000000000",
			x"7FFF8000000000000000", "0010", x"12", 65,
			"single-precision FDIV overflow mismatch");

		single_precision_operation <= '1';
		rounding_precision <= FPU_PRECISION_DOUBLE;
		check(x"3FFF8000000000000001", x"3FFF8000000000000001",
			x"3FFF8000000000000000", "0000", x"00", 65,
			"FSGLDIV operand truncation mismatch");
		check(x"4000C000000000000000", x"3FFF8000000000000000",
			x"3FFDAAAAAB0000000000", "0000", x"02", 65,
			"FSGLDIV result rounding mismatch");
		check(x"3FFF8000000000000000", x"3F378000000000000000",
			x"3F378000000000000000", "0000", x"00", 65,
			"FSGLDIV extended exponent range mismatch");
		check(x"40008000000000000000", x"00008000000000000000",
			x"00004000000000000000", "0000", x"08", 65,
			"FSGLDIV extended underflow boundary mismatch");
		rounding_mode <= FPU_ROUND_ZERO;
		check(x"3FFE8000000000000000", x"7FFE8000000000000000",
			x"7FFEFFFFFFFFFFFFFFFF", "0000", x"12", 65,
			"FSGLDIV extended overflow boundary mismatch");

		single_precision_operation <= '0';
		rounding_mode <= FPU_ROUND_NEAREST;
		rounding_precision <= FPU_PRECISION_EXTENDED;
		check(x"00018000000000000000", x"00008000000000000000",
			x"3FFE8000000000000000", "0000", x"00", 65,
			"extended minimum-exponent FDIV mismatch");
		check(x"00000000000000000001", x"00000000000000000001",
			x"3FFF8000000000000000", "0000", x"00", 65,
			"extended-denormal FDIV normalization mismatch");
		check(x"40018000000000000000", x"00000000000000000001",
			x"00000000000000000000", "0100", x"0A", 65,
			"extended-denormal FDIV underflow mismatch");

		check(x"80000000000000000000", x"C000C000000000000000",
			x"7FFF8000000000000000", "0010", x"04", 0,
			"divide-by-zero mismatch");
		check(x"00000000000000000000", x"00000000000000000000",
			FPU_RESET_NAN, "0001", x"20", 0,
			"zero-divided-by-zero mismatch");
		check(x"FFFF8000000000000000", x"7FFF8000000000000000",
			FPU_RESET_NAN, "0001", x"20", 0,
			"infinity-divided-by-infinity mismatch");
		check(x"FFFF8000000000000000", x"C000C000000000000000",
			x"00000000000000000000", "0100", x"00", 0,
			"finite-divided-by-infinity mismatch");
		check(x"C0008000000000000000", x"FFFF8000000000000000",
			x"7FFF8000000000000000", "0010", x"00", 0,
			"infinity-divided-by-finite mismatch");

		check(x"FFFF8000000000000123", x"7FFFC000000000004567",
			x"7FFFC000000000004567", "0001", x"40", 0,
			"FDIV destination NaN propagation mismatch");
		check(x"FFFFC000000000000123", x"3FFF8000000000000000",
			x"FFFFC000000000000123", "1001", x"00", 0,
			"FDIV source NaN propagation mismatch");

		report "PASS: MC68882 FDIV arithmetic datapath" severity note;
		stop;
	end process;
end architecture;
