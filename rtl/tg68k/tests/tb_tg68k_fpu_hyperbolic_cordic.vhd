library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_hyperbolic_cordic is
end entity;

architecture test of tb_tg68k_fpu_hyperbolic_cordic is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal vectoring : std_logic := '0';
	signal rotate_on_start : std_logic := '0';
	signal x_input : signed(99 downto 0) := (others => '0');
	signal y_input : signed(99 downto 0) := (others => '0');
	signal z_input : signed(112 downto 0) := (others => '0');
	signal x_result : signed(99 downto 0);
	signal y_result : signed(99 downto 0);
	signal z_result : signed(112 downto 0);
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Hyperbolic_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			vectoring => vectoring,
			rotate_on_start => rotate_on_start,
			x_input => x_input,
			y_input => y_input,
			z_input => z_input,
			x_result => x_result,
			y_result => y_result,
			z_result => z_result,
			busy => open,
			done => done
		);

	stimulus : process
		procedure execute(
				constant vectoring_value : in std_logic;
				constant immediate_value : in std_logic;
				constant x_value : in signed(99 downto 0);
				constant y_value : in signed(99 downto 0);
				constant z_value : in signed(112 downto 0);
				constant expected_x : in signed(99 downto 0);
				constant expected_y : in signed(99 downto 0);
				constant expected_z : in signed(112 downto 0);
				constant expected_cycles : in natural) is
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			vectoring <= vectoring_value;
			rotate_on_start <= immediate_value;
			x_input <= x_value;
			y_input <= y_value;
			z_input <= z_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles <= 210 report "hyperbolic CORDIC timeout"
					severity failure;
			end loop;
			assert cycles = expected_cycles and x_result = expected_x and
					y_result = expected_y and z_result = expected_z
				report "hyperbolic CORDIC result or cycle mismatch: x=" &
					to_hstring(x_result) & " y=" & to_hstring(y_result) &
					" z=" & to_hstring(z_result) & " cycles=" &
					integer'image(cycles)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;

		procedure verify_fast_start(
				constant x_value : in signed(99 downto 0);
				constant y_value : in signed(99 downto 0);
				constant z_value : in signed(112 downto 0)) is
			variable baseline_x : signed(99 downto 0);
			variable baseline_y : signed(99 downto 0);
			variable baseline_z : signed(112 downto 0);
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			vectoring <= '0';
			rotate_on_start <= '0';
			x_input <= x_value;
			y_input <= y_value;
			z_input <= z_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles <= 210 report "hyperbolic CORDIC timeout"
					severity failure;
			end loop;
			assert cycles = 198 severity failure;
			baseline_x := x_result;
			baseline_y := y_result;
			baseline_z := z_result;
			wait until rising_edge(clk);
			wait for 1 ns;

			wait until falling_edge(clk);
			rotate_on_start <= '1';
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			cycles := 0;
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles <= 210 report "hyperbolic CORDIC timeout"
					severity failure;
			end loop;
			assert cycles = 197 and x_result = baseline_x and
					y_result = baseline_y and z_result = baseline_z
				report "hyperbolic CORDIC fast-start mismatch"
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		execute('0', '1',
			signed'(x"1351E87200EEC232964A4EC8F"),
			(99 downto 0 => '0'), resize(shift_left(to_signed(1, 100), 94), 113),
			signed'(x"1080AB05CA6145EDCDE9039A3"),
			signed'(x"040AB3367420407999D337D03"),
			(112 downto 0 => '0'), 197);
		execute('0', '1',
			signed'(x"1351E87200EEC232964A4EC8F"),
			(99 downto 0 => '0'), -resize(shift_left(to_signed(1, 100), 94), 113),
			signed'(x"1080AB05CA6145EDCDE903991"),
			signed'(x"FBF54CC98BDFBF86662CC82FD"),
			(112 downto 0 => '0'), 197);
		execute('1', '0', shift_left(to_signed(5, 100), 95),
			shift_left(to_signed(1, 100), 95), (112 downto 0 => '0'),
			signed'(x"207503928AEC2222732E63F89"),
			signed'(x"0000000000000000000000001"),
			signed'('0' & x"000033E647D97F3097E56D1AECDC"), 198);
		execute('1', '0', shift_left(to_signed(5, 100), 95),
			-shift_left(to_signed(1, 100), 95), (112 downto 0 => '0'),
			signed'(x"207503928AEC2222732E63F9A"),
			signed'(x"FFFFFFFFFFFFFFFFFFFFFFFFF"),
			signed'('1' & x"FFFFCC19B82680CF681A92E51324"), 198);
		execute('0', '1',
			signed'(x"1351E87200EEC232964A4EC8F"),
			(99 downto 0 => '0'), resize(shift_left(to_signed(1, 100), 94), 113),
			signed'(x"1080AB05CA6145EDCDE9039A3"),
			signed'(x"040AB3367420407999D337D03"),
			(112 downto 0 => '0'), 197);
		verify_fast_start(
			signed'(x"1351E87200EEC232964A4EC8F"),
			signed'(x"0100000000000000000000000"),
			resize(shift_left(to_signed(1, 100), 94), 113));

		report "PASS: shared hyperbolic CORDIC modes, repeats, and cycles"
			severity note;
		stop;
	end process;
end architecture;
