library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_series_arithmetic is
end entity;

architecture test of tb_tg68k_fpu_series_arithmetic is
	constant CLOCK_PERIOD : time := 10 ns;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal cube_divide : std_logic := '0';
	signal divide_by_six : std_logic := '0';
	signal source_significand : unsigned(63 downto 0) := (others => '0');
	signal product_left : unsigned(63 downto 0);
	signal product_right : unsigned(63 downto 0);
	signal product_result : unsigned(127 downto 0);
	signal result_shift_count : natural range 0 to 2 := 0;
	signal result_shift_cube : std_logic := '0';
	signal square_result : unsigned(127 downto 0);
	signal cube_quotient : unsigned(79 downto 0);
	signal result_low_pair : unsigned(1 downto 0);
	signal cube_remainder : natural range 0 to 5;
	signal busy : std_logic;
	signal done : std_logic;
begin
	clk <= not clk after CLOCK_PERIOD / 2;
	product_result <= product_left * product_right;

	dut : entity work.TG68K_FPU_Series_Arithmetic
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			cube_divide => cube_divide,
			divide_by_six => divide_by_six,
			source_significand => source_significand,
			product_left => product_left,
			product_right => product_right,
			product_result => product_result,
			result_shift_count => result_shift_count,
			result_shift_cube => result_shift_cube,
			square_result => square_result,
			cube_quotient => cube_quotient,
			result_low_pair => result_low_pair,
			cube_remainder => cube_remainder,
			busy => busy,
			done => done
		);

	stimulus : process
		variable lfsr : unsigned(63 downto 0) := x"D4E12C77A53B908F";
		variable feedback : std_logic;
		variable expected_square : unsigned(127 downto 0);
		variable expected_shifted_square : unsigned(127 downto 0);
		variable expected_cube : unsigned(79 downto 0);
		variable expected_quotient : unsigned(79 downto 0);
		variable expected_shifted_quotient : unsigned(79 downto 0);
		variable expected_remainder : natural range 0 to 5;
		variable cycles : natural;

		procedure wait_for_result(constant expected_cycles : in natural) is
		begin
			cycles := 0;
			loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				exit when done = '1';
			end loop;
			assert cycles = expected_cycles
				report "series arithmetic latency mismatch" severity failure;
		end procedure;

		procedure release_held_request is
		begin
			wait until rising_edge(clk);
			start <= '0';
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "held series request restarted after completion"
				severity failure;
		end procedure;
	begin
		wait for 2 * CLOCK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		for vector_index in 0 to 31 loop
			source_significand <= lfsr;
			cube_divide <= '0';
			result_shift_cube <= '0';
			start <= '1';
			wait until rising_edge(clk);
			expected_square := lfsr * lfsr;
			wait_for_result(64);
			assert square_result = expected_square
				report "series square result mismatch" severity failure;
			release_held_request;
			assert result_low_pair = expected_square(1 downto 0)
				report "series square low pair mismatch" severity failure;
			result_shift_count <= 2;
			wait until rising_edge(clk);
			result_shift_count <= 0;
			wait for 1 ns;
			expected_shifted_square := shift_right(expected_square, 2);
			assert square_result = expected_shifted_square
				report "series square shift mismatch" severity failure;

			for divisor_index in 0 to 1 loop
				source_significand <= lfsr;
				cube_divide <= '1';
				result_shift_cube <= '1';
				if divisor_index = 0 then
					divide_by_six <= '0';
				else
					divide_by_six <= '1';
				end if;
				start <= '1';
				wait until rising_edge(clk);
				expected_cube := lfsr * expected_square(127 downto 112);
				if divisor_index = 0 then
					expected_quotient := expected_cube / 3;
					expected_remainder := to_integer(expected_cube mod 3);
				else
					expected_quotient := expected_cube / 6;
					expected_remainder := to_integer(expected_cube mod 6);
				end if;
				wait_for_result(144);
				assert cube_quotient = expected_quotient and
					cube_remainder = expected_remainder
					report "series cube/divide result mismatch" severity failure;
				release_held_request;
				assert result_low_pair = expected_quotient(1 downto 0)
					report "series cube low pair mismatch" severity failure;
				result_shift_count <= 1;
				wait until rising_edge(clk);
				result_shift_count <= 0;
				wait for 1 ns;
				expected_shifted_quotient := shift_right(expected_quotient, 1);
				assert cube_quotient = expected_shifted_quotient
					report "series cube shift mismatch" severity failure;
			end loop;

			feedback := lfsr(63) xor lfsr(62) xor lfsr(60) xor lfsr(59);
			lfsr := lfsr(62 downto 0) & feedback;
		end loop;

		report "PASS: shared FPU series square, cube, divide, and timing"
			severity note;
		stop;
		wait;
	end process;
end architecture;
