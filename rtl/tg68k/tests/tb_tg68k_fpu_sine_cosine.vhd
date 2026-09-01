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
	signal cosine : std_logic := '0';
	signal tangent : std_logic := '0';
	signal simultaneous : std_logic := '0';
	signal source : fpu_extended_t := (others => '0');
	signal result : fpu_extended_t;
	signal condition_codes : std_logic_vector(3 downto 0);
	signal exception_status : std_logic_vector(7 downto 0);
	signal secondary_round_input : fpu_round_input_t;
	signal secondary_result : fpu_extended_t;
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Sine_Cosine
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			cosine => cosine,
			tangent => tangent,
			simultaneous => simultaneous,
			source => source,
			rounding_precision => FPU_PRECISION_EXTENDED,
			rounding_mode => FPU_ROUND_NEAREST,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			busy => open,
			done => done,
			round_input => open,
			secondary_round_input => secondary_round_input,
			base_exception_status => open
		);

	secondary_rounder : entity work.TG68K_FPU_Round
		port map(
			input_class => secondary_round_input.data_class,
			input_sign => secondary_round_input.sign,
			input_exponent => secondary_round_input.exponent,
			input_significand => secondary_round_input.significand,
			special_value => secondary_round_input.special,
			rounding_precision => FPU_PRECISION_EXTENDED,
			rounding_mode => FPU_ROUND_NEAREST,
			single_extended_range => '0',
			result => secondary_result,
			inexact => open,
			overflow => open,
			underflow => open,
			signaling_nan => open
		);

	stimulus : process
		procedure execute(
				constant source_value : in fpu_extended_t;
				constant expected_result : in fpu_extended_t;
				constant expected_cc : in std_logic_vector(3 downto 0);
				constant expected_status : in std_logic_vector(7 downto 0);
				constant expected_cycles : in natural := 0;
				constant cosine_value : in std_logic := '0';
				constant tangent_value : in std_logic := '0';
				constant simultaneous_value : in std_logic := '0';
				constant expected_secondary : in fpu_extended_t :=
					(others => '0')) is
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			cosine <= cosine_value;
			tangent <= tangent_value;
			simultaneous <= simultaneous_value;
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
			if simultaneous_value = '1' then
				assert secondary_result = expected_secondary
					report "simultaneous cosine mismatch: result=" &
						to_hstring(secondary_result)
					severity failure;
			end if;
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

		execute(x"00000000000000000000", x"3FFF8000000000000000",
			x"0", x"00", 0, '1');
		execute(x"80000000000000000000", x"3FFF8000000000000000",
			x"0", x"00", 0, '1');
		execute(x"3FFE8000000000000000", x"3FFEE0A94032DBEA7CEE",
			x"0", x"02", 258, '1');
		execute(x"BFFE8000000000000000", x"3FFEE0A94032DBEA7CEE",
			x"0", x"02", 0, '1');
		execute(x"3FFF8000000000000000", x"3FFE8A51407DA8345C92",
			x"0", x"02", 0, '1');
		execute(x"40008000000000000000", x"BFFDD51132BA9B902522",
			x"8", x"02", 0, '1');
		execute(x"3FD68000000000000000", x"3FFF8000000000000000",
			x"0", x"02", 0, '1');
		execute(x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF",
			x"1", x"20", 0, '1');

		execute(x"00000000000000000000", x"00000000000000000000",
			x"4", x"00", 0, '0', '1');
		execute(x"80000000000000000000", x"80000000000000000000",
			x"C", x"00", 0, '0', '1');
		execute(x"3FFE8000000000000000", x"3FFE8BDA7ADF9A3A5219",
			x"0", x"02", 323, '0', '1');
		execute(x"BFFE8000000000000000", x"BFFE8BDA7ADF9A3A5219",
			x"8", x"02", 0, '0', '1');
		execute(x"3FFFC90FDAA22168C235", x"C0408A51E04DAABDA35F",
			x"8", x"02", 0, '0', '1');
		execute(x"3FD68000000000000000", x"3FD68000000000000000",
			x"0", x"02", 0, '0', '1');
		execute(x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF",
			x"1", x"20", 0, '0', '1');

		execute(x"00000000000000000000", x"00000000000000000000",
			x"4", x"00", 0, '0', '0', '1',
			x"3FFF8000000000000000");
		execute(x"80000000000000000000", x"80000000000000000000",
			x"C", x"00", 0, '0', '0', '1',
			x"3FFF8000000000000000");
		execute(x"3FFE8000000000000000", x"3FFDF57743A2582F7F44",
			x"0", x"02", 258, '0', '0', '1',
			x"3FFEE0A94032DBEA7CEE");
		execute(x"BFFE8000000000000000", x"BFFDF57743A2582F7F44",
			x"8", x"02", 0, '0', '0', '1',
			x"3FFEE0A94032DBEA7CEE");
		execute(x"7FFF8000000000000000", x"7FFFFFFFFFFFFFFFFFFF",
			x"1", x"20", 0, '0', '0', '1',
			x"7FFFFFFFFFFFFFFFFFFF");
		execute(x"7FFFC000000000000042", x"7FFFC000000000000042",
			x"1", x"00", 0, '0', '0', '1',
			x"7FFFC000000000000042");

		report "PASS: FSIN/FCOS/FTAN/FSINCOS range reduction, CORDIC, special values, and status"
			severity note;
		stop;
	end process;
end architecture;
