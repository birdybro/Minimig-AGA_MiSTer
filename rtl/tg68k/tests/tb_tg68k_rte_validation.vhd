library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_rte_validation is
generic(
	VALIDATION_KIND : natural range 0 to 10 := 0
);
end entity;

architecture test of tb_tg68k_rte_validation is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;
	constant FRAME_BASE : natural := 16#1000#;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);
	type format_code_array_t is array (0 to 9) of natural range 0 to 15;
	constant ILLEGAL_FORMAT_CODES : format_code_array_t :=
		(3, 4, 5, 6, 7, 8, 12, 13, 14, 15);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(0) := x"0000";
		result(1) := std_logic_vector(to_unsigned(FRAME_BASE, 16));
		result(2) := x"0000";
		result(3) := x"0100";
		result(16#001C#) := x"0000";
		result(16#001D#) := x"0180";

		result(16#0080#) := x"4E73";
		result(16#0081#) := x"4E72";
		result(16#0082#) := x"2700";

		result(16#00C0#) := x"23FC";
		result(16#00C1#) := x"CAFE";
		result(16#00C2#) := x"BABE";
		result(16#00C3#) := x"0000";
		result(16#00C4#) := x"0200";
		result(16#00C5#) := x"4E72";
		result(16#00C6#) := x"2700";

		result(FRAME_BASE / 2) := x"2700";
		result((FRAME_BASE / 2) + 1) := x"0000";
		result((FRAME_BASE / 2) + 2) := x"0200";
		if VALIDATION_KIND <= ILLEGAL_FORMAT_CODES'high then
			result((FRAME_BASE / 2) + 3) := std_logic_vector(to_unsigned(
				ILLEGAL_FORMAT_CODES(VALIDATION_KIND), 4)) & x"000";
		else
			result((FRAME_BASE / 2) + 3) := x"B000";
			result((FRAME_BASE / 2) + 27) := x"1000";
		end if;
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
	signal memory : memory_t := initial_memory;
	signal frame_write_count : natural := 0;
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
			FC => open,
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
	begin
		if rising_edge(clk) and nreset = '1' and busstate = "11" and
				not is_x(addr_out) and addr_out(31 downto 16) = x"0000" then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if word_address < MEMORY_WORDS then
				if unsigned(addr_out) >= to_unsigned(FRAME_BASE - 8, 32) and
						unsigned(addr_out) < to_unsigned(FRAME_BASE, 32) then
					frame_write_count <= frame_write_count + 1;
				end if;
				if nuds = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nlds = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
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
			report "RTE validation did not enter the format-error handler"
			severity failure;
		assert frame_write_count = 4
			report "format error did not create one four-word frame"
			severity failure;
		assert memory((FRAME_BASE / 2) - 4) = x"2700" and
			memory((FRAME_BASE / 2) - 3) = x"0000" and
			memory((FRAME_BASE / 2) - 2) = x"0100" and
			memory((FRAME_BASE / 2) - 1) = x"0038"
			report "format-error exception frame mismatch" severity failure;
		assert memory(FRAME_BASE / 2) = x"2700" and
			memory((FRAME_BASE / 2) + 1) = x"0000" and
			memory((FRAME_BASE / 2) + 2) = x"0200"
			report "RTE validation changed the rejected frame" severity failure;
		if VALIDATION_KIND <= ILLEGAL_FORMAT_CODES'high then
			assert memory((FRAME_BASE / 2) + 3) = std_logic_vector(to_unsigned(
				ILLEGAL_FORMAT_CODES(VALIDATION_KIND), 4)) & x"000"
				report "illegal format word changed" severity failure;
		else
			assert memory((FRAME_BASE / 2) + 3) = x"B000" and
				memory((FRAME_BASE / 2) + 27) = x"1000"
				report "version-mismatched frame changed" severity failure;
		end if;
		report "PASS: MC68030 RTE frame validation kind " &
			integer'image(VALIDATION_KIND) severity note;
		stop;
		wait;
	end process;
end architecture;
