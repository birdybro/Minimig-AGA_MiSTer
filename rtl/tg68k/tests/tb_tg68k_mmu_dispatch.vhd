library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_mmu_dispatch is
end entity;

architecture test of tb_tg68k_mmu_dispatch is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 4096;
	type memory_t is array (0 to MEMORY_WORDS - 1) of std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(16#0000#) := x"0000";
		result(16#0001#) := x"1000";
		result(16#0002#) := x"0000";
		result(16#0003#) := x"0100";

		result(16#0080#) := x"F000";
		result(16#0081#) := x"2400";
		result(16#0082#) := x"207C";
		result(16#0083#) := x"0000";
		result(16#0084#) := x"0200";
		result(16#0085#) := x"F010";
		result(16#0086#) := x"0800";
		result(16#0087#) := x"F010";
		result(16#0088#) := x"9F71";
		result(16#0089#) := x"F013";
		result(16#008A#) := x"0800";
		result(16#008B#) := x"7001";
		result(16#008C#) := x"4E72";
		result(16#008D#) := x"2700";
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
	signal memory : memory_t := initial_memory;

	signal mmu_match : std_logic;
	signal mmu_valid : std_logic;
	signal mmu_requires_ea : std_logic;
	signal mmu_busy : std_logic := '0';
	signal mmu_done : std_logic := '0';
	signal mmu_address_write : std_logic := '0';
	signal mmu_address_select : std_logic_vector(2 downto 0) := "000";
	signal mmu_address_data : std_logic_vector(31 downto 0) := (others => '0');
	signal mmu_fc_select : std_logic_vector(2 downto 0) := "000";
	signal mmu_start : std_logic;
	signal mmu_opcode : std_logic_vector(15 downto 0);
	signal mmu_extension : std_logic_vector(15 downto 0);
	signal mmu_supervisor : std_logic;
	signal mmu_effective_address : std_logic_vector(31 downto 0);
	signal mmu_fc_data : std_logic_vector(2 downto 0);
	signal mmu_sfc : std_logic_vector(2 downto 0);
	signal mmu_dfc : std_logic_vector(2 downto 0);
	signal command_delay : natural range 0 to 3 := 0;
	signal command_count : natural range 0 to 4 := 0;
	signal post_mmu_fetch_seen : std_logic := '0';
begin
	clk <= not clk after CLK_PERIOD / 2;

	mmu_match <= '1' when mmu_opcode(15 downto 6) = "1111000000" else '0';
	mmu_valid <= '1' when mmu_extension = x"2400" or
		mmu_extension = x"0800" or mmu_extension = x"9F71" else '0';
	mmu_requires_ea <= '0' when mmu_extension = x"2400" else '1';

	dut : entity work.TG68KdotC_Kernel
		port map(
			clk => clk,
			nReset => nReset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => '0',
			CPU => "11",
			addr_out => addr_out,
			data_write => data_write,
			nWr => nWr,
			nUDS => nUDS,
			nLDS => nLDS,
			busstate => busstate,
			longword => open,
			nResetOut => open,
			FC => open,
			clr_berr => open,
			MMU_enable => '1',
			MMU_instruction_match => mmu_match,
			MMU_instruction_valid => mmu_valid,
			MMU_instruction_requires_ea => mmu_requires_ea,
			MMU_instruction_busy => mmu_busy,
			MMU_instruction_done => mmu_done,
			MMU_unimplemented_exception => '0',
			MMU_privilege_exception => '0',
			MMU_bus_error_exception => '0',
			MMU_configuration_exception => '0',
			MMU_address_register_write => mmu_address_write,
			MMU_address_register_select => mmu_address_select,
			MMU_address_register_data => mmu_address_data,
			MMU_fc_data_register_select => mmu_fc_select,
			MMU_instruction_start => mmu_start,
			MMU_opcode => mmu_opcode,
			MMU_extension_word => mmu_extension,
			MMU_supervisor => mmu_supervisor,
			MMU_effective_address => mmu_effective_address,
			MMU_fc_data_register_value => mmu_fc_data,
			MMU_SFC => mmu_sfc,
			MMU_DFC => mmu_dfc,
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

	mmu_model : process(clk)
	begin
		if rising_edge(clk) then
			mmu_done <= '0';
			mmu_address_write <= '0';
			if nReset = '0' then
				mmu_busy <= '0';
				command_delay <= 0;
				command_count <= 0;
			elsif mmu_start = '1' then
				assert mmu_busy = '0' and mmu_supervisor = '1' and
					mmu_sfc = "000" and mmu_dfc = "000"
					report "MMU dispatch state mismatch" severity failure;
				case command_count is
					when 0 =>
						assert mmu_opcode = x"F000" and mmu_extension = x"2400"
							report "PFLUSHA dispatch mismatch" severity failure;
					when 1 =>
						assert mmu_opcode = x"F010" and mmu_extension = x"0800" and
							mmu_effective_address = x"00000200"
							report "PMOVE dispatch mismatch: opcode=" &
								to_hstring(mmu_opcode) & " ext=" &
								to_hstring(mmu_extension) & " ea=" &
								to_hstring(mmu_effective_address) severity failure;
					when 2 =>
						assert mmu_opcode = x"F010" and mmu_extension = x"9F71" and
							mmu_effective_address = x"00000200"
							report "PTEST dispatch mismatch" severity failure;
					when 3 =>
						assert mmu_opcode = x"F013" and mmu_extension = x"0800" and
							mmu_effective_address = x"00000300"
							report "PTEST address-register return was not committed" severity failure;
					when others =>
						assert false report "unexpected extra MMU command" severity failure;
				end case;
				mmu_busy <= '1';
				command_delay <= 2;
				command_count <= command_count + 1;
			elsif command_delay /= 0 then
				command_delay <= command_delay - 1;
				if command_delay = 1 then
					mmu_busy <= '0';
					mmu_done <= '1';
					if command_count = 3 then
						mmu_address_write <= '1';
						mmu_address_select <= "011";
						mmu_address_data <= x"00000300";
					end if;
				end if;
			end if;

			if nReset = '1' and busstate = "00" and addr_out = x"00000116" then
				post_mmu_fetch_seen <= '1';
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 180 loop
			wait until rising_edge(clk);
			exit when command_count = 4 and post_mmu_fetch_seen = '1';
		end loop;
		assert command_count = 4
			report "kernel dispatched " & integer'image(command_count) &
				" of 4 PMMU instructions" severity failure;
		assert post_mmu_fetch_seen = '1'
			report "kernel did not continue after PMMU commands" severity failure;
		report "PASS: TG68K PMMU F-line dispatch and EA integration" severity note;
		stop;
		wait;
	end process;
end architecture;
