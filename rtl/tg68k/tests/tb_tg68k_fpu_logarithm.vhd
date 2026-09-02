library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_logarithm is
end entity;

architecture test of tb_tg68k_fpu_logarithm is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal add_one : std_logic := '1';
	signal logarithm_base : fpu_logarithm_base_t := FPU_LOG_BASE_E;
	signal inverse_hyperbolic_tangent : std_logic := '0';
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Logarithm_With_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			add_one => add_one,
			logarithm_base => logarithm_base,
			inverse_hyperbolic_tangent => inverse_hyperbolic_tangent,
			rounding_precision => FPU_PRECISION_EXTENDED,
			rounding_mode => FPU_ROUND_NEAREST,
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
			constant add_one_value : in std_logic;
			constant source_value : in fpu_extended_t;
			constant expected_result : in fpu_extended_t;
			constant expected_codes : in std_logic_vector(3 downto 0);
			constant expected_status : in std_logic_vector(7 downto 0);
			constant inverse_value : in std_logic := '0';
			constant expected_cycles : in natural := 0) is
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			add_one <= add_one_value;
			inverse_hyperbolic_tangent <= inverse_value;
			source <= source_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				assert busy = '1'
					report "FLOGNP1 dropped busy before completion"
					severity failure;
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles < 520 report "logarithm operation timeout" severity failure;
			end loop;
			if expected_cycles /= 0 then
				assert cycles = expected_cycles
					report "logarithm cycle mismatch: " & integer'image(cycles)
					severity failure;
			end if;
			assert result = expected_result and
				condition_codes = expected_codes and
				exception_status = expected_status
				report "FLOGNP1 mismatch: result=" & to_hstring(result) &
					" cc=" & to_hstring(condition_codes) &
					" status=" & to_hstring(exception_status)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		execute('1', x"00000000000000000000", x"00000000000000000000", x"4", x"00");
		execute('1', x"80000000000000000000", x"80000000000000000000", x"C", x"00");
		execute('1', x"7FFF8000000000000000", x"7FFF8000000000000000", x"2", x"00");
		execute('1', x"FFFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20");
		execute('1', x"BFFF8000000000000000", x"FFFF8000000000000000", x"A", x"04");
		execute('1', x"BFFF8000000000000001", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20");
		execute('1', x"7FFFC000000000000001", x"7FFFC000000000000001", x"1", x"00");
		execute('1', x"FFFFA000000000000001", x"FFFFE000000000000001", x"9", x"40");
		execute('1', x"3FFF8000000000000000", x"3FFEB17217F7D1CF79AC", x"0", x"02");
		execute('1', x"4000C000000000000000", x"3FFFB17217F7D1CF79AC", x"0", x"02");
		execute('1', x"BFFE8000000000000000", x"BFFEB17217F7D1CF79AC", x"8", x"02");
		execute('1', x"BFFEC000000000000000", x"BFFFB17217F7D1CF79AC", x"8", x"02");
		execute('1', x"3FE58000000000000000", x"3FE4FFFFFFE000000555", x"0", x"02");
		execute('1', x"BFE58000000000000000", x"BFE580000010000002AB", x"8", x"02");

		execute('0', x"00000000000000000000", x"FFFF8000000000000000", x"A", x"04");
		execute('0', x"80000000000000000000", x"FFFF8000000000000000", x"A", x"04");
		execute('0', x"BFFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20");
		execute('0', x"FFFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20");
		execute('0', x"3FFF8000000000000000", x"00000000000000000000", x"4", x"00");
		execute('0', x"40008000000000000000", x"3FFEB17217F7D1CF79AC", x"0", x"02");
		execute('0', x"3FFE8000000000000000", x"BFFEB17217F7D1CF79AC", x"8", x"02");

		logarithm_base <= FPU_LOG_BASE_TWO;
		execute('0', x"40008000000000000000", x"3FFF8000000000000000", x"0", x"00");
		execute('0', x"40018000000000000000", x"40008000000000000000", x"0", x"00");
		execute('0', x"3FFE8000000000000000", x"BFFF8000000000000000", x"8", x"00");
		logarithm_base <= FPU_LOG_BASE_TEN;
		execute('0', x"4002A000000000000000", x"3FFF8000000000000000", x"0", x"02");
		execute('0', x"40018000000000000000", x"3FFE9A209A84FBCFF799", x"0", x"02");
		execute('0', x"3FFE8000000000000000", x"BFFD9A209A84FBCFF799", x"8", x"02");

		logarithm_base <= FPU_LOG_BASE_E;
		execute('0', x"00000000000000000000", x"00000000000000000000", x"4", x"00", '1');
		execute('0', x"80000000000000000000", x"80000000000000000000", x"C", x"00", '1');
		execute('0', x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '1');
		execute('0', x"FFFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '1');
		execute('0', x"7FFFC123456789ABCDEF", x"7FFFC123456789ABCDEF", x"1", x"00", '1');
		execute('0', x"7FFFA123456789ABCDEF", x"7FFFE123456789ABCDEF", x"1", x"40", '1');
		execute('0', x"3FFF8000000000000000", x"7FFF8000000000000000", x"2", x"04", '1');
		execute('0', x"BFFF8000000000000000", x"FFFF8000000000000000", x"A", x"04", '1');
		execute('0', x"3FFFC000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '1');
		execute('0', x"3FFE8000000000000000", x"3FFE8C9F53D5681854BB", x"0", x"02", '1', 331);
		execute('0', x"BFFE8000000000000000", x"BFFE8C9F53D5681854BB", x"8", x"02", '1');
		execute('0', x"3FFEC000000000000000", x"3FFEF913957192D2BAA3", x"0", x"02", '1', 332);
		execute('0', x"3FE58000000000000000", x"3FE580000000000002AB", x"0", x"02", '1', 255);
		execute('0', x"3FDE8000000000000000", x"3FDE8000000000000000", x"0", x"02", '1');
		execute('0', x"3FFEFFFFFFFFFFFFFFFF", x"4003B437E057B116B792", x"0", x"02", '1', 389);

		report "PASS: logarithm and inverse hyperbolic tangent datapath, domains, special values, and status"
			severity note;
		stop;
	end process;
end architecture;
