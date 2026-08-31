library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_mmu_fault_rte is
generic(
	FAULT_KIND : natural range 0 to 1 := 0
);
end entity;

architecture test of tb_tg68k_mmu_fault_rte is
	constant CLK_PERIOD : time := 10 ns;
	function select_natural(
		condition : boolean;
		true_value : natural;
		false_value : natural) return natural is
	begin
		if condition then
			return true_value;
		end if;
		return false_value;
	end function;

	constant MEMORY_WORDS : natural := 8192;
	constant FRAME_WORD_COUNT : natural := select_natural(FAULT_KIND = 0, 16, 46);
	constant FRAME_BASE_ADDRESS : natural := select_natural(FAULT_KIND = 0,
		16#0FE0#, 16#0FA4#);
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";
		result(4) := x"0000";
		result(5) := x"0180";

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
		result(16#008A#) := x"4EF9";
		result(16#008B#) := x"0000";
		if FAULT_KIND = 0 then
			result(16#008C#) := x"3FFE";
		else
			result(16#008C#) := x"4000";
		end if;
		result(16#1FFF#) := x"4E71";

		-- Make page four resident, flush the ATC, and return from the fault.
		result(16#00C0#) := x"23FC";
		result(16#00C1#) := x"0000";
		result(16#00C2#) := x"2001";
		result(16#00C3#) := x"0000";
		result(16#00C4#) := x"1010";
		result(16#00C5#) := x"F000";
		result(16#00C6#) := x"2400";
		result(16#00C7#) := x"4E73";

		-- Logical $4000 executes here after RTE and records completion.
		result(16#1000#) := x"23FC";
		result(16#1001#) := x"CAFE";
		result(16#1002#) := x"BABE";
		result(16#1003#) := x"0000";
		result(16#1004#) := x"0200";
		result(16#1005#) := x"4E72";
		result(16#1006#) := x"2700";

		result(16#0180#) := x"7FFF";
		result(16#0181#) := x"0002";
		result(16#0182#) := x"0000";
		result(16#0183#) := x"1000";
		result(16#0184#) := x"80CC";
		result(16#0185#) := x"8000";

		result(16#0800#) := x"0000";
		result(16#0801#) := x"0001";
		result(16#0802#) := x"0000";
		result(16#0803#) := x"1001";
		result(16#0806#) := x"0000";
		result(16#0807#) := x"3001";
		result(16#0808#) := x"0000";
		result(16#0809#) := x"0000";
		return result;
	end function;

	signal clk : std_logic := '0';
	signal nreset : std_logic := '0';
	signal data_in : std_logic_vector(15 downto 0);
	signal addr_out : std_logic_vector(31 downto 0);
	signal data_write : std_logic_vector(15 downto 0);
	signal nuds : std_logic;
	signal nlds : std_logic;
	signal busstate : std_logic_vector(1 downto 0);
	signal fc : std_logic_vector(2 downto 0);
	signal memory : memory_t := initial_memory;
	signal frame_write_count : natural := 0;
	signal frame_read_count : natural := 0;
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
			nWr => open,
			nUDS => nuds,
			nLDS => nlds,
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

	memory_read : process(all)
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

	bus_monitor : process(clk)
		variable word_address : natural;
		variable expected_address : unsigned(31 downto 0);
	begin
		if rising_edge(clk) and nreset = '1' and busstate /= "01" and
				not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if busstate = "11" and word_address < MEMORY_WORDS then
				if unsigned(addr_out) >= to_unsigned(FRAME_BASE_ADDRESS, 32) and
						addr_out <= x"00000FFE" then
					expected_address := to_unsigned(16#0FFE#, 32) -
						to_unsigned(frame_write_count * 2, 32);
					assert unsigned(addr_out) = expected_address
						report "fault-frame write order mismatch" severity failure;
					frame_write_count <= frame_write_count + 1;
				end if;
				if nuds = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nlds = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
			elsif busstate = "10" and
					unsigned(addr_out) >= to_unsigned(FRAME_BASE_ADDRESS, 32) and
					addr_out <= x"00000FFE" then
				expected_address := to_unsigned(FRAME_BASE_ADDRESS, 32) +
					to_unsigned(frame_read_count * 2, 32);
				assert unsigned(addr_out) = expected_address and fc = "101" and
					nuds = '0' and nlds = '0'
					report "fault-frame RTE read order/attributes mismatch"
					severity failure;
				frame_read_count <= frame_read_count + 1;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nreset <= '1';
		for iteration in 0 to 10000 loop
			wait until rising_edge(clk);
			exit when memory(16#0100#) = x"CAFE" and
				memory(16#0101#) = x"BABE";
		end loop;
		assert memory(16#0100#) = x"CAFE" and
			memory(16#0101#) = x"BABE"
			report "RTE did not resume at repaired translated instruction page"
			severity failure;
		assert frame_write_count = FRAME_WORD_COUNT and
			frame_read_count = FRAME_WORD_COUNT
			report "fault-frame write/read transfer count mismatch"
			severity failure;
		if FAULT_KIND = 0 then
			assert memory((FRAME_BASE_ADDRESS / 2) + 3) = x"A008"
				report "format-A identification word mismatch" severity failure;
		else
			assert memory((FRAME_BASE_ADDRESS / 2) + 3) = x"B008"
				report "format-B identification word mismatch" severity failure;
		end if;
		assert memory(16#0808#) = x"0000" and
			memory(16#0809#)(15 downto 5) = "00100000000" and
			memory(16#0809#)(1 downto 0) = "01"
			report "fault handler did not install the page descriptor"
			severity failure;
		report "PASS: MMU fault RTE frame read and repaired-page resume kind " &
			integer'image(FAULT_KIND)
			severity note;
		stop;
		wait;
	end process;
end architecture;
