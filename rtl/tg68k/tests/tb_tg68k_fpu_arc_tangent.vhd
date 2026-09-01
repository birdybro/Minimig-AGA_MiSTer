library ieee;
use ieee.std_logic_1164.all;
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
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Arc_Tangent
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			rounding_precision => FPU_PRECISION_EXTENDED,
			rounding_mode => FPU_ROUND_NEAREST,
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
				constant expected_status : in std_logic_vector(7 downto 0)) is
			variable cycles : natural := 0;
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
				cycles := cycles + 1;
				assert cycles < 250 report "FATAN timeout" severity failure;
			end loop;
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
		report "PASS: FATAN CORDIC, signed zero, infinity, and NaN behavior"
			severity note;
		stop;
	end process;
end architecture;
