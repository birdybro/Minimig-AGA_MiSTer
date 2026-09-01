library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_wrapper is
end entity;

architecture test of tb_tg68k_fpu_wrapper is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(16#0000#) := x"0000";
		result(16#0001#) := x"1000";
		result(16#0002#) := x"0000";
		result(16#0003#) := x"0100";
		result(16#0080#) := x"7405";
		result(16#0081#) := x"F202";
		result(16#0082#) := x"4180";
		result(16#0083#) := x"F200";
		result(16#0084#) := x"0E00";
		result(16#0085#) := x"207C";
		result(16#0086#) := x"0000";
		result(16#0087#) := x"0300";
		result(16#0088#) := x"F210";
		result(16#0089#) := x"6600";
		result(16#008A#) := x"F210";
		result(16#008B#) := x"4700";
		result(16#008C#) := x"F201";
		result(16#008D#) := x"6700";
		result(16#008E#) := x"23C1";
		result(16#008F#) := x"0000";
		result(16#0090#) := x"0200";
		result(16#0091#) := x"227C";
		result(16#0092#) := x"0000";
		result(16#0093#) := x"0400";
		result(16#0094#) := x"F219";
		result(16#0095#) := x"6980";
		result(16#0096#) := x"F221";
		result(16#0097#) := x"4A80";
		result(16#0098#) := x"F200";
		result(16#0099#) := x"6680";
		result(16#009A#) := x"23C9";
		result(16#009B#) := x"0000";
		result(16#009C#) := x"0204";
		result(16#009D#) := x"23C0";
		result(16#009E#) := x"0000";
		result(16#009F#) := x"0208";
		result(16#00A0#) := x"4E72";
		result(16#00A1#) := x"2700";
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
	signal logical_address : std_logic_vector(31 downto 0);
	signal logical_access : std_logic;
	signal memory : memory_t := initial_memory;
	signal result_write_count : natural range 0 to 2 := 0;
	signal fpu_memory_transfer_count : natural range 0 to 4 := 0;
	signal extended_transfer_count : natural range 0 to 12 := 0;
	signal extended_result_write_count : natural range 0 to 4 := 0;
	signal post_fpu_fetch : std_logic := '0';
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
			logical_bus_address => logical_address,
			logical_bus_access => logical_access,
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
			if busstate /= "01" and
					(addr_out = x"00000300" or addr_out = x"00000302") then
				assert logical_access = '1' and logical_address = addr_out
					report "FPU memory cycle lost its logical bus address"
					severity failure;
				fpu_memory_transfer_count <= fpu_memory_transfer_count + 1;
			end if;
			if busstate /= "01" and unsigned(addr_out) >= unsigned'(x"00000400") and
					unsigned(addr_out) <= unsigned'(x"0000040A") then
				extended_transfer_count <= extended_transfer_count + 1;
			end if;
			if busstate = "11" and not is_x(addr_out) then
				word_address := to_integer(unsigned(addr_out(13 downto 1)));
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
				if addr_out = x"00000200" or addr_out = x"00000202" then
					result_write_count <= result_write_count + 1;
				end if;
				if addr_out = x"00000204" or addr_out = x"00000206" or
						addr_out = x"00000208" or addr_out = x"0000020A" then
					extended_result_write_count <= extended_result_write_count + 1;
				end if;
			end if;
			if busstate = "00" and addr_out = x"00000140" then
				post_fpu_fetch <= '1';
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 520 loop
			wait until rising_edge(clk);
			exit when result_write_count = 2 and
				extended_result_write_count = 4 and post_fpu_fetch = '1';
		end loop;
		assert result_write_count = 2 and memory(16#0100#) = x"40A0" and
			memory(16#0101#) = x"0000"
			report "TG68K FPU instruction stream result mismatch: " &
				to_hstring(memory(16#0100#)) & to_hstring(memory(16#0101#))
			severity failure;
		assert post_fpu_fetch = '1'
			report "TG68K did not retire the FPU instruction stream" severity failure;
		assert fpu_memory_transfer_count = 4 and
			memory(16#0180#) = x"40A0" and memory(16#0181#) = x"0000"
			report "TG68K FPU memory transfer sequence mismatch" severity failure;
		assert extended_transfer_count = 12 and
			memory(16#0102#) = x"0000" and memory(16#0103#) = x"0400" and
			memory(16#0104#) = x"40A0" and memory(16#0105#) = x"0000"
			report "TG68K FPU extended predecrement/postincrement mismatch: cycles=" &
				integer'image(extended_transfer_count) & " A1=" &
				to_hstring(memory(16#0102#)) & to_hstring(memory(16#0103#)) &
				" result=" & to_hstring(memory(16#0104#)) &
				to_hstring(memory(16#0105#))
			severity failure;
		report "PASS: TG68K instruction-level FPU FMOVE and EA updates"
			severity note;
		stop;
	end process;
end architecture;
