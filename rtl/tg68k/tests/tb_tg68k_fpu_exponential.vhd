library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_exponential is
end entity;

architecture test of tb_tg68k_fpu_exponential is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal exponential_base : fpu_exponential_base_t := FPU_EXP_BASE_TWO;
	signal subtract_one : std_logic := '0';
	signal hyperbolic_sine : std_logic := '0';
	signal hyperbolic_cosine : std_logic := '0';
	signal hyperbolic_tangent : std_logic := '0';
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

	dut : entity work.TG68K_FPU_Exponential_With_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			exponential_base => exponential_base,
			subtract_one => subtract_one,
			hyperbolic_sine => hyperbolic_sine,
			hyperbolic_cosine => hyperbolic_cosine,
			hyperbolic_tangent => hyperbolic_tangent,
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
		procedure execute(
			constant source_value : fpu_extended_t;
			constant precision_value : fpu_rounding_precision_t;
			constant mode_value : fpu_rounding_mode_t;
			constant expected_result : fpu_extended_t;
			constant expected_status : std_logic_vector(7 downto 0);
			constant expected_iterations : natural;
			constant base_value : fpu_exponential_base_t :=
				FPU_EXP_BASE_TWO;
			constant subtract_one_value : std_logic := '0';
			constant hyperbolic_sine_value : std_logic := '0';
			constant hyperbolic_cosine_value : std_logic := '0';
			constant hyperbolic_tangent_value : std_logic := '0') is
			variable iteration_count : natural := 0;
		begin
			wait until falling_edge(clk);
			source <= source_value;
			exponential_base <= base_value;
			subtract_one <= subtract_one_value;
			hyperbolic_sine <= hyperbolic_sine_value;
			hyperbolic_cosine <= hyperbolic_cosine_value;
			hyperbolic_tangent <= hyperbolic_tangent_value;
			rounding_precision <= precision_value;
			rounding_mode <= mode_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				iteration_count := iteration_count + 1;
				assert iteration_count < 520
					report "exponential operation did not complete" severity failure;
			end loop;
			assert iteration_count = expected_iterations
				report "exponential iteration count mismatch: " &
					integer'image(iteration_count)
				severity failure;
			assert result = expected_result and
				condition_codes = fpu_condition_codes(expected_result) and
				exception_status = expected_status
				report "exponential result mismatch: got " & to_hstring(result) &
					" status=" & to_hstring(exception_status)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "exponential engine did not return idle" severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		execute(x"00000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF8000000000000000", x"00", 0);
		execute(x"80000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF8000000000000000", x"00", 0);
		execute(x"7FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"00", 0);
		execute(x"FFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"00", 0);
		execute(x"7FFFC123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFC123456789ABCDEF", x"00", 0);
		execute(x"7FFFA123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFE123456789ABCDEF", x"40", 0);

		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"40008000000000000000", x"02", 0);
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFE8000000000000000", x"02", 0);
		execute(x"3FFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFB504F333F9DE6484", x"02", 296);
		execute(x"BFFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"3FFEB504F333F9DE6485", x"02", 296);
		execute(x"4000D000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"40029837F0518DB8A96F", x"02", 296);
		execute(x"3FFF4000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFB504F333F9DE6484", x"02", 296);

		execute(x"3FFE8000000000000000", FPU_PRECISION_DOUBLE,
			FPU_ROUND_ZERO, x"3FFFB504F333F9DE6000", x"02", 296);
		execute(x"3FFE8000000000000000", FPU_PRECISION_SINGLE,
			FPU_ROUND_PLUS_INFINITY, x"3FFFB504F40000000000", x"02", 296);

		execute(x"3F9B8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"3FFF8000000000000001", x"02", 0);
		execute(x"BF9B8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_ZERO, x"3FFEFFFFFFFFFFFFFFFF", x"02", 0);

		execute(x"400D8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"12", 0);
		execute(x"400D8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_ZERO, x"7FFEFFFFFFFFFFFFFFFF", x"12", 0);
		execute(x"C00D807E000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"0A", 0);
		execute(x"C00D807E000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"00000000000000000001", x"0A", 0);

		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"4000ADF85458A2BB4A9B", x"02", 408,
			FPU_EXP_BASE_E);
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFDBC5AB1B16779BE35", x"02", 408,
			FPU_EXP_BASE_E);
		execute(x"3FFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFD3094C70F034DE4C", x"02", 408,
			FPU_EXP_BASE_E);
		execute(x"4000D000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"4003CE529DBC088A578B", x"02", 408,
			FPU_EXP_BASE_E);
		execute(x"400D8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"12", 0,
			FPU_EXP_BASE_E);
		execute(x"C00D807E000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"0A", 0,
			FPU_EXP_BASE_E);

		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"4002A000000000000000", x"02", 408,
			FPU_EXP_BASE_TEN);
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFBCCCCCCCCCCCCCCCD", x"02", 408,
			FPU_EXP_BASE_TEN);
		execute(x"3FFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"4000CA62C1D6D2DA9490", x"02", 408,
			FPU_EXP_BASE_TEN);
		execute(x"4000D000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"4009DE48F0ED526B1EDF", x"02", 408,
			FPU_EXP_BASE_TEN);
		execute(x"400C8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"12", 0,
			FPU_EXP_BASE_TEN);
		execute(x"C00C8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"0A", 0,
			FPU_EXP_BASE_TEN);

		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFDBF0A8B145769535", x"02", 411,
			FPU_EXP_BASE_E, '1');
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFFEA1D2A7274C4320E5", x"02", 412,
			FPU_EXP_BASE_E, '1');
		execute(x"00000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"80000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"80000000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"7FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"FFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"3FE38000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FE38000000400000015", x"02", 209,
			FPU_EXP_BASE_E, '1');
		execute(x"BFE38000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFE2FFFFFFF80000002B", x"02", 209,
			FPU_EXP_BASE_E, '1');
		execute(x"3FD78000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FD78000000000400000", x"02", 65,
			FPU_EXP_BASE_E, '1');
		execute(x"BFD78000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFD6FFFFFFFFFF800000", x"02", 65,
			FPU_EXP_BASE_E, '1');
		execute(x"3F9B8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3F9B8000000000000000", x"02", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"3F9B8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"3F9B8000000000000001", x"02", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"BF9B8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_ZERO, x"BF9AFFFFFFFFFFFFFFFF", x"02", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"BF9B8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_MINUS_INFINITY, x"BF9B8000000000000000", x"02", 0,
			FPU_EXP_BASE_E, '1');
		execute(x"C00E8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFFF8000000000000000", x"02", 0,
			FPU_EXP_BASE_E, '1');

		execute(x"00000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"80000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"80000000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"7FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"FFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"FFFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"7FFFC123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFC123456789ABCDEF", x"00", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"7FFFA123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFE123456789ABCDEF", x"40", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF966CFE2275CC12D4", x"02", 412,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFFF966CFE2275CC12D4", x"02", 412,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"3FFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFE8566807F31DCB652", x"02", 410,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"3FFFC000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"400088461D55EB530366", x"02", 414,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"3FDE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"3FDE8000000000000001", x"02", 0,
			FPU_EXP_BASE_E, '0', '1');
		execute(x"BFDE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_ZERO, x"BFDE8000000000000000", x"02", 0,
			FPU_EXP_BASE_E, '0', '1');

		execute(x"00000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"80000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"7FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"FFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"7FFFC123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFC123456789ABCDEF", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"7FFFA123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFE123456789ABCDEF", x"40", 0,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFC583AA8ECFAA8261", x"02", 412,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFC583AA8ECFAA8261", x"02", 412,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"3FFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF90560C3157468323", x"02", 410,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"3FFFC000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"4000968DE10F11011218", x"02", 414,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"3FE58000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF8000000000000400", x"02", 64,
			FPU_EXP_BASE_E, '0', '0', '1');
		execute(x"3FDD8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"3FFF8000000000000001", x"02", 0,
			FPU_EXP_BASE_E, '0', '0', '1');

		execute(x"00000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"00000000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"80000000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"80000000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"7FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"FFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFFF8000000000000000", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"7FFFC123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFC123456789ABCDEF", x"00", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"7FFFA123456789ABCDEF", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFE123456789ABCDEF", x"40", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"3FFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFEC2F7D5A8A79CA2AC", x"02", 478,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"BFFF8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"BFFEC2F7D5A8A79CA2AC", x"02", 478,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"3FFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFDEC9A9EBAB4579B29", x"02", 477,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"3FFFC000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFEE7B7CBC36FABBB07", x"02", 480,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"3FE58000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FE4FFFFFFFFFFFFFAAB", x"02", 209,
			FPU_EXP_BASE_E, '0', '0', '0', '1');
		execute(x"3FDE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_ZERO, x"3FDDFFFFFFFFFFFFFFFF", x"02", 0,
			FPU_EXP_BASE_E, '0', '0', '0', '1');

		report "PASS: MC68882 exponential and hyperbolic operations"
			severity note;
		stop;
	end process;
end architecture;
