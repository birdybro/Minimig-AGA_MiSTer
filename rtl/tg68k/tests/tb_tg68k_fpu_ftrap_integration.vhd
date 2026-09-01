library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_ftrap_integration is
	generic(
		TRAP_MODE : natural range 0 to 2 := 0
	);
end entity;

architecture test of tb_tg68k_fpu_ftrap_integration is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 4096;
	constant NEXT_PC : natural := 16#010E# + TRAP_MODE * 2;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
		variable fallthrough_index : natural;
	begin
		result(0) := x"0000";
		result(1) := x"1000";
		result(2) := x"0000";
		result(3) := x"0100";
		result(14) := x"0000";
		result(15) := x"0400";

		result(16#0080#) := x"203C";
		result(16#0081#) := x"4000";
		result(16#0082#) := x"0000";
		result(16#0083#) := x"F200";
		result(16#0084#) := x"8800";
		case TRAP_MODE is
			when 0 => result(16#0085#) := x"F27C";
			when 1 => result(16#0085#) := x"F27A";
			when others => result(16#0085#) := x"F27B";
		end case;
		result(16#0086#) := x"0001";
		fallthrough_index := 16#0087#;
		if TRAP_MODE >= 1 then
			result(fallthrough_index) := x"A55A";
			fallthrough_index := fallthrough_index + 1;
		end if;
		if TRAP_MODE = 2 then
			result(fallthrough_index) := x"5AA5";
			fallthrough_index := fallthrough_index + 1;
		end if;
		result(fallthrough_index) := x"70EE";
		result(fallthrough_index + 1) := x"23C0";
		result(fallthrough_index + 2) := x"0000";
		result(fallthrough_index + 3) := x"0300";
		result(fallthrough_index + 4) := x"4E72";
		result(fallthrough_index + 5) := x"2700";

		result(16#0200#) := x"23CF";
		result(16#0201#) := x"0000";
		result(16#0202#) := x"0304";
		result(16#0203#) := x"7001";
		result(16#0204#) := x"23C0";
		result(16#0205#) := x"0000";
		result(16#0206#) := x"0300";
		result(16#0207#) := x"4E72";
		result(16#0208#) := x"2700";
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
					report "FTRAPcc test wrote outside memory" severity failure;
				if addr_out(31 downto 4) = x"00000FF" then
					assert fc = "101"
						report "FTRAPcc frame used incorrect function code"
						severity failure;
				end if;
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
			elsif busstate = "10" and
					(addr_out = x"0000001C" or addr_out = x"0000001E") then
				vector_fetch_count <= vector_fetch_count + 1;
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 1000 loop
			wait until rising_edge(clk);
			if memory(16#0180#) = x"0000" and
					memory(16#0181#) = x"0001" then
				wait until rising_edge(clk);
				assert memory(16#0182#) = x"0000" and
					memory(16#0183#) = x"0FF4"
					report "FTRAPcc handler observed incorrect stack pointer"
					severity failure;
				assert memory(16#07FA#) = x"2700" and
					memory(16#07FB#) = x"0000" and
					to_integer(unsigned(memory(16#07FC#))) = NEXT_PC and
					memory(16#07FD#) = x"201C" and
					memory(16#07FE#) = x"0000" and
					memory(16#07FF#) = x"010A"
					report "FTRAPcc format-2 exception frame mismatch"
					severity failure;
				assert vector_fetch_count = 2
					report "FTRAPcc did not fetch vector 7" severity failure;
				report "PASS: true FTRAPcc vector and format-2 frame, mode " &
					integer'image(TRAP_MODE)
					severity note;
				stop;
			end if;
		end loop;
		assert false report "true FTRAPcc integration timed out"
			severity failure;
		wait;
	end process;
end architecture;
