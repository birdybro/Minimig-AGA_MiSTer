library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_bsun_integration is
end entity;

architecture test of tb_tg68k_fpu_bsun_integration is
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
		result(16#0060#) := x"0000";
		result(16#0061#) := x"0500";

		result(16#0080#) := x"203C";
		result(16#0081#) := x"0000";
		result(16#0082#) := x"8000";
		result(16#0083#) := x"F200";
		result(16#0084#) := x"9000";
		result(16#0085#) := x"203C";
		result(16#0086#) := x"1000";
		result(16#0087#) := x"0000";
		result(16#0088#) := x"F200";
		result(16#0089#) := x"8800";
		result(16#008A#) := x"223C";
		result(16#008B#) := x"1234";
		result(16#008C#) := x"5678";
		result(16#008D#) := x"F241";
		result(16#008E#) := x"0011";
		result(16#008F#) := x"70EE";
		result(16#0090#) := x"23C0";
		result(16#0091#) := x"0000";
		result(16#0092#) := x"0300";
		result(16#0093#) := x"4E72";
		result(16#0094#) := x"2700";

		result(16#0280#) := x"23CF";
		result(16#0281#) := x"0000";
		result(16#0282#) := x"0314";
		result(16#0283#) := x"F202";
		result(16#0284#) := x"A800";
		result(16#0285#) := x"23C2";
		result(16#0286#) := x"0000";
		result(16#0287#) := x"0304";
		result(16#0288#) := x"F203";
		result(16#0289#) := x"A400";
		result(16#028A#) := x"23C3";
		result(16#028B#) := x"0000";
		result(16#028C#) := x"0308";
		result(16#028D#) := x"23C1";
		result(16#028E#) := x"0000";
		result(16#028F#) := x"030C";
		result(16#0290#) := x"7001";
		result(16#0291#) := x"23C0";
		result(16#0292#) := x"0000";
		result(16#0293#) := x"0300";
		result(16#0294#) := x"4E72";
		result(16#0295#) := x"2700";
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
					report "BSUN test wrote outside memory" severity failure;
				if addr_out(31 downto 4) = x"00000FF" then
					assert fc = "101"
						report "BSUN frame used incorrect function code"
						severity failure;
				end if;
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
			elsif busstate = "10" and
					(addr_out = x"000000C0" or addr_out = x"000000C2") then
				vector_fetch_count <= vector_fetch_count + 1;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 1500 loop
			wait until rising_edge(clk);
			if memory(16#0180#) = x"0000" and
					memory(16#0181#) = x"0001" then
				wait until rising_edge(clk);
				assert memory(16#018A#) = x"0000" and
					memory(16#018B#) = x"0FF8"
					report "BSUN handler observed incorrect stack pointer"
					severity failure;
				assert memory(16#07FC#) = x"2700" and
					memory(16#07FD#) = x"0000" and
					memory(16#07FE#) = x"011A" and
					memory(16#07FF#) = x"00C0"
					report "BSUN format-0 exception frame mismatch"
					severity failure;
				assert memory(16#0182#) = x"1000" and
					memory(16#0183#) = x"8080"
					report "BSUN FPSR status/accrual mismatch" severity failure;
				assert memory(16#0184#) = x"0000" and
					memory(16#0185#) = x"011A"
					report "BSUN FPIAR mismatch" severity failure;
				assert memory(16#0186#) = x"1234" and
					memory(16#0187#) = x"5678"
					report "enabled BSUN did not suppress FScc destination"
					severity failure;
				assert vector_fetch_count = 2
					report "BSUN did not fetch vector 48" severity failure;
				report "PASS: enabled BSUN pre-instruction exception state and frame"
					severity note;
				stop;
			end if;
		end loop;
		assert false report "enabled BSUN integration timed out"
			severity failure;
		wait;
	end process;
end architecture;
