library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_divide_engine is
end entity;

architecture test of tb_tg68k_fpu_divide_engine is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal initial_mode : fpu_divide_initial_t := FPU_DIVIDE_BYPASS;
	signal divisor : unsigned(64 downto 0) := (others => '0');
	signal dividend : unsigned(64 downto 0) := (others => '0');
	signal forced_subtrahend : unsigned(64 downto 0) := (others => '0');
	signal iterations : natural range 0 to 65535 := 0;
	signal nearest_adjust : std_logic := '0';
	signal divisor_result : unsigned(64 downto 0);
	signal remainder_result : unsigned(64 downto 0);
	signal quotient_result : unsigned(65 downto 0);
	signal exponent_decrement : std_logic;
	signal sign_invert : std_logic;
	signal busy : std_logic;
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Divide_Engine
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			initial_mode => initial_mode,
			divisor => divisor,
			dividend => dividend,
			forced_subtrahend => forced_subtrahend,
			iterations => iterations,
			nearest_adjust => nearest_adjust,
			divisor_result => divisor_result,
			remainder_result => remainder_result,
			quotient_result => quotient_result,
			exponent_decrement => exponent_decrement,
			sign_invert => sign_invert,
			busy => busy,
			done => done
		);

	stimulus : process
		procedure check(
			constant mode_value : fpu_divide_initial_t;
			constant divisor_value : natural;
			constant dividend_value : natural;
			constant forced_value : natural;
			constant iteration_value : natural;
			constant nearest_value : std_logic;
			constant expected_remainder : natural;
			constant expected_quotient : natural;
			constant expected_decrement : std_logic;
			constant expected_invert : std_logic;
			constant expected_cycles : natural;
			constant message_text : string) is
			variable cycle_count : natural := 0;
		begin
			wait until falling_edge(clk);
			initial_mode <= mode_value;
			divisor <= to_unsigned(divisor_value, divisor'length);
			dividend <= to_unsigned(dividend_value, dividend'length);
			forced_subtrahend <= to_unsigned(forced_value,
				forced_subtrahend'length);
			iterations <= iteration_value;
			nearest_adjust <= nearest_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 20
					report message_text & ": engine did not complete"
					severity failure;
			end loop;
			assert busy = '1' and divisor_result = divisor_value and
				remainder_result = expected_remainder and
				quotient_result = expected_quotient and
				exponent_decrement = expected_decrement and
				sign_invert = expected_invert and
				cycle_count = expected_cycles
				report message_text & ": remainder=" &
					integer'image(to_integer(remainder_result)) &
					" quotient=" & integer'image(to_integer(quotient_result)) &
					" cycles=" & integer'image(cycle_count)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report message_text & ": completion did not retire"
				severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		check(FPU_DIVIDE_FRACTION, 12, 9, 0, 4, '0', 0, 24,
			'1', '0', 3, "fractional normalization mismatch");
		check(FPU_DIVIDE_FRACTION, 8, 12, 0, 3, '0', 0, 12,
			'0', '0', 2, "fractional direct quotient mismatch");
		check(FPU_DIVIDE_REDUCTION, 10, 15, 0, 2, '0', 0, 6,
			'0', '0', 2, "reduction recurrence mismatch");
		check(FPU_DIVIDE_REDUCTION, 10, 15, 0, 0, '1', 5, 2,
			'0', '1', 0, "nearest odd tie mismatch");
		check(FPU_DIVIDE_REDUCTION, 16, 10, 0, 2, '1', 8, 2,
			'0', '0', 2, "nearest even tie mismatch");
		check(FPU_DIVIDE_SUBTRACT, 16, 32, 19, 0, '0', 13, 1,
			'0', '0', 0, "forced subtraction mismatch");
		check(FPU_DIVIDE_BYPASS, 16, 7, 0, 0, '0', 7, 0,
			'0', '0', 0, "bypass mismatch");

		report "PASS: shared divide and remainder digit engine" severity note;
		stop;
	end process;
end architecture;
