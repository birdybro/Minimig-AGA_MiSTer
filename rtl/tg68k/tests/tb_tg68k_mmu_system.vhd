library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_system is
end entity;

architecture test of tb_tg68k_mmu_system is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal opcode : std_logic_vector(15 downto 0) := x"F010";
	signal extension_word : std_logic_vector(15 downto 0) := (others => '0');
	signal supervisor : std_logic := '1';
	signal effective_address : std_logic_vector(31 downto 0) := (others => '0');
	signal fc_data_register_value : std_logic_vector(2 downto 0) := "101";
	signal sfc : std_logic_vector(2 downto 0) := "001";
	signal dfc : std_logic_vector(2 downto 0) := "101";
	signal instruction_start : std_logic := '0';
	signal instruction_match : std_logic;
	signal instruction_valid : std_logic;
	signal instruction_requires_effective_address : std_logic;
	signal fc_data_register_select : std_logic_vector(2 downto 0);
	signal instruction_busy : std_logic;
	signal instruction_done : std_logic;
	signal unimplemented_exception : std_logic;
	signal privilege_exception : std_logic;
	signal bus_error_exception : std_logic;
	signal configuration_exception : std_logic;
	signal address_register_write : std_logic;
	signal address_register_select : std_logic_vector(2 downto 0);
	signal address_register_data : std_logic_vector(31 downto 0);
	signal translation_start : std_logic := '0';
	signal translation_logical_address : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal translation_function_code : std_logic_vector(2 downto 0) := "001";
	signal translation_write : std_logic := '0';
	signal translation_read_modify_write : std_logic := '0';
	signal translation_ready : std_logic;
	signal translation_busy : std_logic;
	signal translation_done : std_logic;
	signal translation_physical_address : std_logic_vector(31 downto 0);
	signal translation_cache_inhibit : std_logic;
	signal translation_bypassed : std_logic;
	signal translation_atc_hit : std_logic;
	signal translation_table_walk : std_logic;
	signal translation_fault : std_logic;
	signal translation_fault_from_atc : std_logic;
	signal translation_fault_bus_error : std_logic;
	signal translation_fault_invalid : std_logic;
	signal translation_fault_limit : std_logic;
	signal translation_fault_supervisor : std_logic;
	signal translation_fault_write_protect : std_logic;
	signal translation_fault_descriptor_address : std_logic_vector(31 downto 0);
	signal translation_fault_during_update : std_logic;

	signal operand_bus_ready : std_logic := '0';
	signal operand_bus_error : std_logic := '0';
	signal operand_bus_read_data : std_logic_vector(15 downto 0) := (others => '0');
	signal operand_bus_request : std_logic;
	signal operand_bus_write : std_logic;
	signal operand_bus_address : std_logic_vector(31 downto 0);
	signal operand_bus_write_data : std_logic_vector(15 downto 0);
	signal operand_bus_function_code : std_logic_vector(2 downto 0);

	signal table_bus_ready : std_logic := '0';
	signal table_bus_error : std_logic := '0';
	signal table_bus_read_data : std_logic_vector(15 downto 0) := (others => '0');
	signal table_bus_request : std_logic;
	signal table_bus_write : std_logic;
	signal table_bus_lock : std_logic;
	signal table_bus_address : std_logic_vector(31 downto 0);
	signal table_bus_write_data : std_logic_vector(15 downto 0);
	signal table_bus_function_code : std_logic_vector(2 downto 0);

	signal crp_out : mmu_root_pointer_t;
	signal srp_out : mmu_root_pointer_t;
	signal tc_out : mmu_tc_t;
	signal tt0_out : mmu_tt_t;
	signal tt1_out : mmu_tt_t;
	signal mmusr_out : mmu_status_t;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_MMU_System
		port map(
			clk => clk,
			nReset => nReset,
			opcode => opcode,
			extension_word => extension_word,
			supervisor => supervisor,
			effective_address => effective_address,
			fc_data_register_value => fc_data_register_value,
			sfc => sfc,
			dfc => dfc,
			instruction_start => instruction_start,
			instruction_match => instruction_match,
			instruction_valid => instruction_valid,
			instruction_requires_effective_address =>
				instruction_requires_effective_address,
			fc_data_register_select => fc_data_register_select,
			instruction_busy => instruction_busy,
			instruction_done => instruction_done,
			unimplemented_exception => unimplemented_exception,
			privilege_exception => privilege_exception,
			bus_error_exception => bus_error_exception,
			configuration_exception => configuration_exception,
			address_register_write => address_register_write,
			address_register_select => address_register_select,
			address_register_data => address_register_data,
			translation_start => translation_start,
			translation_logical_address => translation_logical_address,
			translation_function_code => translation_function_code,
			translation_write => translation_write,
			translation_read_modify_write => translation_read_modify_write,
			translation_ready => translation_ready,
			translation_busy => translation_busy,
			translation_done => translation_done,
			translation_physical_address => translation_physical_address,
			translation_cache_inhibit => translation_cache_inhibit,
			translation_bypassed => translation_bypassed,
			translation_atc_hit => translation_atc_hit,
			translation_table_walk => translation_table_walk,
			translation_fault => translation_fault,
			translation_fault_from_atc => translation_fault_from_atc,
			translation_fault_bus_error => translation_fault_bus_error,
			translation_fault_invalid => translation_fault_invalid,
			translation_fault_limit => translation_fault_limit,
			translation_fault_supervisor => translation_fault_supervisor,
			translation_fault_write_protect => translation_fault_write_protect,
			translation_fault_descriptor_address =>
				translation_fault_descriptor_address,
			translation_fault_during_update => translation_fault_during_update,
			operand_bus_ready => operand_bus_ready,
			operand_bus_error => operand_bus_error,
			operand_bus_read_data => operand_bus_read_data,
			operand_bus_request => operand_bus_request,
			operand_bus_write => operand_bus_write,
			operand_bus_address => operand_bus_address,
			operand_bus_write_data => operand_bus_write_data,
			operand_bus_function_code => operand_bus_function_code,
			table_bus_ready => table_bus_ready,
			table_bus_error => table_bus_error,
			table_bus_read_data => table_bus_read_data,
			table_bus_request => table_bus_request,
			table_bus_write => table_bus_write,
			table_bus_lock => table_bus_lock,
			table_bus_address => table_bus_address,
			table_bus_write_data => table_bus_write_data,
			table_bus_function_code => table_bus_function_code,
			crp_out => crp_out,
			srp_out => srp_out,
			tc_out => tc_out,
			tt0_out => tt0_out,
			tt1_out => tt1_out,
			mmusr_out => mmusr_out
		);

	stimulus : process
		procedure issue(
			constant opcode_value : std_logic_vector(15 downto 0);
			constant extension_value : std_logic_vector(15 downto 0);
			constant address_value : std_logic_vector(31 downto 0)) is
		begin
			opcode <= opcode_value;
			extension_word <= extension_value;
			effective_address <= address_value;
			wait for 1 ns;
			assert instruction_match = '1' and instruction_valid = '1'
				report "MMU system rejected a valid instruction" severity failure;
			instruction_start <= '1';
			wait until rising_edge(clk);
			instruction_start <= '0';
			wait for 1 ns;
		end procedure;

		procedure operand_read(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			assert operand_bus_request = '1' and operand_bus_write = '0' and
				operand_bus_address = address_value and
				operand_bus_function_code = "101"
				report "MMU operand read cycle mismatch" severity failure;
			assert table_bus_request = '0'
				report "table bus active during PMOVE operand read" severity failure;
			operand_bus_read_data <= data_value;
			operand_bus_ready <= '1';
			wait until rising_edge(clk);
			operand_bus_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure issue_translation(
			constant address_value : std_logic_vector(31 downto 0);
			constant fc_value : std_logic_vector(2 downto 0);
			constant write_value : std_logic) is
		begin
			assert translation_ready = '1'
				report "MMU system did not advertise translation readiness" severity failure;
			translation_logical_address <= address_value;
			translation_function_code <= fc_value;
			translation_write <= write_value;
			translation_start <= '1';
			wait until rising_edge(clk);
			translation_start <= '0';
			wait for 1 ns;
		end procedure;

		procedure wait_translation_done is
		begin
			for cycle in 0 to 80 loop
				exit when translation_done = '1';
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert translation_done = '1'
				report "MMU system translation did not complete" severity failure;
		end procedure;

		procedure leave_translation_done is
		begin
			wait until rising_edge(clk);
			wait for 1 ns;
			assert translation_done = '0' and translation_busy = '0' and
				translation_ready = '1'
				report "MMU system translator did not return idle" severity failure;
		end procedure;

		procedure operand_write(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			assert operand_bus_request = '1' and operand_bus_write = '1' and
				operand_bus_address = address_value and
				operand_bus_write_data = data_value and
				operand_bus_function_code = "101"
				report "MMU operand write cycle mismatch" severity failure;
			operand_bus_ready <= '1';
			wait until rising_edge(clk);
			operand_bus_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure table_read(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			while table_bus_request = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert table_bus_write = '0' and table_bus_address = address_value and
				table_bus_function_code = "101" and operand_bus_request = '0'
				report "MMU table read cycle mismatch: expected " &
					to_hstring(address_value) & " got " &
					to_hstring(table_bus_address) & " FC=" &
					to_hstring(table_bus_function_code) severity failure;
			table_bus_read_data <= data_value;
			table_bus_ready <= '1';
			wait until rising_edge(clk);
			table_bus_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure table_write(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			while table_bus_request = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert table_bus_write = '1' and table_bus_address = address_value and
				table_bus_write_data = data_value and
				table_bus_function_code = "101" and table_bus_lock = '1'
				report "MMU table update cycle mismatch" severity failure;
			table_bus_ready <= '1';
			wait until rising_edge(clk);
			table_bus_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure wait_done is
		begin
			for cycle in 0 to 80 loop
				exit when instruction_done = '1';
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert instruction_done = '1'
				report "MMU system command did not complete" severity failure;
		end procedure;

		procedure leave_done is
		begin
			wait until rising_edge(clk);
			wait for 1 ns;
			assert instruction_done = '0' and instruction_busy = '0'
				report "MMU system did not return idle" severity failure;
		end procedure;

		procedure assert_no_exception is
		begin
			assert unimplemented_exception = '0' and privilege_exception = '0' and
				bus_error_exception = '0' and configuration_exception = '0'
				report "unexpected MMU instruction exception" severity failure;
		end procedure;
	begin
		wait for 2 * CLK_PERIOD;
		nReset <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;

		-- Install a valid short-format root pointer through PMOVE.
		issue(x"F010", x"4C00", x"00000800");
		assert instruction_requires_effective_address = '1'
			report "PMOVE did not request effective-address calculation" severity failure;
		operand_read(x"00000800", x"7FFF");
		operand_read(x"00000802", x"0002");
		operand_read(x"00000804", x"0000");
		operand_read(x"00000806", x"1000");
		wait_done;
		assert_no_exception;
		assert crp_out = x"7FFF000200001000"
			report "PMOVE did not update CRP" severity failure;
		leave_done;

		-- Readback preserves Motorola big-endian quad-word transfer order.
		issue(x"F010", x"4E00", x"00000900");
		operand_write(x"00000900", x"7FFF");
		operand_write(x"00000902", x"0002");
		operand_write(x"00000904", x"0000");
		operand_write(x"00000906", x"1000");
		wait_done;
		assert_no_exception;
		leave_done;

		-- One 12-bit table index and an 8-bit page offset cover 32 bits.
		issue(x"F010", x"4000", x"00000A00");
		operand_read(x"00000A00", x"80CC");
		operand_read(x"00000A02", x"8000");
		wait_done;
		assert_no_exception;
		assert tc_out = x"80CC8000"
			report "PMOVE did not update TC" severity failure;
		leave_done;

		-- Ordinary accesses share the table walker and ATC with PMMU instructions.
		issue_translation(x"ABC39123", "001", '0');
		table_read(x"000010E4", x"D000");
		table_read(x"000010E6", x"0001");
		table_write(x"000010E4", x"D000");
		table_write(x"000010E6", x"0009");
		wait_translation_done;
		assert translation_physical_address = x"D0000123" and
			translation_fault = '0' and translation_table_walk = '1'
			report "MMU system ordinary table translation mismatch" severity failure;
		leave_translation_done;
		issue_translation(x"ABC39123", "001", '0');
		wait_translation_done;
		assert translation_physical_address = x"D0000123" and
			translation_atc_hit = '1' and table_bus_request = '0'
			report "MMU system ordinary ATC hit mismatch" severity failure;
		leave_translation_done;

		-- PLOADR invalidates, walks through CPU space, updates U, and fills ATC.
		issue(x"F010", x"2211", x"ABC34123");
		table_read(x"000010D0", x"A000");
		table_read(x"000010D2", x"0001");
		table_write(x"000010D0", x"A000");
		table_write(x"000010D2", x"0009");
		wait_done;
		assert_no_exception;
		assert mmusr_out = x"0000"
			report "PLOAD changed MMUSR" severity failure;
		leave_done;

		-- A level-zero PTESTR observes the newly filled, unmodified ATC entry.
		issue(x"F010", x"8211", x"ABC34123");
		wait_done;
		assert_no_exception;
		assert table_bus_request = '0' and mmusr_out = x"0000"
			report "level-zero PTEST did not hit the PLOAD entry" severity failure;
		leave_done;

		-- PLOADW forces a fresh search and sets M as well as U.
		issue(x"F010", x"2011", x"ABC34123");
		table_read(x"000010D0", x"A000");
		table_read(x"000010D2", x"0009");
		table_write(x"000010D0", x"A000");
		table_write(x"000010D2", x"0019");
		wait_done;
		assert_no_exception;
		leave_done;

		issue(x"F010", x"8011", x"ABC34123");
		wait_done;
		assert mmusr_out = x"0200"
			report "PTEST did not report the ATC modified attribute" severity failure;
		leave_done;

		-- Nonzero-level PTEST bypasses ATC, suppresses U/M writes, and returns
		-- the physical descriptor address in the selected address register.
		issue(x"F010", x"9F71", x"ABC34123");
		table_read(x"000010D0", x"A000");
		table_read(x"000010D2", x"0019");
		wait_done;
		assert_no_exception;
		assert mmusr_out = x"0201" and address_register_write = '1' and
			address_register_select = "011" and address_register_data = x"000010D0"
			report "nonzero-level PTEST result mismatch" severity failure;
		leave_done;

		-- PFLUSHA removes the entry; a level-zero PTEST then reports invalid.
		issue(x"F000", x"2400", x"00000000");
		assert instruction_requires_effective_address = '0'
			report "PFLUSHA unexpectedly requested an effective address" severity failure;
		wait_done;
		assert_no_exception;
		leave_done;
		issue(x"F010", x"8211", x"ABC34123");
		wait_done;
		assert mmusr_out = x"0400"
			report "PFLUSHA left a stale ATC entry" severity failure;
		leave_done;

		-- TT0 takes priority over an ATC miss for level-zero PTEST.
		issue(x"F010", x"0800", x"00000B00");
		operand_read(x"00000B00", x"AB00");
		operand_read(x"00000B02", x"8110");
		wait_done;
		assert_no_exception;
		assert tt0_out = x"AB008110"
			report "PMOVE did not update TT0" severity failure;
		leave_done;
		issue(x"F010", x"8211", x"ABC34123");
		wait_done;
		assert mmusr_out = x"0040"
			report "PTEST did not report transparent translation" severity failure;
		leave_done;

		-- A bad enabled TC is installed with E cleared and reports configuration.
		issue(x"F010", x"4000", x"00000C00");
		operand_read(x"00000C00", x"8000");
		operand_read(x"00000C02", x"0000");
		wait_done;
		assert configuration_exception = '1' and tc_out = x"00000000"
			report "invalid TC configuration handling mismatch" severity failure;
		leave_done;

		-- Privilege takes priority for an otherwise valid supervisor instruction.
		supervisor <= '0';
		issue(x"F000", x"2400", x"00000000");
		wait_done;
		assert privilege_exception = '1' and unimplemented_exception = '0'
			report "MMU privilege exception priority mismatch" severity failure;
		leave_done;

		report "TG68K integrated MMU subsystem test passed" severity note;
		stop;
		wait;
	end process;
end architecture;
