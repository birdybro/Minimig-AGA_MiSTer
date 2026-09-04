library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_remainder is
end entity;

architecture test of tb_tg68k_fpu_remainder is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal ieee_remainder : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal destination : fpu_extended_t := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal quotient : std_logic_vector(7 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
	signal digit_start : std_logic;
	signal digit_initial_mode : fpu_divide_initial_t;
	signal digit_divisor : unsigned(64 downto 0);
	signal digit_dividend : unsigned(64 downto 0);
	signal digit_forced_subtrahend : unsigned(64 downto 0);
	signal digit_iterations : natural range 0 to 65535;
	signal digit_nearest_adjust : std_logic;
	signal digit_remainder : unsigned(64 downto 0);
	signal digit_quotient : unsigned(65 downto 0);
	signal digit_sign_invert : std_logic;
	signal digit_done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Remainder
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			ieee_remainder => ieee_remainder,
			source => source,
			destination => destination,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			reduction_start => digit_start,
			reduction_initial_mode => digit_initial_mode,
			reduction_divisor => digit_divisor,
			reduction_dividend => digit_dividend,
			reduction_forced_subtrahend => digit_forced_subtrahend,
			reduction_iterations => digit_iterations,
			reduction_nearest_adjust => digit_nearest_adjust,
			reduction_remainder => digit_remainder,
			reduction_quotient => digit_quotient,
			reduction_sign_invert => digit_sign_invert,
			reduction_done => digit_done,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			quotient => quotient,
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
			initial_mode => digit_initial_mode,
			divisor => digit_divisor,
			dividend => digit_dividend,
			forced_subtrahend => digit_forced_subtrahend,
			iterations => digit_iterations,
			nearest_adjust => digit_nearest_adjust,
			divisor_result => open,
			remainder_result => digit_remainder,
			quotient_result => digit_quotient,
			exponent_decrement => open,
			sign_invert => digit_sign_invert,
			busy => open,
			done => digit_done
		);

	stimulus : process
		procedure check(
			constant operation_is_remainder : std_logic;
			constant source_value : fpu_extended_t;
			constant destination_value : fpu_extended_t;
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant expected_quotient : std_logic_vector(7 downto 0);
			constant message_text : string) is
			variable cycle_count : natural := 0;
		begin
			wait until falling_edge(clk);
			ieee_remainder <= operation_is_remainder;
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
				assert cycle_count < 65536
					report message_text & ": operation did not complete"
					severity failure;
			end loop;
			assert busy = '1' and result = expected_result and
				condition_codes = expected_cc and
				exception_status = expected_status and
				quotient = expected_quotient
				report message_text & ": result=" & to_hstring(result) &
					" cc=" & to_hstring(condition_codes) &
					" status=" & to_hstring(exception_status) &
					" quotient=" & to_hstring(quotient)
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

		check('0', x"40008000000000000000", x"4001E000000000000000",
			x"3FFF8000000000000000", "0000", x"00", x"03",
			"FMOD positive quotient mismatch");
		check('1', x"40008000000000000000", x"4001E000000000000000",
			x"BFFF8000000000000000", "1000", x"00", x"04",
			"FREM nearest-even increment mismatch");
		check('1', x"40018000000000000000", x"4001C000000000000000",
			x"C0008000000000000000", "1000", x"00", x"02",
			"FREM odd tie quotient mismatch");
		check('1', x"40008000000000000000", x"4001A000000000000000",
			x"3FFF8000000000000000", "0000", x"00", x"02",
			"FREM even tie quotient mismatch");
		check('1', x"40018000000000000000", x"4000C000000000000000",
			x"BFFF8000000000000000", "1000", x"00", x"01",
			"FREM sub-unit quotient mismatch");
		check('0', x"40008000000000000000", x"C001E000000000000000",
			x"BFFF8000000000000000", "1000", x"00", x"83",
			"FMOD negative dividend mismatch");
		check('1', x"40008000000000000000", x"C001E000000000000000",
			x"3FFF8000000000000000", "0000", x"00", x"84",
			"FREM negative dividend mismatch");
		check('1', x"C0008000000000000000", x"4001E000000000000000",
			x"BFFF8000000000000000", "1000", x"00", x"84",
			"FREM negative divisor mismatch");
		check('1', x"40008000000000000000", x"C0028000000000000000",
			x"80000000000000000000", "1100", x"00", x"84",
			"FREM signed exact zero mismatch");
		check('0', x"40018000000000000000", x"3FFF8000000000000000",
			x"3FFF8000000000000000", "0000", x"00", x"00",
			"FMOD zero quotient mismatch");
		check('0', x"4000C000000000000000", x"40818000000000000000",
			x"3FFF8000000000000000", "0000", x"00", x"55",
			"FMOD wide quotient reduction mismatch");
		check('0', x"40014000000000000000", x"40027000000000000000",
			x"3FFF8000000000000000", "0000", x"00", x"03",
			"FMOD unnormalized operand mismatch");
		check('0', x"00000000000000000002", x"00000000000000000003",
			x"00000000000000000001", "0000", x"08", x"01",
			"FMOD denormal operand mismatch");

		rounding_precision <= FPU_PRECISION_SINGLE;
		check('0', x"40008000000000000000", x"3FFF8000008000000000",
			x"3FFF8000000000000000", "0000", x"02", x"00",
			"FMOD final precision rounding mismatch");
		rounding_precision <= FPU_PRECISION_EXTENDED;

		check('0', x"7FFF8000000000000000", x"BFFFC000000000000000",
			x"BFFFC000000000000000", "1000", x"00", x"80",
			"FMOD infinite modulus mismatch");
		check('0', x"00000000000000000000", x"3FFF8000000000000000",
			FPU_RESET_NAN, "0001", x"20", x"00",
			"FMOD zero modulus mismatch");
		check('1', x"40008000000000000000", x"7FFF8000000000000000",
			FPU_RESET_NAN, "0001", x"20", x"00",
			"FREM infinite dividend mismatch");
		check('0', x"7FFFC000000000000123", x"FFFFC000000000000456",
			x"FFFFC000000000000456", "1001", x"00", x"80",
			"FMOD destination NaN priority mismatch");
		check('1', x"FFFF8000000000000123", x"3FFF8000000000000000",
			x"FFFFC000000000000123", "1001", x"40", x"80",
			"FREM signaling NaN mismatch");

		report "PASS: MC68882 FMOD and FREM exact remainder reduction"
			severity note;
		stop;
	end process;
end architecture;
