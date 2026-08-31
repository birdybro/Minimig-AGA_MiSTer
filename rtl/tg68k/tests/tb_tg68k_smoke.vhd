library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;

entity tb_tg68k_smoke is
	generic(
		CPU_MODE : natural range 0 to 3 := 3
	);
end entity;

architecture test of tb_tg68k_smoke is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;

	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);
	type expected_transfer_t is record
		cycle : natural;
		state : std_logic_vector(1 downto 0);
		address : std_logic_vector(31 downto 0);
		write_cycle : std_logic;
		strobes : std_logic_vector(1 downto 0);
		data : std_logic_vector(15 downto 0);
	end record;
	type expected_transfers_t is array (natural range <>) of expected_transfer_t;

	constant EXPECTED_TRANSFERS : expected_transfers_t := (
		(6,  "10", x"00000000", '1', "00", x"0000"),
		(7,  "10", x"00000002", '1', "00", x"1000"),
		(8,  "00", x"00000004", '1', "00", x"0000"),
		(9,  "00", x"00000006", '1', "00", x"0100"),
		(10, "00", x"00000008", '1', "00", x"4E71"),
		(12, "00", x"00000100", '1', "00", x"7001"),
		(13, "00", x"00000102", '1', "00", x"5280"),
		(14, "00", x"00000104", '1', "00", x"23C0"),
		(15, "00", x"00000106", '1', "00", x"0000"),
		(16, "00", x"00000108", '1', "00", x"0200"),
		(17, "00", x"0000010A", '1', "00", x"4E72"),
		(18, "11", x"00000200", '0', "00", x"0000"),
		(19, "11", x"00000202", '0', "00", x"0002"),
		(20, "00", x"0000010C", '1', "00", x"2700")
	);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(16#0000#) := x"0000";
		result(16#0001#) := x"1000";
		result(16#0002#) := x"0000";
		result(16#0003#) := x"0100";

		result(16#0080#) := x"7001";
		result(16#0081#) := x"5280";
		result(16#0082#) := x"23C0";
		result(16#0083#) := x"0000";
		result(16#0084#) := x"0200";
		result(16#0085#) := x"4E72";
		result(16#0086#) := x"2700";
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
	signal memory : memory_t := initial_memory;
	signal cycle_count : natural := 0;
	signal transfer_count : natural := 0;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68KdotC_Kernel
		port map(
			clk => clk,
			nReset => nreset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => '0',
			CPU => std_logic_vector(to_unsigned(CPU_MODE, 2)),
			addr_out => addr_out,
			data_write => data_write,
			nWr => nwr,
			nUDS => nuds,
			nLDS => nlds,
			busstate => busstate,
			longword => open,
			nResetOut => open,
			FC => open,
			clr_berr => open,
			skipFetch => open,
			regin_out => open,
			CACR_out => open,
			D_CACHE_out => open,
			VBR_out => open
		);

	reset_driver : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nreset <= '1';
		wait;
	end process;

	memory_read : process(all)
		variable word_address : natural;
	begin
		data_in <= x"FFFF";
		if not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if word_address < MEMORY_WORDS then
				data_in <= memory(word_address);
			end if;
		end if;
	end process;

	memory_write : process(clk)
		variable word_address : natural;
	begin
		if rising_edge(clk) then
			if nreset = '1' and busstate = "11" and not is_x(addr_out) then
				word_address := to_integer(unsigned(addr_out(13 downto 1)));
				assert word_address < MEMORY_WORDS
					report "write outside test memory" severity failure;
				if nuds = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nlds = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
			end if;
		end if;
	end process;

	trace : process(clk)
		file trace_file : text open write_mode is "build/bus_trace.log";
		variable trace_line : line;
		variable observed_data : std_logic_vector(15 downto 0);
	begin
		if rising_edge(clk) then
			if nreset = '1' then
				cycle_count <= cycle_count + 1;
				if busstate /= "01" then
					assert transfer_count < EXPECTED_TRANSFERS'length
						report "unexpected extra bus transfer" severity failure;
					if busstate = "11" then
						observed_data := data_write;
					else
						observed_data := data_in;
					end if;
					assert cycle_count = EXPECTED_TRANSFERS(transfer_count).cycle
						report "bus transfer occurred on the wrong cycle" severity failure;
					assert busstate = EXPECTED_TRANSFERS(transfer_count).state
						report "bus transfer has the wrong state" severity failure;
					assert addr_out = EXPECTED_TRANSFERS(transfer_count).address
						report "bus transfer has the wrong address" severity failure;
					assert nwr = EXPECTED_TRANSFERS(transfer_count).write_cycle
						report "bus transfer has the wrong direction" severity failure;
					assert nuds & nlds = EXPECTED_TRANSFERS(transfer_count).strobes
						report "bus transfer has the wrong byte strobes" severity failure;
					assert observed_data = EXPECTED_TRANSFERS(transfer_count).data
						report "bus transfer has the wrong data" severity failure;
					transfer_count <= transfer_count + 1;
					write(trace_line, cycle_count);
					write(trace_line, string'(" "));
					write(trace_line, to_integer(unsigned(busstate)));
					write(trace_line, string'(" "));
					write(trace_line, to_hstring(addr_out));
					write(trace_line, string'(" "));
					write(trace_line, nwr);
					write(trace_line, string'(" "));
					write(trace_line, nuds);
					write(trace_line, nlds);
					write(trace_line, string'(" "));
					write(trace_line, to_hstring(observed_data));
					writeline(trace_file, trace_line);
				end if;
			end if;
		end if;
	end process;

	watchdog : process
	begin
		wait until nreset = '1';
		for iteration in 0 to 300 loop
			wait until rising_edge(clk);
			if memory(16#0101#) = x"0002" then
				wait until rising_edge(clk);
				assert cycle_count = 21
					report "integer program completed on the wrong cycle" severity failure;
				assert transfer_count = EXPECTED_TRANSFERS'length
					report "integer program used the wrong number of bus transfers"
					severity failure;
				report "PASS: TG68K integer smoke CPU mode " &
					integer'image(CPU_MODE) &
					", cycles=" & integer'image(cycle_count) &
					", transfers=" & integer'image(transfer_count)
					severity note;
				stop;
			end if;
		end loop;
		assert false report "timeout waiting for integer program result"
			severity failure;
	end process;
end architecture;
