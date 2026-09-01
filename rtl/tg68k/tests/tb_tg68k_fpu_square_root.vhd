library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_square_root is
end entity;

architecture test of tb_tg68k_fpu_square_root is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Square_Root
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			busy => busy,
			done => done,
			round_input => open,
			base_exception_status => open
		);

	stimulus : process
		procedure check(
			constant source_value : fpu_extended_t;
			constant expected_result : fpu_extended_t;
			constant expected_cc : std_logic_vector(3 downto 0);
			constant expected_status : std_logic_vector(7 downto 0);
			constant expected_cycles : natural;
			constant message_text : string) is
			variable cycle_count : natural := 0;
		begin
			wait until falling_edge(clk);
			source <= source_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 70
					report message_text & ": square root did not complete"
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
				report message_text & ": square root did not return idle"
				severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		check(x"40018000000000000000", x"40008000000000000000",
			"0000", x"00", 66, "exact FSQRT mismatch");
		check(x"40008000000000000000", x"3FFFB504F333F9DE6484",
			"0000", x"02", 66, "extended FSQRT rounding mismatch");

		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		check(x"40008000000000000000", x"3FFFB504F333F9DE6485",
			"0000", x"02", 66, "directed FSQRT rounding mismatch");

		rounding_mode <= FPU_ROUND_NEAREST;
		rounding_precision <= FPU_PRECISION_SINGLE;
		check(x"40008000000000000000", x"3FFFB504F30000000000",
			"0000", x"02", 66, "single-precision FSQRT mismatch");

		rounding_precision <= FPU_PRECISION_DOUBLE;
		check(x"40008000000000000000", x"3FFFB504F333F9DE6800",
			"0000", x"02", 66, "double-precision FSQRT mismatch");

		rounding_precision <= FPU_PRECISION_EXTENDED;
		check(x"00002000000000000000", x"1FFF8000000000000000",
			"0000", x"00", 66, "denormal exact FSQRT mismatch");

		check(x"00000000000000000000", x"00000000000000000000",
			"0100", x"00", 0, "positive-zero FSQRT mismatch");
		check(x"80000000000000000000", x"80000000000000000000",
			"1100", x"00", 0, "negative-zero FSQRT mismatch");
		check(x"3FFF0000000000000000", x"00000000000000000000",
			"0100", x"00", 0, "unnormalized-zero FSQRT mismatch");
		check(x"7FFF8000000000000000", x"7FFF8000000000000000",
			"0010", x"00", 0, "positive-infinity FSQRT mismatch");
		check(x"FFFF8000000000000000", FPU_RESET_NAN,
			"0001", x"20", 0, "negative-infinity FSQRT mismatch");
		check(x"C0018000000000000000", FPU_RESET_NAN,
			"0001", x"20", 0, "negative FSQRT mismatch");
		check(x"FFFFC000000000000123", x"FFFFC000000000000123",
			"1001", x"00", 0, "quiet-NaN FSQRT mismatch");
		check(x"FFFF8000000000000123", x"FFFFC000000000000123",
			"1001", x"40", 0, "signaling-NaN FSQRT mismatch");

		report "PASS: MC68882 FSQRT arithmetic datapath" severity note;
		stop;
	end process;
end architecture;
