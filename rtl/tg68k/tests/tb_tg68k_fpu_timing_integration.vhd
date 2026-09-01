library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_timing_integration is
end entity;

architecture test of tb_tg68k_fpu_timing_integration is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);
	type address_trace_t is array (natural range <>) of
		std_logic_vector(31 downto 0);
	type state_trace_t is array (natural range <>) of
		std_logic_vector(1 downto 0);
	constant EXPECTED_BUS_TRACE : address_trace_t(0 to 15) := (
		x"00000000", x"00000002", x"00000004", x"00000006",
		x"00000008", x"00000100", x"00000102", x"00000104",
		x"00000106", x"00000108", x"0000010A", x"0000010C",
		x"0000010E", x"00000110", x"00000112", x"00000114");
	constant EXPECTED_BUS_STATES : state_trace_t(EXPECTED_BUS_TRACE'range) := (
		"10", "10", "00", "00", "00", "00", "00", "00",
		"00", "00", "00", "00", "00", "00", "00", "00");

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";
		result(16#0080#) := x"7002";
		result(16#0081#) := x"F200";
		result(16#0082#) := x"4000";
		result(16#0083#) := x"F200";
		result(16#0084#) := x"0080";
		result(16#0085#) := x"F200";
		result(16#0086#) := x"00A2";
		result(16#0087#) := x"F200";
		result(16#0088#) := x"010E";
		result(16#0089#) := x"4E72";
		result(16#008A#) := x"2700";
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

	read_memory : process(all)
		variable word_address : natural;
	begin
		data_in <= x"FFFF";
		if not is_x(addr_out) and addr_out(31 downto 16) = x"0000" then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if word_address < MEMORY_WORDS then
				data_in <= memory(word_address);
			end if;
		end if;
	end process;

	stimulus : process
		variable cycle_count : natural := 0;
		variable bus_cycle_count : natural := 0;
		variable move_start_cycle : natural := 0;
		variable register_move_start_cycle : natural := 0;
		variable add_start_cycle : natural := 0;
		variable sine_start_cycle : natural := 0;
		variable stop_start_cycle : natural := 0;
		variable stop_extension_cycle : natural := 0;
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 4000 loop
			wait until rising_edge(clk);
			cycle_count := cycle_count + 1;
			if busstate /= "01" and not is_x(addr_out) then
				bus_cycle_count := bus_cycle_count + 1;
				assert bus_cycle_count <= EXPECTED_BUS_TRACE'length and
					addr_out = EXPECTED_BUS_TRACE(bus_cycle_count - 1) and
					busstate = EXPECTED_BUS_STATES(bus_cycle_count - 1) and
					nWr = '1' and nUDS = '0' and nLDS = '0'
					report "unexpected bus cycle during FPU timing stream"
					severity failure;
				if unsigned(addr_out) >= to_unsigned(16#100#, 32) then
					assert fc = "110"
						report "timed FPU program fetch function code mismatch"
						severity failure;
				end if;
				case addr_out is
					when x"00000102" =>
						if move_start_cycle = 0 then
							move_start_cycle := cycle_count;
						end if;
					when x"00000106" =>
						if register_move_start_cycle = 0 then
							register_move_start_cycle := cycle_count;
						end if;
					when x"0000010A" =>
						if add_start_cycle = 0 then
							add_start_cycle := cycle_count;
						end if;
					when x"0000010E" =>
						if sine_start_cycle = 0 then
							sine_start_cycle := cycle_count;
						end if;
					when x"00000112" =>
						if stop_start_cycle = 0 then
							stop_start_cycle := cycle_count;
						end if;
					when x"00000114" =>
						stop_extension_cycle := cycle_count;
					when others => null;
				end case;
			end if;
			exit when stop_extension_cycle /= 0;
		end loop;
		assert stop_extension_cycle /= 0
			report "timed FPU instruction stream did not retire" severity failure;
		assert register_move_start_cycle - move_start_cycle = 2 and
			add_start_cycle - register_move_start_cycle = 47 and
			sine_start_cycle - add_start_cycle = 25 and
			stop_start_cycle - sine_start_cycle = 60 and
			stop_extension_cycle - stop_start_cycle = 397 and
			bus_cycle_count = EXPECTED_BUS_TRACE'length
			report "FPU CPU-level timing or bus trace mismatch" severity failure;
		report "PASS: exact TG68K 68882 retirement and bus timing" severity note;
		stop;
		wait;
	end process;
end architecture;
