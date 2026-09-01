library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_mmu_fpu_fault_integration is
	generic(
		FAULT_KIND : natural range 0 to 5 := 0
	);
end entity;

architecture test of tb_tg68k_mmu_fpu_fault_integration is
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
		result(16#008A#) := x"7005";
		result(16#008B#) := x"F200";
		result(16#008C#) := x"4000";
		result(16#008D#) := x"207C";
		result(16#008E#) := x"0000";
		result(16#008F#) := x"4000";
		result(16#0090#) := x"F210";
		if FAULT_KIND = 0 or FAULT_KIND = 2 or FAULT_KIND = 4 then
			result(16#0091#) := x"4800";
		else
			result(16#0091#) := x"6800";
		end if;

		result(16#00C0#) := x"4E72";
		result(16#00C1#) := x"2700";

		result(16#0180#) := x"7FFF";
		result(16#0181#) := x"0002";
		result(16#0182#) := x"0000";
		result(16#0183#) := x"1000";
		result(16#0184#) := x"80CC";
		result(16#0185#) := x"8000";
		result(16#0800#) := x"0000";
		result(16#0801#) := x"0001";
		result(16#0808#) := x"2000";
		if FAULT_KIND = 0 then
			result(16#0809#) := x"0000";
		elsif FAULT_KIND = 1 then
			result(16#0809#) := x"0045";
		else
			result(16#0809#) := x"0041";
		end if;
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
	signal logical_address : std_logic_vector(31 downto 0);
	signal logical_access : std_logic;
	signal memory : memory_t := initial_memory;
	signal stack_write_count : natural range 0 to 46 := 0;
	signal table_fault_count : natural range 0 to 1 := 0;
	signal physical_operand_count : natural range 0 to 3 := 0;
	signal handler_fetch_seen : std_logic := '0';
begin
	clk <= not clk after CLK_PERIOD / 2;
	bus_error <= '1' when
		(FAULT_KIND = 2 and busstate = "10" and addr_out = x"00001010") or
		(FAULT_KIND = 3 and busstate = "11" and addr_out = x"00001012") or
		(FAULT_KIND = 4 and busstate = "10" and addr_out = x"20000004") or
		(FAULT_KIND = 5 and busstate = "11" and addr_out = x"20000004") else
		'0';

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
			MMU_enable => '1',
			FPU_enable => '1',
			addr_out => addr_out,
			data_write => data_write,
			nWr => nWr,
			nUDS => nUDS,
			nLDS => nLDS,
			busstate => busstate,
			longword => open,
			cache_inhibit => open,
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
				if word_address < MEMORY_WORDS then
					data_in <= memory(word_address);
				end if;
			elsif addr_out(31 downto 16) = x"2000" then
				case addr_out(3 downto 1) is
					when "000" => data_in <= x"4001";
					when "001" => data_in <= x"0000";
					when "010" => data_in <= x"A000";
					when others => data_in <= x"0000";
				end case;
			end if;
		end if;
	end process;

	bus_monitor : process(clk)
		variable word_address : natural;
		variable expected_address : unsigned(31 downto 0);
	begin
		if rising_edge(clk) and nReset = '1' and busstate /= "01" and
				not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if busstate = "11" and unsigned(addr_out) >=
					to_unsigned(16#0FA4#, 32) and addr_out <= x"00000FFE" then
				expected_address := to_unsigned(16#0FFE#, 32) -
					to_unsigned(stack_write_count * 2, 32);
				assert unsigned(addr_out) = expected_address and fc = "101"
					report "combined FPU fault-frame bus order mismatch"
					severity failure;
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
				stack_write_count <= stack_write_count + 1;
			elsif addr_out(31 downto 16) = x"2000" then
				assert logical_access = '1' and
					logical_address = std_logic_vector(unsigned'(x"00004000") +
						to_unsigned(physical_operand_count * 2, 32)) and
					fc = "101" and nUDS = '0' and nLDS = '0'
					report "faulting translated FPU cycle attributes mismatch"
					severity failure;
				physical_operand_count <= physical_operand_count + 1;
			elsif bus_error = '1' and addr_out(31 downto 12) = x"00001" then
				table_fault_count <= table_fault_count + 1;
			elsif busstate = "11" and addr_out(31 downto 12) = x"00001" and
					bus_error = '0' then
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
			end if;

			if busstate = "00" and addr_out = x"00000180" then
				handler_fetch_seen <= '1';
			end if;
		end if;
	end process;

	stimulus : process
		variable expected_ssw : std_logic_vector(15 downto 0);
		variable expected_fault_address : std_logic_vector(31 downto 0);
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 5000 loop
			wait until rising_edge(clk);
			exit when handler_fetch_seen = '1';
		end loop;
		assert handler_fetch_seen = '1' and stack_write_count = 46
			report "combined FPU fault did not enter vector 2" severity failure;
		if FAULT_KIND = 0 or FAULT_KIND = 2 or FAULT_KIND = 4 then
			expected_ssw := x"0165";
		else
			expected_ssw := x"0125";
		end if;
		if FAULT_KIND >= 4 then
			expected_fault_address := x"00004004";
		else
			expected_fault_address := x"00004000";
		end if;
		assert memory(16#07D2#) = x"2700" and
			memory(16#07D3#) = x"0000" and
			memory(16#07D4#) = x"0120" and
			memory(16#07D5#) = x"B008" and
			memory(16#07D7#) = expected_ssw and
			memory(16#07DA#) = expected_fault_address(31 downto 16) and
			memory(16#07DB#) = expected_fault_address(15 downto 0)
			report "combined FPU format-B frame context mismatch"
			severity failure;
		if FAULT_KIND = 1 or FAULT_KIND = 3 then
			assert memory(16#07DE#) = x"0000" and
				memory(16#07DF#) = x"4001"
				report "translation-fault FPU output buffer mismatch"
				severity failure;
		elsif FAULT_KIND = 5 then
			assert memory(16#07DE#) = x"0000" and
				memory(16#07DF#) = x"A000"
				report "physical-fault FPU output buffer mismatch"
				severity failure;
		end if;
		if FAULT_KIND <= 3 then
			assert physical_operand_count = 0
				report "FPU operand cycle escaped translation failure"
				severity failure;
		else
			assert physical_operand_count = 3
				report "translated physical FPU fault cycle count mismatch"
				severity failure;
		end if;
		if FAULT_KIND = 2 or FAULT_KIND = 3 then
			assert table_fault_count = 1
				report "FPU table-walk fault count mismatch" severity failure;
		else
			assert table_fault_count = 0
				report "unexpected FPU table-walk bus error" severity failure;
		end if;
		report "PASS: combined MMU/FPU fault kind " & integer'image(FAULT_KIND)
			severity note;
		stop;
		wait;
	end process;
end architecture;
