library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_state_frame_integration is
	generic(
		FRAME_MODE : natural range 0 to 2 := 0
	);
end entity;

architecture test of tb_tg68k_fpu_state_frame_integration is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 4096;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);
	type address_trace_t is array (0 to 33) of std_logic_vector(31 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";
		if FRAME_MODE = 1 then
			result(16#0010#) := x"0000";
			result(16#0011#) := x"0500";
		else
			result(16#001C#) := x"0000";
			result(16#001D#) := x"0500";
		end if;

		if FRAME_MODE = 0 then
			result(16#0080#) := x"207C";
			result(16#0081#) := x"0000";
			result(16#0082#) := x"0600";
			result(16#0083#) := x"F310";
			result(16#0084#) := x"7005";
			result(16#0085#) := x"F200";
			result(16#0086#) := x"4000";
			result(16#0087#) := x"227C";
			result(16#0088#) := x"0000";
			result(16#0089#) := x"0700";
			result(16#008A#) := x"F321";
			result(16#008B#) := x"23C9";
			result(16#008C#) := x"0000";
			result(16#008D#) := x"0304";
			result(16#008E#) := x"F350";
			result(16#008F#) := x"247C";
			result(16#0090#) := x"0000";
			result(16#0091#) := x"0800";
			result(16#0092#) := x"F312";
			result(16#0093#) := x"7001";
			result(16#0094#) := x"23C0";
			result(16#0095#) := x"0000";
			result(16#0096#) := x"0300";
			result(16#0097#) := x"4E72";
			result(16#0098#) := x"2700";
		elsif FRAME_MODE = 1 then
			result(16#0080#) := x"207C";
			result(16#0081#) := x"0000";
			result(16#0082#) := x"0600";
			result(16#0083#) := x"027C";
			result(16#0084#) := x"DFFF";
			result(16#0085#) := x"F310";
		else
			result(16#0080#) := x"207C";
			result(16#0081#) := x"0000";
			result(16#0082#) := x"0600";
			result(16#0083#) := x"F358";
			result(16#0300#) := x"2A38";
			result(16#0301#) := x"0000";
		end if;

		if FRAME_MODE /= 0 then
			result(16#0280#) := x"23CF";
			result(16#0281#) := x"0000";
			result(16#0282#) := x"0308";
			result(16#0283#) := x"23C8";
			result(16#0284#) := x"0000";
			result(16#0285#) := x"0304";
			result(16#0286#) := x"7001";
			result(16#0287#) := x"23C0";
			result(16#0288#) := x"0000";
			result(16#0289#) := x"0300";
			result(16#028A#) := x"4E72";
			result(16#028B#) := x"2700";
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
	signal memory : memory_t := initial_memory;
	signal frame_write_count : natural range 0 to 34 := 0;
	signal frame_write_addresses : address_trace_t :=
		(others => (others => '0'));
	signal vector_fetch_count : natural range 0 to 2 := 0;
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

	memory_access : process(clk)
		variable word_address : natural;
	begin
		if rising_edge(clk) and nReset = '1' and not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(12 downto 1)));
			if busstate = "11" then
				assert word_address < MEMORY_WORDS
					report "state-frame test wrote outside memory" severity failure;
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
				if FRAME_MODE = 0 and
						((unsigned(addr_out) >= to_unsigned(16#0600#, 32) and
						  unsigned(addr_out) < to_unsigned(16#0700#, 32)) or
						 (unsigned(addr_out) >= to_unsigned(16#0800#, 32) and
						  unsigned(addr_out) < to_unsigned(16#083C#, 32))) then
					assert fc = "101"
						report "state-frame write used incorrect function code"
						severity failure;
					frame_write_addresses(frame_write_count) <= addr_out;
					frame_write_count <= frame_write_count + 1;
				end if;
			elsif busstate = "10" and FRAME_MODE /= 0 then
				if (FRAME_MODE = 1 and
						(addr_out = x"00000020" or addr_out = x"00000022")) or
						(FRAME_MODE = 2 and
						(addr_out = x"00000038" or addr_out = x"0000003A")) then
					vector_fetch_count <= vector_fetch_count + 1;
				end if;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 2500 loop
			wait until rising_edge(clk);
			if memory(16#0180#) = x"0000" and
					memory(16#0181#) = x"0001" then
				wait until rising_edge(clk);
				if FRAME_MODE = 0 then
					assert memory(16#0182#) = x"0000" and
						memory(16#0183#) = x"06C4"
						report "FSAVE predecrement address update mismatch"
						severity failure;
					assert memory(16#0300#) = x"0000" and
						memory(16#0301#) = x"0000" and
						memory(16#0362#) = x"1F38" and
						memory(16#0363#) = x"0000" and
						memory(16#037E#) = x"7C0E" and
						memory(16#037F#) = x"FFFF" and
						memory(16#0400#) = x"0000" and
						memory(16#0401#) = x"0000"
						report "TG68K FSAVE/FRESTORE frame contents mismatch"
						severity failure;
					assert frame_write_count = 34 and
						frame_write_addresses(0) = x"00000600" and
						frame_write_addresses(1) = x"00000602" and
						frame_write_addresses(2) = x"000006C4" and
						frame_write_addresses(3) = x"000006C6" and
						frame_write_addresses(4) = x"000006FC" and
						frame_write_addresses(5) = x"000006FE" and
						frame_write_addresses(30) = x"000006C8" and
						frame_write_addresses(31) = x"000006CA" and
						frame_write_addresses(32) = x"00000800" and
						frame_write_addresses(33) = x"00000802"
						report "TG68K state-frame bus order mismatch"
						severity failure;
					report "PASS: TG68K null/idle FSAVE and null FRESTORE"
						severity note;
				elsif FRAME_MODE = 1 then
					assert memory(16#0182#) = x"0000" and
						memory(16#0183#) = x"0600" and
						memory(16#0184#) = x"0000" and
						memory(16#0185#) = x"0FF8"
						report "FSAVE privilege handler state mismatch"
						severity failure;
					assert memory(16#07FC#) = x"0700" and
						memory(16#07FD#) = x"0000" and
						memory(16#07FE#) = x"010A" and
						memory(16#07FF#) = x"0020"
						report "FSAVE privilege exception frame mismatch: " &
							to_hstring(memory(16#07FC#)) & " " &
							to_hstring(memory(16#07FD#)) & " " &
							to_hstring(memory(16#07FE#)) & " " &
							to_hstring(memory(16#07FF#))
						severity failure;
					assert memory(16#0300#) = x"4E71" and
						vector_fetch_count = 2
						report "FSAVE privilege exception side effect mismatch"
						severity failure;
					report "PASS: TG68K FSAVE privilege exception"
						severity note;
				else
					assert memory(16#0182#) = x"0000" and
						memory(16#0183#) = x"0600" and
						memory(16#0184#) = x"0000" and
						memory(16#0185#) = x"0FF8"
						report "FRESTORE format handler state mismatch"
						severity failure;
					assert memory(16#07FC#) = x"2700" and
						memory(16#07FD#) = x"0000" and
						memory(16#07FE#) = x"0106" and
						memory(16#07FF#) = x"0038"
						report "FRESTORE format exception frame mismatch: " &
							to_hstring(memory(16#07FC#)) & " " &
							to_hstring(memory(16#07FD#)) & " " &
							to_hstring(memory(16#07FE#)) & " " &
							to_hstring(memory(16#07FF#))
						severity failure;
					assert vector_fetch_count = 2
						report "FRESTORE did not fetch vector 14" severity failure;
					report "PASS: TG68K FRESTORE format exception"
						severity note;
				end if;
				stop;
			end if;
		end loop;
		assert false report "TG68K state-frame integration timed out: bus=" &
			to_hstring(addr_out) & " state=" & to_hstring(busstate) &
			" writes=" & integer'image(frame_write_count) &
			" marker=" & to_hstring(memory(16#0181#)) &
			" A1=" & to_hstring(memory(16#0183#))
			severity failure;
		wait;
	end process;
end architecture;
