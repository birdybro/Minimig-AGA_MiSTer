library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_circular_cordic is
end entity;

architecture test of tb_tg68k_fpu_circular_cordic is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal vectoring : std_logic := '0';
	signal narrow_precision : std_logic := '0';
	signal rotate_on_start : std_logic := '0';
	signal x_input : signed(147 downto 0) := (others => '0');
	signal y_input : signed(147 downto 0) := (others => '0');
	signal z_input : signed(147 downto 0) := (others => '0');
	signal x_result : signed(147 downto 0);
	signal y_result : signed(147 downto 0);
	signal z_result : signed(147 downto 0);
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Circular_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			vectoring => vectoring,
			narrow_precision => narrow_precision,
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
				constant narrow_value : in std_logic;
				constant immediate_value : in std_logic;
				constant x_value : in signed(147 downto 0);
				constant y_value : in signed(147 downto 0);
				constant z_value : in signed(147 downto 0);
				constant expected_x : in signed(147 downto 0);
				constant expected_y : in signed(147 downto 0);
				constant expected_z : in signed(147 downto 0);
				constant expected_cycles : in natural) is
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			vectoring <= vectoring_value;
			narrow_precision <= narrow_value;
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
				assert cycles <= 300 report "circular CORDIC timeout"
					severity failure;
			end loop;
			assert cycles = expected_cycles and x_result = expected_x and
					y_result = expected_y and z_result = expected_z
				report "circular CORDIC result or cycle mismatch: x=" &
					to_hstring(x_result) & " y=" & to_hstring(y_result) &
					" z=" & to_hstring(z_result) & " cycles=" &
					integer'image(cycles)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;

		procedure verify_fast_start(
				constant x_value : in signed(147 downto 0);
				constant y_value : in signed(147 downto 0);
				constant z_value : in signed(147 downto 0)) is
			variable baseline_x : signed(147 downto 0);
			variable baseline_y : signed(147 downto 0);
			variable baseline_z : signed(147 downto 0);
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			vectoring <= '0';
			narrow_precision <= '0';
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
				assert cycles <= 300 report "circular CORDIC timeout"
					severity failure;
			end loop;
			assert cycles = 290 severity failure;
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
				assert cycles <= 300 report "circular CORDIC timeout"
					severity failure;
			end loop;
			assert cycles = 289 and x_result = baseline_x and
					y_result = baseline_y and z_result = baseline_z
				report "circular CORDIC fast-start mismatch"
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		execute('1', '1', '0',
			signed'(x"0000000010000000000000000000000000000"),
			signed'(x"0000000008000000000000000000000000000"),
			(147 downto 0 => '0'),
			signed'(x"000000001D7548DCB6F2E08916D128047304C"),
			signed'(x"0000000000000000000000000000000000000"),
			signed'(x"00000000076B19C1586ED3DA2B7F222F65E1E"),
			226);
		execute('1', '1', '0',
			signed'(x"0000000010000000000000000000000000000"),
			signed'(x"FFFFFFFFF8000000000000000000000000000"),
			(147 downto 0 => '0'),
			signed'(x"000000001D7548DCB6F2E08916D1280473048"),
			signed'(x"0000000000000000000000000000000000000"),
			signed'(x"FFFFFFFFF894E63EA7912C25D480DDD09A1E2"),
			226);
		execute('0', '0', '1',
			signed'(x"09B74EDA8435E5A67F5F9092BD7FD40E9C289"),
			(147 downto 0 => '0'), shift_left(to_signed(1, 148), 142),
			signed'(x"0EC835E79946A31457E610231AC1D6180F0A9"),
			signed'(x"061F78A9ABAA58B4698916152CF7EEE1BBDF6"),
			signed'(x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"),
			289);
		execute('0', '0', '1',
			signed'(x"09B74EDA8435E5A67F5F9092BD7FD40E9C289"),
			(147 downto 0 => '0'), -shift_left(to_signed(1, 148), 142),
			signed'(x"0EC835E79946A31457E610231AC1D6180F0A6"),
			signed'(x"F9E087565455A74B9676E9EAD308111E4420C"),
			signed'(x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"),
			289);
		verify_fast_start(
			signed'(x"09B74EDA8435E5A67F5F9092BD7FD40E9C289"),
			signed'(x"0100000000000000000000000000000000000"),
			shift_left(to_signed(1, 148), 142));

		report "PASS: shared circular CORDIC precision, direction, and cycles"
			severity note;
		stop;
	end process;
end architecture;
