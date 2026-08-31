library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_mmu_wrapper is
end entity;

architecture test of tb_tg68k_mmu_wrapper is
	constant CLK_PERIOD : time := 10 ns;
	constant LOW_MEMORY_WORDS : natural := 8192;
	constant HIGH_MEMORY_WORDS : natural := 16;
	type low_memory_t is array (0 to LOW_MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);
	type high_memory_t is array (0 to HIGH_MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);

	function initial_low_memory return low_memory_t is
		variable result : low_memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";

		-- MOVEA.L #$300,A0; PMOVE (A0),CRP
		result(16#0080#) := x"207C";
		result(16#0081#) := x"0000";
		result(16#0082#) := x"0300";
		result(16#0083#) := x"F010";
		result(16#0084#) := x"4C00";
		-- MOVEA.L #$308,A0; PMOVE (A0),TC
		result(16#0085#) := x"207C";
		result(16#0086#) := x"0000";
		result(16#0087#) := x"0308";
		result(16#0088#) := x"F010";
		result(16#0089#) := x"4000";
		-- The PMOVE operand is logical $4000, physically $20000000.
		result(16#008A#) := x"207C";
		result(16#008B#) := x"0000";
		result(16#008C#) := x"4000";
		result(16#008D#) := x"F010";
		result(16#008E#) := x"0800";
		-- MOVE.L #$12345678,$4004; STOP #$2700
		result(16#008F#) := x"23FC";
		result(16#0090#) := x"1234";
		result(16#0091#) := x"5678";
		result(16#0092#) := x"0000";
		result(16#0093#) := x"4004";
		result(16#0094#) := x"4E72";
		result(16#0095#) := x"2700";

		-- CRP: upper-limit $7fff, short descriptor root at $1000.
		result(16#0180#) := x"7FFF";
		result(16#0181#) := x"0002";
		result(16#0182#) := x"0000";
		result(16#0183#) := x"1000";
		-- TC: E=1, 4 KiB pages, 12 initial bits, one 8-bit table.
		result(16#0184#) := x"80CC";
		result(16#0185#) := x"8000";

		-- Logical page $00000 maps to itself; page $00004 maps to $20000000.
		result(16#0800#) := x"0000";
		result(16#0801#) := x"0001";
		result(16#0808#) := x"2000";
		result(16#0809#) := x"0041";
		return result;
	end function;

	function initial_high_memory return high_memory_t is
		variable result : high_memory_t := (others => x"0000");
	begin
		result(0) := x"A500";
		result(1) := x"8121";
		return result;
	end function;

	signal clk : std_logic := '0';
	signal nreset : std_logic := '0';
	signal data_in : std_logic_vector(15 downto 0);
	signal addr_out : std_logic_vector(31 downto 0);
	signal data_write : std_logic_vector(15 downto 0);
	signal nwr : std_logic;
	signal nuds : std_logic;
	signal nlds : std_logic;
	signal busstate : std_logic_vector(1 downto 0);
	signal fc : std_logic_vector(2 downto 0);
	signal cache_inhibit : std_logic;
	signal low_memory : low_memory_t := initial_low_memory;
	signal high_memory : high_memory_t := initial_high_memory;
	signal high_read_count : natural := 0;
	signal high_write_count : natural := 0;
	signal table_read_count : natural := 0;
	signal table_write_count : natural := 0;
	signal translated_program_fetch_count : natural := 0;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68KdotC_MMU
		port map(
			clk => clk,
			nReset => nreset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => '0',
			CPU => "11",
			MMU_enable => '1',
			addr_out => addr_out,
			data_write => data_write,
			nWr => nwr,
			nUDS => nuds,
			nLDS => nlds,
			busstate => busstate,
			longword => open,
			cache_inhibit => cache_inhibit,
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

	memory_read : process(all)
		variable word_address : natural;
	begin
		data_in <= x"FFFF";
		if not is_x(addr_out) then
			if addr_out(31 downto 16) = x"0000" then
				word_address := to_integer(unsigned(addr_out(13 downto 1)));
				if word_address < LOW_MEMORY_WORDS then
					data_in <= low_memory(word_address);
				end if;
			elsif addr_out(31 downto 16) = x"2000" then
				word_address := to_integer(unsigned(addr_out(4 downto 1)));
				if word_address < HIGH_MEMORY_WORDS then
					data_in <= high_memory(word_address);
				end if;
			end if;
		end if;
	end process;

	bus_monitor : process(clk)
		variable word_address : natural;
	begin
		if rising_edge(clk) and nreset = '1' and busstate /= "01" then
			if addr_out(31 downto 16) = x"2000" then
				word_address := to_integer(unsigned(addr_out(4 downto 1)));
				assert word_address < HIGH_MEMORY_WORDS
					report "translated access exceeded test memory" severity failure;
				assert fc = "101"
					report "translated data access used the wrong function code"
					severity failure;
				assert cache_inhibit = '1'
					report "descriptor cache-inhibit attribute was not propagated"
					severity failure;
				if busstate = "11" then
					high_write_count <= high_write_count + 1;
					if nuds = '0' then
						high_memory(word_address)(15 downto 8) <= data_write(15 downto 8);
					end if;
					if nlds = '0' then
						high_memory(word_address)(7 downto 0) <= data_write(7 downto 0);
					end if;
				else
					high_read_count <= high_read_count + 1;
				end if;
			elsif addr_out(31 downto 12) = x"00001" then
				assert fc = "101"
					report "table walk did not use supervisor-data space"
					severity failure;
				assert cache_inhibit = '1'
					report "table walk was exposed to the external CPU cache"
					severity failure;
				if busstate = "11" then
					table_write_count <= table_write_count + 1;
				else
					table_read_count <= table_read_count + 1;
				end if;
				word_address := to_integer(unsigned(addr_out(13 downto 1)));
				if busstate = "11" and word_address < LOW_MEMORY_WORDS then
					if nuds = '0' then
						low_memory(word_address)(15 downto 8) <= data_write(15 downto 8);
					end if;
					if nlds = '0' then
						low_memory(word_address)(7 downto 0) <= data_write(7 downto 0);
					end if;
				end if;
			elsif busstate = "00" and addr_out(31 downto 8) = x"000001" and
					fc = "110" then
				translated_program_fetch_count <= translated_program_fetch_count + 1;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nreset <= '1';
		for iteration in 0 to 1500 loop
			wait until rising_edge(clk);
			exit when high_memory(2) = x"1234" and high_memory(3) = x"5678";
		end loop;
		assert high_memory(2) = x"1234" and high_memory(3) = x"5678"
			report "translated CPU write did not reach physical memory"
			severity failure;
		assert high_read_count = 2 and high_write_count = 2
			report "translated PMOVE/CPU operand transfer count mismatch: reads=" &
				integer'image(high_read_count) & ", writes=" &
				integer'image(high_write_count) severity failure;
		assert translated_program_fetch_count > 0
			report "instruction fetches did not pass through MMU translation"
			severity failure;
		assert table_read_count >= 4 and table_write_count >= 2
			report "expected table walk/update bus transactions were absent"
			severity failure;
		assert low_memory(16#0801#) = x"0009"
			report "program page descriptor used bit was not written" severity failure;
		assert low_memory(16#0809#) = x"0059"
			report "data page descriptor used/modified bits were not written"
			severity failure;
		report "PASS: TG68K integrated MMU fetch, PMOVE operand, table walk, and write"
			severity note;
		stop;
		wait;
	end process;
end architecture;
