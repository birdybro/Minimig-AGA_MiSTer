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

	dut : entity work.TG68K_FPU_Exponential
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
		procedure execute(
			constant source_value : fpu_extended_t;
			constant precision_value : fpu_rounding_precision_t;
			constant mode_value : fpu_rounding_mode_t;
			constant expected_result : fpu_extended_t;
			constant expected_status : std_logic_vector(7 downto 0);
			constant expected_iterations : natural) is
			variable iteration_count : natural := 0;
		begin
			wait until falling_edge(clk);
			source <= source_value;
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
				assert iteration_count < 250
					report "FTWOTOX did not complete" severity failure;
			end loop;
			assert iteration_count = expected_iterations
				report "FTWOTOX iteration count mismatch: " &
					integer'image(iteration_count)
				severity failure;
			assert result = expected_result and
				condition_codes = fpu_condition_codes(expected_result) and
				exception_status = expected_status
				report "FTWOTOX result mismatch: got " & to_hstring(result) &
					" status=" & to_hstring(exception_status)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "FTWOTOX engine did not return idle" severity failure;
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
			FPU_ROUND_NEAREST, x"3FFFB504F333F9DE6484", x"02", 226);
		execute(x"BFFE8000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_PLUS_INFINITY, x"3FFEB504F333F9DE6485", x"02", 226);
		execute(x"4000D000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"40029837F0518DB8A96F", x"02", 226);
		execute(x"3FFF4000000000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"3FFFB504F333F9DE6484", x"02", 226);

		execute(x"3FFE8000000000000000", FPU_PRECISION_DOUBLE,
			FPU_ROUND_ZERO, x"3FFFB504F333F9DE6000", x"02", 226);
		execute(x"3FFE8000000000000000", FPU_PRECISION_SINGLE,
			FPU_ROUND_PLUS_INFINITY, x"3FFFB504F40000000000", x"02", 226);

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

		report "PASS: MC68882 FTWOTOX range reduction and CORDIC" severity note;
		stop;
	end process;
end architecture;
