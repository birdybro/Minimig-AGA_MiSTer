library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_busy_frame_integration is
end entity;

architecture test of tb_tg68k_fpu_busy_frame_integration is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);
	type address_trace_t is array (0 to 5) of std_logic_vector(31 downto 0);
	type word_trace_t is array (0 to 5) of std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";
		result(4) := x"0000";
		result(5) := x"0200";

		result(16#0080#) := x"7005";
		result(16#0081#) := x"F200";
		result(16#0082#) := x"4000";
		result(16#0083#) := x"207C";
		result(16#0084#) := x"0000";
		result(16#0085#) := x"0300";
		result(16#0086#) := x"F210";
		result(16#0087#) := x"6800";
		result(16#0088#) := x"23FC";
		result(16#0089#) := x"0000";
		result(16#008A#) := x"0001";
		result(16#008B#) := x"0000";
		result(16#008C#) := x"0400";
		result(16#008D#) := x"4E72";
		result(16#008E#) := x"2700";

		result(16#0100#) := x"227C";
		result(16#0101#) := x"0000";
		result(16#0102#) := x"06D8";
		result(16#0103#) := x"F321";
		result(16#0104#) := x"7009";
		result(16#0105#) := x"F200";
		result(16#0106#) := x"4000";
		result(16#0107#) := x"F359";
		result(16#0108#) := x"4E73";
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
	signal bus_error : std_logic;
	signal fault_seen : std_logic := '0';
	signal fault_count : natural range 0 to 1 := 0;
	signal memory : memory_t := initial_memory;
	signal stack_write_count : natural range 0 to 46 := 0;
	signal stack_read_count : natural range 0 to 46 := 0;
	signal save_write_count : natural range 0 to 108 := 0;
	signal restore_read_count : natural range 0 to 108 := 0;
	signal operand_write_count : natural range 0 to 6 := 0;
	signal operand_addresses : address_trace_t :=
		(others => (others => '0'));
	signal operand_words : word_trace_t := (others => (others => '0'));
begin
	clk <= not clk after CLK_PERIOD / 2;
	bus_error <= '1' when fault_seen = '0' and busstate = "11" and
		addr_out = x"00000304" else '0';

	dut : entity work.TG68KdotC_MMU
		port map(
			clk => clk,
			nReset => nReset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => bus_error,
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
		variable sequence_index : natural;
		variable frame_word_index : natural;
	begin
		if rising_edge(clk) and nReset = '1' and busstate /= "01" and
				not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if bus_error = '1' then
				assert addr_out = x"00000304" and fc = "101" and
					nUDS = '0' and nLDS = '0'
					report "faulted FPU operand bus attributes mismatch"
					severity failure;
				fault_seen <= '1';
				fault_count <= fault_count + 1;
			elsif busstate = "11" and word_address < MEMORY_WORDS then
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
				if fault_seen = '1' and stack_write_count < 46 and
						unsigned(addr_out) >= to_unsigned(16#0FA4#, 32) and
						addr_out <= x"00000FFE" then
					expected_address := to_unsigned(16#0FFE#, 32) -
						to_unsigned(stack_write_count * 2, 32);
					assert unsigned(addr_out) = expected_address and fc = "101"
						report "FPU fault-frame write order mismatch: got " &
							to_hstring(addr_out) & " expected " &
							to_hstring(std_logic_vector(expected_address)) &
							" count " & integer'image(stack_write_count)
						severity failure;
					stack_write_count <= stack_write_count + 1;
				elsif unsigned(addr_out) >= to_unsigned(16#0600#, 32) and
						unsigned(addr_out) < to_unsigned(16#06D8#, 32) then
					sequence_index := save_write_count;
					if sequence_index < 2 then
						frame_word_index := sequence_index;
					else
						frame_word_index := (53 - (sequence_index - 2) / 2) * 2 +
							(sequence_index mod 2);
					end if;
					expected_address := to_unsigned(16#0600#, 32) +
						to_unsigned(frame_word_index * 2, 32);
					assert unsigned(addr_out) = expected_address and fc = "101"
						report "busy FSAVE bus order mismatch" severity failure;
					save_write_count <= save_write_count + 1;
				elsif unsigned(addr_out) >= to_unsigned(16#0300#, 32) and
						unsigned(addr_out) < to_unsigned(16#030C#, 32) then
					operand_addresses(operand_write_count) <= addr_out;
					operand_words(operand_write_count) <= data_write;
					operand_write_count <= operand_write_count + 1;
				end if;
			elsif busstate = "10" then
				if fault_seen = '1' and
						unsigned(addr_out) >= to_unsigned(16#0FA4#, 32) and
						addr_out <= x"00000FFE" then
					expected_address := to_unsigned(16#0FA4#, 32) +
						to_unsigned(stack_read_count * 2, 32);
					assert unsigned(addr_out) = expected_address and fc = "101"
						report "FPU fault-frame RTE read order mismatch"
						severity failure;
					stack_read_count <= stack_read_count + 1;
				elsif unsigned(addr_out) >= to_unsigned(16#0600#, 32) and
						unsigned(addr_out) < to_unsigned(16#06D8#, 32) then
					expected_address := to_unsigned(16#0600#, 32) +
						to_unsigned(restore_read_count * 2, 32);
					assert unsigned(addr_out) = expected_address and fc = "101"
						report "busy FRESTORE bus order mismatch" severity failure;
					restore_read_count <= restore_read_count + 1;
				end if;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 30000 loop
			wait until rising_edge(clk);
			exit when memory(16#0200#) = x"0000" and
				memory(16#0201#) = x"0001";
		end loop;
		assert memory(16#0200#) = x"0000" and
			memory(16#0201#) = x"0001"
			report "busy-frame fault handler did not resume the FPU instruction"
			severity failure;
		assert fault_count = 1 and stack_write_count = 46 and
			stack_read_count = 46
			report "FPU operand fault-frame transfer count mismatch"
			severity failure;
		assert memory(16#07D2#) = x"2700" and
			memory(16#07D3#) = x"0000" and
			memory(16#07D4#) = x"010C" and
			memory(16#07D5#) = x"B008" and
			memory(16#07D7#) = x"0125" and
			memory(16#07DA#) = x"0000" and
			memory(16#07DB#) = x"0304" and
			memory(16#07DE#) = x"0000" and
			memory(16#07DF#) = x"A000"
			report "FPU operand format-B exception frame mismatch"
			severity failure;
		assert save_write_count = 108 and restore_read_count = 108 and
			memory(16#0300#) = x"1FD4" and
			memory(16#0301#) = x"0000"
			report "busy state-frame transfer count or format mismatch"
			severity failure;
		assert operand_write_count = 6
			report "resumed FPU operand transfer count mismatch" severity failure;
		for index in 0 to 5 loop
			assert operand_addresses(index) = std_logic_vector(
				to_unsigned(16#0300# + index * 2, 32))
				report "resumed FPU operand address sequence mismatch"
				severity failure;
		end loop;
		assert operand_words(0) = x"4001" and
			operand_words(1) = x"0000" and operand_words(2) = x"A000" and
			operand_words(3) = x"0000" and operand_words(4) = x"0000" and
			operand_words(5) = x"0000"
			report "busy frame did not preserve the suspended FPU source"
			severity failure;
		report "PASS: FPU format-B fault, busy FSAVE/FRESTORE, and RTE resume"
			severity note;
		stop;
		wait;
	end process;
end architecture;
