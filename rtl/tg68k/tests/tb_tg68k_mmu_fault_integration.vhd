library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_mmu_fault_integration is
generic(
	FAULT_KIND : natural range 0 to 5 := 0
);
end entity;

architecture test of tb_tg68k_mmu_fault_integration is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;
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

		-- Install CRP and then enable translation through TC.
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
		if FAULT_KIND = 0 or FAULT_KIND = 5 then
			-- MOVE.L #$12345678,$00004000: data write fault.
			result(16#008A#) := x"23FC";
			result(16#008B#) := x"1234";
			result(16#008C#) := x"5678";
			result(16#008D#) := x"0000";
			result(16#008E#) := x"4000";
		elsif FAULT_KIND = 1 then
			-- Execute the resident NOP at $3FFE, then fault on sequential fetch.
			result(16#008A#) := x"4EF9";
			result(16#008B#) := x"0000";
			result(16#008C#) := x"3FFE";
			result(16#1FFF#) := x"4E71";
		elsif FAULT_KIND = 2 then
			-- Fault while JMP is executing to require a format-B frame.
			result(16#008A#) := x"4EF9";
			result(16#008B#) := x"0000";
			result(16#008C#) := x"4000";
		else
			-- MOVE.L $00004000,D0: data read fault.
			result(16#008A#) := x"2039";
			result(16#008B#) := x"0000";
			result(16#008C#) := x"4000";
		end if;
		result(16#00C0#) := x"4E72";
		result(16#00C1#) := x"2700";

		result(16#0180#) := x"7FFF";
		result(16#0181#) := x"0002";
		result(16#0182#) := x"0000";
		result(16#0183#) := x"1000";
		result(16#0184#) := x"80CC";
		result(16#0185#) := x"8000";

		-- Page zero is resident; logical page four is invalid.
		result(16#0800#) := x"0000";
		result(16#0801#) := x"0001";
		result(16#0806#) := x"0000";
		result(16#0807#) := x"3001";
		result(16#0808#) := x"0000";
		if FAULT_KIND = 5 then
			result(16#0809#) := x"2001";
		else
			result(16#0809#) := x"0000";
		end if;
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
	signal bus_error : std_logic;
	signal memory : memory_t := initial_memory;
	signal stack_write_count : natural := 0;
	signal handler_fetch_seen : std_logic := '0';
	signal table_fault_cycle_count : natural := 0;
	signal translated_data_cycle_seen : std_logic := '0';
begin
	clk <= not clk after CLK_PERIOD / 2;
	bus_error <= '1' when
		(FAULT_KIND = 4 and busstate = "10" and addr_out = x"00001010") or
		(FAULT_KIND = 5 and busstate = "11" and addr_out = x"00001012") else
		'0';

	dut : entity work.TG68KdotC_MMU
		port map(
			clk => clk,
			nReset => nreset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => bus_error,
			CPU => "11",
			MMU_enable => '1',
			addr_out => addr_out,
			data_write => data_write,
			nWr => nwr,
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
		variable lowest_stack_address : unsigned(31 downto 0);
	begin
		if rising_edge(clk) and nreset = '1' and busstate /= "01" and
				not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if busstate = "11" and word_address < MEMORY_WORDS then
				if FAULT_KIND = 5 and addr_out = x"00001012" then
					assert bus_error = '1' and fc = "101"
						report "descriptor-update BERR cycle attributes mismatch"
						severity failure;
					table_fault_cycle_count <= table_fault_cycle_count + 1;
				end if;
				if FAULT_KIND = 1 then
					lowest_stack_address := to_unsigned(16#0FE0#, 32);
				else
					lowest_stack_address := to_unsigned(16#0FA4#, 32);
				end if;
				if unsigned(addr_out) >= lowest_stack_address and
						addr_out <= x"00000FFE" then
					expected_address := to_unsigned(16#0FFE#, 32) -
						to_unsigned(stack_write_count * 2, 32);
					assert unsigned(addr_out) = expected_address
						report "MMU fault frame write order mismatch" severity failure;
					assert nuds = '0' and nlds = '0' and fc = "101"
						report "MMU fault frame bus attributes mismatch" severity failure;
					stack_write_count <= stack_write_count + 1;
				end if;
				if nuds = '0' and bus_error = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nlds = '0' and bus_error = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
			end if;
			if FAULT_KIND = 4 and busstate = "10" and
					addr_out = x"00001010" then
				assert bus_error = '1' and fc = "101"
					report "descriptor-read BERR cycle attributes mismatch"
					severity failure;
				table_fault_cycle_count <= table_fault_cycle_count + 1;
			end if;
			if (FAULT_KIND = 4 or FAULT_KIND = 5) and
					unsigned(addr_out) >= to_unsigned(16#2000#, 32) and
					unsigned(addr_out) < to_unsigned(16#3000#, 32) then
				translated_data_cycle_seen <= '1';
			end if;
			if busstate = "00" and addr_out = x"00000180" then
				handler_fetch_seen <= '1';
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nreset <= '1';
		for iteration in 0 to 5000 loop
			wait until rising_edge(clk);
			exit when handler_fetch_seen = '1';
		end loop;
		assert handler_fetch_seen = '1'
			report "MMU data fault did not reach vector 2 handler" severity failure;
		if FAULT_KIND = 0 then
			assert stack_write_count = 46
				report "MMU data fault did not write exactly 46 frame words"
				severity failure;
			assert memory(16#07D2#) = x"2700"
				report "format-B status register mismatch" severity failure;
			assert memory(16#07D3#) = x"0000" and
				memory(16#07D4#) = x"0114"
				report "format-B faulting PC mismatch" severity failure;
			assert memory(16#07D5#) = x"B008"
				report "format-B format/vector word mismatch" severity failure;
			assert memory(16#07D7#) = x"0105"
				report "format-B data-fault SSW mismatch" severity failure;
			assert memory(16#07DA#) = x"0000" and
				memory(16#07DB#) = x"4000"
				report "format-B logical fault address mismatch: " &
					to_hstring(memory(16#07DA#)) & to_hstring(memory(16#07DB#))
				severity failure;
			assert memory(16#07DE#) = x"1234" and
				memory(16#07DF#) = x"5678"
				report "format-B data output buffer mismatch" severity failure;
			assert memory(16#07ED#)(15 downto 12) = x"0"
				report "format-B implementation version mismatch" severity failure;
		elsif FAULT_KIND = 1 then
			assert stack_write_count = 16
				report "MMU instruction fault did not write exactly 16 frame words"
				severity failure;
			assert memory(16#07F0#) = x"2700"
				report "format-A status register mismatch: " &
					to_hstring(memory(16#07F0#)) severity failure;
			assert memory(16#07F1#) = x"0000" and
				memory(16#07F2#) = x"4000"
				report "format-A stacked PC mismatch" severity failure;
			assert memory(16#07F3#) = x"A008"
				report "format-A format/vector word mismatch" severity failure;
			assert memory(16#07F5#) = x"A000"
				report "format-A instruction-fault SSW mismatch" severity failure;
		elsif FAULT_KIND = 2 then
			assert stack_write_count = 46
				report "in-progress instruction fault did not write 46 frame words"
				severity failure;
			assert memory(16#07D2#) = x"2700" and
				memory(16#07D3#) = x"0000" and
				memory(16#07D4#) = x"0114"
				report "in-progress instruction fault context mismatch"
				severity failure;
			assert memory(16#07D5#) = x"B008" and
				memory(16#07D7#) = x"5000"
				report "in-progress instruction fault format/SSW mismatch"
				severity failure;
			assert memory(16#07DA#) = x"0000" and
				memory(16#07DB#) = x"4000"
				report "in-progress instruction logical fault address mismatch"
				severity failure;
		elsif FAULT_KIND = 3 then
			assert stack_write_count = 46
				report "MMU data read fault did not write 46 frame words"
				severity failure;
			assert memory(16#07D2#) = x"2700" and
				memory(16#07D3#) = x"0000" and
				memory(16#07D4#) = x"0114"
				report "data read fault context mismatch" severity failure;
			assert memory(16#07D5#) = x"B008" and
				memory(16#07D7#) = x"0145"
				report "data read fault format/SSW mismatch" severity failure;
			assert memory(16#07DA#) = x"0000" and
				memory(16#07DB#) = x"4000"
				report "data read logical fault address mismatch" severity failure;
		elsif FAULT_KIND = 4 then
			assert stack_write_count = 46 and table_fault_cycle_count = 1
				report "descriptor-read BERR did not produce one format-B fault"
				severity failure;
			assert memory(16#07D3#) = x"0000" and
				memory(16#07D4#) = x"0114" and
				memory(16#07D5#) = x"B008" and
				memory(16#07D7#) = x"0145" and
				memory(16#07DA#) = x"0000" and
				memory(16#07DB#) = x"4000"
				report "descriptor-read BERR frame context mismatch"
				severity failure;
			assert translated_data_cycle_seen = '0'
				report "operand cycle escaped a failed descriptor read"
				severity failure;
		else
			assert stack_write_count = 46 and table_fault_cycle_count = 1
				report "descriptor-update BERR did not produce one format-B fault"
				severity failure;
			assert memory(16#07D3#) = x"0000" and
				memory(16#07D4#) = x"0114" and
				memory(16#07D5#) = x"B008" and
				memory(16#07D7#) = x"0105" and
				memory(16#07DA#) = x"0000" and
				memory(16#07DB#) = x"4000"
				report "descriptor-update BERR frame context mismatch"
				severity failure;
			assert memory(16#0809#) = x"2001" and
				translated_data_cycle_seen = '0'
				report "failed descriptor update committed or operand cycle escaped"
				severity failure;
		end if;
		report "PASS: integrated MMU fault frame kind " &
			integer'image(FAULT_KIND) & " and bus order" severity note;
		stop;
		wait;
	end process;
end architecture;
