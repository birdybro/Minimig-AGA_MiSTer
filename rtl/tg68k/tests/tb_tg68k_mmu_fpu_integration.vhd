library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_mmu_fpu_integration is
end entity;

architecture test of tb_tg68k_mmu_fpu_integration is
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

		result(16#0080#) := x"207C";
		result(16#0081#) := x"0000";
		result(16#0082#) := x"0300";
		result(16#0083#) := x"F010";
		result(16#0084#) := x"4C00";
		result(16#0085#) := x"207C";
		result(16#0086#) := x"0000";
		result(16#0087#) := x"0308";
		result(16#0088#) := x"F010";
		result(16#0089#) := x"4000";

		result(16#008A#) := x"207C";
		result(16#008B#) := x"0000";
		result(16#008C#) := x"4000";
		result(16#008D#) := x"F210";
		result(16#008E#) := x"4800";
		result(16#008F#) := x"207C";
		result(16#0090#) := x"0000";
		result(16#0091#) := x"4010";
		result(16#0092#) := x"F210";
		result(16#0093#) := x"6800";
		result(16#0094#) := x"4E72";
		result(16#0095#) := x"2700";

		result(16#0180#) := x"7FFF";
		result(16#0181#) := x"0002";
		result(16#0182#) := x"0000";
		result(16#0183#) := x"1000";
		result(16#0184#) := x"80CC";
		result(16#0185#) := x"8000";

		result(16#0800#) := x"0000";
		result(16#0801#) := x"0001";
		result(16#0808#) := x"2000";
		result(16#0809#) := x"0041";
		return result;
	end function;

	function initial_high_memory return high_memory_t is
		variable result : high_memory_t := (others => x"0000");
	begin
		result(0) := x"4001";
		result(1) := x"0000";
		result(2) := x"A000";
		result(3) := x"0000";
		result(4) := x"0000";
		result(5) := x"0000";
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
	signal cache_inhibit : std_logic;
	signal logical_address : std_logic_vector(31 downto 0);
	signal logical_access : std_logic;
	signal low_memory : low_memory_t := initial_low_memory;
	signal high_memory : high_memory_t := initial_high_memory;
	signal high_read_count : natural range 0 to 6 := 0;
	signal high_write_count : natural range 0 to 6 := 0;
	signal table_read_count : natural := 0;
	signal table_write_count : natural := 0;
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
			MMU_enable => '1',
			FPU_enable => '1',
			addr_out => addr_out,
			data_write => data_write,
			nWr => nWr,
			nUDS => nUDS,
			nLDS => nLDS,
			busstate => busstate,
			longword => open,
			cache_inhibit => cache_inhibit,
			logical_bus_address => logical_address,
			logical_bus_access => logical_access,
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
		variable transfer_index : natural;
		variable expected_logical : unsigned(31 downto 0);
	begin
		if rising_edge(clk) and nReset = '1' and busstate /= "01" and
				not is_x(addr_out) then
			if addr_out(31 downto 16) = x"2000" then
				word_address := to_integer(unsigned(addr_out(4 downto 1)));
				assert logical_access = '1' and fc = "101" and
					cache_inhibit = '1' and nUDS = '0' and nLDS = '0'
					report "translated FPU bus attributes mismatch" severity failure;
				if busstate = "10" then
					transfer_index := high_read_count;
					expected_logical := to_unsigned(16#4000# +
						transfer_index * 2, 32);
					assert unsigned(addr_out) = to_unsigned(16#20000000# +
						transfer_index * 2, 32) and
						unsigned(logical_address) = expected_logical
						report "translated FPU read address mismatch" severity failure;
					high_read_count <= high_read_count + 1;
				else
					transfer_index := high_write_count;
					expected_logical := to_unsigned(16#4010# +
						transfer_index * 2, 32);
					assert unsigned(addr_out) = to_unsigned(16#20000010# +
						transfer_index * 2, 32) and
						unsigned(logical_address) = expected_logical
						report "translated FPU write address mismatch" severity failure;
					high_write_count <= high_write_count + 1;
					if word_address < HIGH_MEMORY_WORDS then
						high_memory(word_address) <= data_write;
					end if;
				end if;
			elsif addr_out(31 downto 12) = x"00001" then
				assert fc = "101" and cache_inhibit = '1'
					report "combined table cycle attributes mismatch"
					severity failure;
				word_address := to_integer(unsigned(addr_out(13 downto 1)));
				if busstate = "11" then
					table_write_count <= table_write_count + 1;
					if word_address < LOW_MEMORY_WORDS then
						low_memory(word_address) <= data_write;
					end if;
				else
					table_read_count <= table_read_count + 1;
				end if;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 4000 loop
			wait until rising_edge(clk);
			exit when high_write_count = 6;
		end loop;
		assert high_read_count = 6 and high_write_count = 6
			report "translated FPU transfer count mismatch" severity failure;
		for index in 0 to 5 loop
			assert high_memory(8 + index) = high_memory(index)
				report "translated extended FPU data mismatch" severity failure;
		end loop;
		assert table_read_count >= 4 and table_write_count >= 2 and
			low_memory(16#0809#) = x"0059"
			report "translated FPU descriptor side effects mismatch"
			severity failure;
		report "PASS: translated FPU extended read/write and descriptor updates"
			severity note;
		stop;
		wait;
	end process;
end architecture;
