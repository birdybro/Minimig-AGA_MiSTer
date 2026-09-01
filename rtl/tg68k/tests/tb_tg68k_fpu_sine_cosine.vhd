library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_sine_cosine is
end entity;

architecture test of tb_tg68k_fpu_sine_cosine is
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

	dut : entity work.TG68K_FPU_Sine_Cosine
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
				constant expected_status : in std_logic_vector(7 downto 0);
				constant expected_cycles : in natural := 0) is
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
				assert cycles < 400
					report "sine engine timeout" severity failure;
			end loop;
			assert result = expected_result and
				condition_codes = expected_cc and
				exception_status = expected_status
				report "sine result mismatch: result=" & to_hstring(result) &
					" cc=" & to_hstring(condition_codes) &
					" status=" & to_hstring(exception_status)
				severity failure;
			if expected_cycles /= 0 then
				assert cycles = expected_cycles
					report "sine cycle count mismatch: " & integer'image(cycles)
					severity failure;
			end if;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;

		procedure execute_bounded(
				constant source_value : in fpu_extended_t) is
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
				assert cycles < 300
					report "large-argument sine timeout" severity failure;
			end loop;
			assert unsigned(result(78 downto 64)) <= to_unsigned(16#3FFF#, 15) and
				exception_status = x"02" and cycles = 258
				report "large-argument sine range/status mismatch: result=" &
					to_hstring(result) & " status=" &
					to_hstring(exception_status) & " cycles=" &
					integer'image(cycles)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		execute(x"00000000000000000000", x"00000000000000000000", x"4", x"00");
		execute(x"80000000000000000000", x"80000000000000000000", x"C", x"00");
		execute(x"3FFE8000000000000000", x"3FFDF57743A2582F7F44", x"0", x"02", 258);
		execute(x"3FFF4000000000000000", x"3FFDF57743A2582F7F44", x"0", x"02");
		execute(x"BFFE8000000000000000", x"BFFDF57743A2582F7F44", x"8", x"02");
		execute(x"3FFF8000000000000000", x"3FFED76AA47848677021", x"0", x"02");
		execute(x"40008000000000000000", x"3FFEE8C7B7568DA22EFD", x"0", x"02");
		execute(x"3FFEC90FDAA22168C235", x"3FFEB504F333F9DE6485", x"0", x"02");
		execute(x"3FFFC90FDAA22168C235", x"3FFF8000000000000000", x"0", x"02");
		execute(x"4000C90FDAA22168C235", x"BFBEECE675D1FC8F8CBB", x"8", x"02");
		execute(x"3FD68000000000000000", x"3FD68000000000000000", x"0", x"02");
		execute(x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF", x"1", x"20");
		execute(x"7FFFC000000000000042", x"7FFFC000000000000042", x"1", x"00");
		execute(x"7FFF8000000000000041", x"7FFFC000000000000041", x"1", x"40");
		execute_bounded(x"40428000000000000000");
		execute_bounded(x"7FFEFFFFFFFFFFFFFFFF");

		report "PASS: FSIN range reduction, CORDIC, special values, and status"
			severity note;
		stop;
	end process;
end architecture;
