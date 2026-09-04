library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_arc_tangent is
end entity;

architecture test of tb_tg68k_fpu_arc_tangent is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal arc_sine : std_logic := '0';
	signal arc_cosine : std_logic := '0';
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal done : std_logic;
	signal cordic_start : std_logic;
	signal cordic_x_input : signed(147 downto 0);
	signal cordic_y_input : signed(147 downto 0);
	signal cordic_z_input : signed(147 downto 0);
	signal cordic_z_result : signed(147 downto 0);
	signal cordic_done : std_logic;
	signal root_start : std_logic;
	signal root_radicand : unsigned(225 downto 0);
	signal root_result : unsigned(112 downto 0);
	signal root_done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	cordic : entity work.TG68K_FPU_Circular_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => cordic_start,
			vectoring => '1',
			narrow_precision => '1',
			rotate_on_start => '0',
			x_input => cordic_x_input,
			y_input => cordic_y_input,
			z_input => cordic_z_input,
			external_shifted_coordinate => (others => '0'),
			shift_source_out => open,
			shift_amount_out => open,
			x_result => open,
			y_result => open,
			z_result => cordic_z_result,
			busy => open,
			done => cordic_done
		);

	root_engine : entity work.TG68K_FPU_Square_Root_Engine
		port map(
			clk => clk,
			nReset => nReset,
			narrow_start => '0',
			narrow_radicand => (others => '0'),
			wide_start => root_start,
			wide_radicand => root_radicand,
			root_result => root_result,
			remainder_nonzero => open,
			busy => open,
			done => root_done
		);

	dut : entity work.TG68K_FPU_Arc_Tangent
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			arc_sine => arc_sine,
			arc_cosine => arc_cosine,
			rounding_precision => FPU_PRECISION_EXTENDED,
			rounding_mode => FPU_ROUND_NEAREST,
			cordic_start => cordic_start,
			cordic_x_input => cordic_x_input,
			cordic_y_input => cordic_y_input,
			cordic_z_input => cordic_z_input,
			cordic_z_result => cordic_z_result,
			cordic_done => cordic_done,
			root_start => root_start,
			root_radicand => root_radicand,
			root_result => root_result,
			root_done => root_done,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			busy => open,
			done => done,
			round_input => open,
			base_exception_status => open
		);

	stimulus : process
		procedure execute(
				constant source_value : in fpu_extended_t;
				constant expected_result : in fpu_extended_t;
				constant expected_cc : in std_logic_vector(3 downto 0);
				constant expected_status : in std_logic_vector(7 downto 0);
				constant arc_sine_value : in std_logic := '0';
				constant expected_cycles : in natural := 0;
				constant arc_cosine_value : in std_logic := '0') is
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			source <= source_value;
			arc_sine <= arc_sine_value;
			arc_cosine <= arc_cosine_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles < 650 report "inverse circular timeout" severity failure;
			end loop;
			if expected_cycles /= 0 then
				assert cycles = expected_cycles
					report "inverse circular cycle mismatch: " & integer'image(cycles)
					severity failure;
			end if;
			assert result = expected_result and condition_codes = expected_cc and
				exception_status = expected_status
				report "FATAN result/status mismatch: source=" & to_hstring(source_value) &
					" result=" & to_hstring(result) &
					" expected=" & to_hstring(expected_result) &
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
		execute(x"00000000000000000000", x"00000000000000000000", x"4", x"00");
		execute(x"80000000000000000000", x"80000000000000000000", x"C", x"00");
		execute(x"3FFF8000000000000000", x"3FFEC90FDAA22168C235", x"0", x"02");
		execute(x"BFFF8000000000000000", x"BFFEC90FDAA22168C235", x"8", x"02");
		execute(x"40008000000000000000", x"3FFF8DB70C975DF22363", x"0", x"02");
		execute(x"7FFF0000000000000000", x"3FFFC90FDAA22168C235", x"0", x"02");
		execute(x"FFFF0000000000000000", x"BFFFC90FDAA22168C235", x"8", x"02");
		execute(x"7FFFC000000000000042", x"7FFFC000000000000042", x"1", x"00");
		execute(x"7FFF8000000000000041", x"7FFFC000000000000041", x"1", x"40");

		execute(x"00000000000000000000", x"00000000000000000000", x"4", x"00", '1');
		execute(x"80000000000000000000", x"80000000000000000000", x"C", x"00", '1');
		execute(x"3FFF8000000000000000", x"3FFFC90FDAA22168C235", x"0", x"02", '1');
		execute(x"BFFF8000000000000000", x"BFFFC90FDAA22168C235", x"8", x"02", '1');
		execute(x"3FFE8000000000000000", x"3FFE860A91C16B9B2C23", x"0", x"02", '1', 457);
		execute(x"BFFE8000000000000000", x"BFFE860A91C16B9B2C23", x"8", x"02", '1');
		execute(x"3FFEC000000000000000", x"3FFED91A98AE3406E041", x"0", x"02", '1');
		execute(x"3FFEFFFFFFFFFFFFFFFF", x"3FFFC90FDAA16C63CF01", x"0", x"02", '1', 456);
		execute(x"3FE58000000000000000", x"3FE58000000000000155", x"0", x"02", '1');
		execute(x"3FDD8000000000000000", x"3FDD8000000000000000", x"0", x"02", '1');
		execute(x"40008000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '1');
		execute(x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '1');
		execute(x"7FFFC000000000000042", x"7FFFC000000000000042", x"1", x"00", '1');
		execute(x"7FFF8000000000000041", x"7FFFC000000000000041", x"1", x"40", '1');

		execute(x"00000000000000000000", x"3FFFC90FDAA22168C235", x"0", x"02", '0', 0, '1');
		execute(x"80000000000000000000", x"3FFFC90FDAA22168C235", x"0", x"02", '0', 0, '1');
		execute(x"3FFF8000000000000000", x"00000000000000000000", x"4", x"00", '0', 0, '1');
		execute(x"BFFF8000000000000000", x"4000C90FDAA22168C235", x"0", x"02", '0', 0, '1');
		execute(x"3FFE8000000000000000", x"3FFF860A91C16B9B2C23", x"0", x"02", '0', 456, '1');
		execute(x"BFFE8000000000000000", x"4000860A91C16B9B2C23", x"0", x"02", '0', 456, '1');
		execute(x"3FFEFFFFFFFFFFFFFFFF", x"3FDFB504F333F9DE6484", x"0", x"02", '0', 488, '1');
		execute(x"3F8F8000000000000000", x"3FFFC90FDAA22168C235", x"0", x"02", '0', 567, '1');
		execute(x"3F8E8000000000000000", x"3FFFC90FDAA22168C235", x"0", x"02", '0', 455, '1');
		execute(x"40008000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '0', 0, '1');
		execute(x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20", '0', 0, '1');
		execute(x"7FFFC000000000000042", x"7FFFC000000000000042", x"1", x"00", '0', 0, '1');
		execute(x"7FFF8000000000000041", x"7FFFC000000000000041", x"1", x"40", '0', 0, '1');

		report "PASS: FATAN/FASIN/FACOS CORDIC, domains, special values, and status"
			severity note;
		stop;
	end process;
end architecture;
