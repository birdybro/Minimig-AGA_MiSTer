library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_conditional_integration is
end entity;

architecture test of tb_tg68k_fpu_conditional_integration is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 4096;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";

		result(16#0080#) := x"203C";
		result(16#0081#) := x"4000";
		result(16#0082#) := x"0000";
		result(16#0083#) := x"F200";
		result(16#0084#) := x"8800";
		result(16#0085#) := x"7200";
		result(16#0086#) := x"F241";
		result(16#0087#) := x"0001";
		result(16#0088#) := x"23C1";
		result(16#0089#) := x"0000";
		result(16#008A#) := x"0204";
		result(16#008B#) := x"207C";
		result(16#008C#) := x"0000";
		result(16#008D#) := x"0301";
		result(16#008E#) := x"F250";
		result(16#008F#) := x"0000";

		result(16#0090#) := x"F281";
		result(16#0091#) := x"0004";
		result(16#0092#) := x"74EE";
		result(16#0093#) := x"7402";
		result(16#0094#) := x"F280";
		result(16#0095#) := x"0004";
		result(16#0096#) := x"7603";
		result(16#0097#) := x"F2CF";
		result(16#0098#) := x"0000";
		result(16#0099#) := x"0006";
		result(16#009A#) := x"78EE";
		result(16#009B#) := x"7804";

		result(16#009C#) := x"7A01";
		result(16#009D#) := x"F24D";
		result(16#009E#) := x"0000";
		result(16#009F#) := x"0004";
		result(16#00A0#) := x"7CEE";
		result(16#00A1#) := x"7C06";
		result(16#00A2#) := x"7800";
		result(16#00A3#) := x"F24C";
		result(16#00A4#) := x"0000";
		result(16#00A5#) := x"0004";
		result(16#00A6#) := x"7E07";

		result(16#00A7#) := x"23C1";
		result(16#00A8#) := x"0000";
		result(16#00A9#) := x"0204";
		result(16#00AA#) := x"23C2";
		result(16#00AB#) := x"0000";
		result(16#00AC#) := x"0208";
		result(16#00AD#) := x"23C3";
		result(16#00AE#) := x"0000";
		result(16#00AF#) := x"020C";
		result(16#00B0#) := x"23C4";
		result(16#00B1#) := x"0000";
		result(16#00B2#) := x"0210";
		result(16#00B3#) := x"23C5";
		result(16#00B4#) := x"0000";
		result(16#00B5#) := x"0214";
		result(16#00B6#) := x"23C6";
		result(16#00B7#) := x"0000";
		result(16#00B8#) := x"0218";
		result(16#00B9#) := x"23C7";
		result(16#00BA#) := x"0000";
		result(16#00BB#) := x"021C";

		result(16#00BC#) := x"F27C";
		result(16#00BD#) := x"0000";
		result(16#00BE#) := x"7001";
		result(16#00BF#) := x"23C0";
		result(16#00C0#) := x"0000";
		result(16#00C1#) := x"0220";
		result(16#00C2#) := x"4E72";
		result(16#00C3#) := x"2700";

		result(16#0180#) := x"A5A5";
		return result;
	end function;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal data_in : std_logic_vector(15 downto 0);
	signal addr_out : std_logic_vector(31 downto 0);
	signal data_write : std_logic_vector(15 downto 0);
	signal nWr : std_logic;
	signal nUDS : std_logic;
	signal nLDS : std_logic;
	signal busstate : std_logic_vector(1 downto 0);
	signal fc : std_logic_vector(2 downto 0);
	signal memory : memory_t := initial_memory;
	signal fscc_memory_write_count : natural range 0 to 2 := 0;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68KdotC_MMU
		port map(
			clk => clk,
			nReset => nReset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => '0',
			CPU => "11",
			MMU_enable => '0',
			FPU_enable => '1',
			addr_out => addr_out,
			data_write => data_write,
			nWr => nWr,
			nUDS => nUDS,
			nLDS => nLDS,
			busstate => busstate,
			longword => open,
			cache_inhibit => open,
			logical_bus_address => open,
			logical_bus_access => open,
			nResetOut => open,
			FC => fc,
			clr_berr => open,
			skipFetch => open,
			regin_out => open,
			CACR_out => open,
			D_CACHE_out => open,
			VBR_out => open
		);

	data_in <= memory(to_integer(unsigned(addr_out(12 downto 1))))
		when not is_x(addr_out) else x"FFFF";

	memory_write : process(clk)
		variable word_address : natural;
	begin
		if rising_edge(clk) and nReset = '1' and busstate = "11" and
				not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(12 downto 1)));
			assert word_address < MEMORY_WORDS
				report "conditional test wrote outside memory" severity failure;
			if nUDS = '0' then
				memory(word_address)(15 downto 8) <= data_write(15 downto 8);
			end if;
			if nLDS = '0' then
				memory(word_address)(7 downto 0) <= data_write(7 downto 0);
			end if;
			if addr_out = x"00000301" then
				assert nUDS = '1' and nLDS = '0' and fc = "101"
					report "FScc used incorrect byte lane or function code"
					severity failure;
				fscc_memory_write_count <= fscc_memory_write_count + 1;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 2000 loop
			wait until rising_edge(clk);
			if memory(16#0110#) = x"0000" and
					memory(16#0111#) = x"0001" then
				wait until rising_edge(clk);
				assert memory(16#0102#) = x"0000" and
					memory(16#0103#) = x"00FF" and
					memory(16#0180#) = x"A500" and
					memory(16#0104#) = x"0000" and
					memory(16#0105#) = x"0002" and
					memory(16#0106#) = x"0000" and
					memory(16#0107#) = x"0003" and
					memory(16#0108#) = x"0000" and
					memory(16#0109#) = x"FFFF" and
					memory(16#010A#) = x"0000" and
					memory(16#010B#) = x"0000" and
					memory(16#010C#) = x"0000" and
					memory(16#010D#) = x"0006" and
					memory(16#010E#) = x"0000" and
					memory(16#010F#) = x"0007" and
					fscc_memory_write_count = 1
					report "conditional instruction stream result mismatch"
					severity failure;
				report "PASS: TG68K FBcc, FDBcc, FScc, and false FTRAPcc integration"
					severity note;
				stop;
			end if;
		end loop;
		assert false report "conditional instruction stream timed out"
			severity failure;
		wait;
	end process;
end architecture;
