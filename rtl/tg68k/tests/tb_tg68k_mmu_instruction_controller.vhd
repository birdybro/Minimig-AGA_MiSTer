library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_instruction_controller is
end entity;

architecture test of tb_tg68k_mmu_instruction_controller is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal command_valid : std_logic := '1';
	signal command_unimplemented : std_logic := '0';
	signal command_privilege_violation : std_logic := '0';
	signal operation : mmu_instruction_operation_t := MMU_OP_NONE;
	signal register_select : mmu_register_t := MMU_REG_TC;
	signal operand_size : mmu_operand_size_t := MMU_SIZE_NONE;
	signal flush_disable : std_logic := '0';
	signal read_access : std_logic := '0';
	signal effective_address : std_logic_vector(31 downto 0) := (others => '0');
	signal fc_source : mmu_fc_source_t := MMU_FC_SOURCE_SFC;
	signal fc_immediate : std_logic_vector(2 downto 0) := (others => '0');
	signal fc_data_register_value : std_logic_vector(2 downto 0) := (others => '0');
	signal sfc : std_logic_vector(2 downto 0) := "001";
	signal dfc : std_logic_vector(2 downto 0) := "101";
	signal fc_mask : std_logic_vector(2 downto 0) := (others => '0');
	signal ptest_level : std_logic_vector(2 downto 0) := (others => '0');
	signal ptest_return_address : std_logic := '0';
	signal ptest_address_register : std_logic_vector(2 downto 0) := (others => '0');

	signal memory_ready : std_logic := '0';
	signal memory_error : std_logic := '0';
	signal memory_read_data : std_logic_vector(15 downto 0) := (others => '0');
	signal memory_request : std_logic;
	signal memory_write : std_logic;
	signal memory_address : std_logic_vector(31 downto 0);
	signal memory_write_data : std_logic_vector(15 downto 0);
	signal memory_function_code : std_logic_vector(2 downto 0);

	signal mmu_register_read_data : std_logic_vector(63 downto 0) := (others => '0');
	signal mmu_configuration_exception : std_logic := '0';
	signal mmu_register_write : std_logic;
	signal mmu_register_select : mmu_register_t;
	signal mmu_register_write_data : std_logic_vector(63 downto 0);
	signal mmu_flush_disable : std_logic;

	signal atc_lookup_match : std_logic := '0';
	signal atc_lookup_write_protected : std_logic := '0';
	signal atc_lookup_modified : std_logic := '0';
	signal atc_lookup_bus_error : std_logic := '0';
	signal transparent_match : std_logic := '0';
	signal atc_lookup_request : std_logic;
	signal atc_lookup_test : std_logic;
	signal atc_lookup_address : std_logic_vector(31 downto 0);
	signal atc_lookup_function_code : std_logic_vector(2 downto 0);
	signal atc_lookup_write : std_logic;
	signal atc_flush_all : std_logic;
	signal atc_flush_request : std_logic;
	signal atc_flush_by_address : std_logic;
	signal atc_flush_address : std_logic_vector(31 downto 0);
	signal atc_flush_function_code_base : std_logic_vector(2 downto 0);
	signal atc_flush_function_code_mask : std_logic_vector(2 downto 0);
	signal atc_fill_request : std_logic;
	signal atc_fill_logical_address : std_logic_vector(31 downto 0);
	signal atc_fill_function_code : std_logic_vector(2 downto 0);
	signal atc_fill_physical_address : std_logic_vector(31 downto 0);
	signal atc_fill_cache_inhibit : std_logic;
	signal atc_fill_write_protected : std_logic;
	signal atc_fill_modified : std_logic;
	signal atc_fill_bus_error : std_logic;

	signal walker_done : std_logic := '0';
	signal walker_mapping_valid : std_logic := '0';
	signal walker_physical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal walker_cache_inhibit : std_logic := '0';
	signal walker_write_protected : std_logic := '0';
	signal walker_supervisor_violation : std_logic := '0';
	signal walker_modified : std_logic := '0';
	signal walker_invalid_descriptor : std_logic := '0';
	signal walker_limit_violation : std_logic := '0';
	signal walker_bus_error : std_logic := '0';
	signal walker_final_descriptor_address : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal walker_descriptor_count : std_logic_vector(2 downto 0) := (others => '0');
	signal walker_start : std_logic;
	signal walker_logical_address : std_logic_vector(31 downto 0);
	signal walker_function_code : std_logic_vector(2 downto 0);
	signal walker_write_access : std_logic;
	signal walker_force_table_search : std_logic;
	signal walker_suppress_descriptor_updates : std_logic;
	signal walker_stop_level : std_logic_vector(2 downto 0);

	signal busy : std_logic;
	signal done : std_logic;
	signal unimplemented_exception : std_logic;
	signal privilege_exception : std_logic;
	signal bus_error_exception : std_logic;
	signal configuration_exception : std_logic;
	signal address_register_write : std_logic;
	signal address_register_select : std_logic_vector(2 downto 0);
	signal address_register_data : std_logic_vector(31 downto 0);
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_MMU_Instruction_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			command_valid => command_valid,
			command_unimplemented => command_unimplemented,
			command_privilege_violation => command_privilege_violation,
			operation => operation,
			register_select => register_select,
			operand_size => operand_size,
			flush_disable => flush_disable,
			read_access => read_access,
			effective_address => effective_address,
			fc_source => fc_source,
			fc_immediate => fc_immediate,
			fc_data_register_value => fc_data_register_value,
			sfc => sfc,
			dfc => dfc,
			fc_mask => fc_mask,
			ptest_level => ptest_level,
			ptest_return_address => ptest_return_address,
			ptest_address_register => ptest_address_register,
			memory_ready => memory_ready,
			memory_error => memory_error,
			memory_read_data => memory_read_data,
			memory_request => memory_request,
			memory_write => memory_write,
			memory_address => memory_address,
			memory_write_data => memory_write_data,
			memory_function_code => memory_function_code,
			mmu_register_read_data => mmu_register_read_data,
			mmu_configuration_exception => mmu_configuration_exception,
			mmu_register_write => mmu_register_write,
			mmu_register_select => mmu_register_select,
			mmu_register_write_data => mmu_register_write_data,
			mmu_flush_disable => mmu_flush_disable,
			atc_lookup_match => atc_lookup_match,
			atc_lookup_write_protected => atc_lookup_write_protected,
			atc_lookup_modified => atc_lookup_modified,
			atc_lookup_bus_error => atc_lookup_bus_error,
			transparent_match => transparent_match,
			atc_lookup_request => atc_lookup_request,
			atc_lookup_test => atc_lookup_test,
			atc_lookup_address => atc_lookup_address,
			atc_lookup_function_code => atc_lookup_function_code,
			atc_lookup_write => atc_lookup_write,
			atc_flush_all => atc_flush_all,
			atc_flush_request => atc_flush_request,
			atc_flush_by_address => atc_flush_by_address,
			atc_flush_address => atc_flush_address,
			atc_flush_function_code_base => atc_flush_function_code_base,
			atc_flush_function_code_mask => atc_flush_function_code_mask,
			atc_fill_request => atc_fill_request,
			atc_fill_logical_address => atc_fill_logical_address,
			atc_fill_function_code => atc_fill_function_code,
			atc_fill_physical_address => atc_fill_physical_address,
			atc_fill_cache_inhibit => atc_fill_cache_inhibit,
			atc_fill_write_protected => atc_fill_write_protected,
			atc_fill_modified => atc_fill_modified,
			atc_fill_bus_error => atc_fill_bus_error,
			walker_done => walker_done,
			walker_mapping_valid => walker_mapping_valid,
			walker_physical_address => walker_physical_address,
			walker_cache_inhibit => walker_cache_inhibit,
			walker_write_protected => walker_write_protected,
			walker_supervisor_violation => walker_supervisor_violation,
			walker_modified => walker_modified,
			walker_invalid_descriptor => walker_invalid_descriptor,
			walker_limit_violation => walker_limit_violation,
			walker_bus_error => walker_bus_error,
			walker_final_descriptor_address => walker_final_descriptor_address,
			walker_descriptor_count => walker_descriptor_count,
			walker_start => walker_start,
			walker_logical_address => walker_logical_address,
			walker_function_code => walker_function_code,
			walker_write_access => walker_write_access,
			walker_force_table_search => walker_force_table_search,
			walker_suppress_descriptor_updates => walker_suppress_descriptor_updates,
			walker_stop_level => walker_stop_level,
			busy => busy,
			done => done,
			unimplemented_exception => unimplemented_exception,
			privilege_exception => privilege_exception,
			bus_error_exception => bus_error_exception,
			configuration_exception => configuration_exception,
			address_register_write => address_register_write,
			address_register_select => address_register_select,
			address_register_data => address_register_data
		);

	stimulus : process
		procedure pulse_start is
		begin
			start <= '1';
			wait until rising_edge(clk);
			start <= '0';
			wait for 1 ns;
		end procedure;

		procedure finish_command is
		begin
			assert done = '1'
				report "MMU command did not complete" severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert done = '0' and busy = '0'
				report "MMU controller did not return idle" severity failure;
		end procedure;

		procedure read_word(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			assert memory_request = '1' and memory_write = '0' and
				memory_address = address_value and memory_function_code = "101"
				report "PMOVE read transfer mismatch" severity failure;
			memory_read_data <= data_value;
			memory_ready <= '1';
			wait until rising_edge(clk);
			memory_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure write_word(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			assert memory_request = '1' and memory_write = '1' and
				memory_address = address_value and memory_write_data = data_value and
				memory_function_code = "101"
				report "PMOVE write transfer mismatch" severity failure;
			memory_ready <= '1';
			wait until rising_edge(clk);
			memory_ready <= '0';
			wait for 1 ns;
		end procedure;
	begin
		wait for 2 * CLK_PERIOD;
		nReset <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;

		-- PMOVE memory-to-MMU uses ascending, big-endian word transfers.
		operation <= MMU_OP_PMOVE_TO_MMU;
		register_select <= MMU_REG_SRP;
		operand_size <= MMU_SIZE_QUAD;
		flush_disable <= '1';
		effective_address <= x"00001000";
		pulse_start;
		read_word(x"00001000", x"7FFF");
		read_word(x"00001002", x"0002");
		read_word(x"00001004", x"1234");
		read_word(x"00001006", x"5670");
		assert mmu_register_write = '1' and mmu_register_select = MMU_REG_SRP and
			mmu_register_write_data = x"7FFF000212345670" and
			mmu_flush_disable = '1'
			report "PMOVE quad register commit mismatch" severity failure;
		wait until rising_edge(clk);
		mmu_configuration_exception <= '1';
		wait until rising_edge(clk);
		mmu_configuration_exception <= '0';
		wait for 1 ns;
		assert configuration_exception = '1'
			report "PMOVE configuration exception was lost" severity failure;
		finish_command;

		-- PMOVE MMU-to-memory preserves register width and word order.
		operation <= MMU_OP_PMOVE_FROM_MMU;
		register_select <= MMU_REG_CRP;
		operand_size <= MMU_SIZE_QUAD;
		flush_disable <= '0';
		mmu_register_read_data <= x"80000003CAFEBAB0";
		effective_address <= x"00002000";
		wait for 1 ns;
		assert mmu_register_select = MMU_REG_CRP
			report "PMOVE read register was not selected before issue" severity failure;
		pulse_start;
		write_word(x"00002000", x"8000");
		write_word(x"00002002", x"0003");
		write_word(x"00002004", x"CAFE");
		write_word(x"00002006", x"BAB0");
		finish_command;

		-- A bus error terminates a partial PMOVE without committing a register.
		operation <= MMU_OP_PMOVE_TO_MMU;
		register_select <= MMU_REG_TC;
		operand_size <= MMU_SIZE_LONG;
		effective_address <= x"00003000";
		pulse_start;
		read_word(x"00003000", x"80CC");
		assert memory_address = x"00003002" severity failure;
		memory_error <= '1';
		wait until rising_edge(clk);
		memory_error <= '0';
		wait for 1 ns;
		assert done = '1' and bus_error_exception = '1' and
			mmu_register_write = '0'
			report "PMOVE operand bus error handling failed" severity failure;
		finish_command;

		-- Address-free and page-selective PFLUSH commands carry exact qualifiers.
		operation <= MMU_OP_PFLUSH_ALL;
		pulse_start;
		assert atc_flush_all = '1' and atc_flush_request = '0'
			report "PFLUSHA control pulse failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		finish_command;

		operation <= MMU_OP_PFLUSH_PAGE;
		fc_source <= MMU_FC_SOURCE_IMMEDIATE;
		fc_immediate <= "110";
		fc_mask <= "101";
		effective_address <= x"12345678";
		pulse_start;
		assert atc_flush_request = '1' and atc_flush_by_address = '1' and
			atc_flush_address = x"12345678" and
			atc_flush_function_code_base = "110" and
			atc_flush_function_code_mask = "101"
			report "page-selective PFLUSH control failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		finish_command;

		-- PLOAD first invalidates the exact tag, then forces a history-updating walk.
		operation <= MMU_OP_PLOAD;
		fc_source <= MMU_FC_SOURCE_DATA_REGISTER;
		fc_data_register_value <= "011";
		read_access <= '0';
		effective_address <= x"23456789";
		pulse_start;
		assert atc_flush_request = '1' and atc_flush_by_address = '1' and
			atc_flush_function_code_base = "011" and
			atc_flush_function_code_mask = "111"
			report "PLOAD tag invalidation failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert walker_start = '1' and walker_logical_address = x"23456789" and
			walker_function_code = "011" and walker_write_access = '1' and
			walker_force_table_search = '1' and
			walker_suppress_descriptor_updates = '0' and walker_stop_level = "000"
			report "PLOAD walker request failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		walker_mapping_valid <= '1';
		walker_physical_address <= x"A3456789";
		walker_cache_inhibit <= '1';
		walker_write_protected <= '0';
		walker_modified <= '1';
		walker_done <= '1';
		wait until rising_edge(clk);
		walker_done <= '0';
		wait for 1 ns;
		assert atc_fill_request = '1' and
			atc_fill_logical_address = x"23456789" and
			atc_fill_function_code = "011" and
			atc_fill_physical_address = x"A3456789" and
			atc_fill_cache_inhibit = '1' and atc_fill_modified = '1' and
			atc_fill_bus_error = '0'
			report "PLOAD ATC fill failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		finish_command;

		-- Level-zero PTEST is a non-mutating ATC lookup and writes exact MMUSR bits.
		operation <= MMU_OP_PTEST;
		fc_source <= MMU_FC_SOURCE_SFC;
		read_access <= '1';
		ptest_level <= "000";
		ptest_return_address <= '0';
		effective_address <= x"3456789A";
		atc_lookup_match <= '1';
		atc_lookup_write_protected <= '1';
		atc_lookup_modified <= '1';
		pulse_start;
		assert atc_lookup_request = '1' and atc_lookup_test = '1' and
			atc_lookup_address = x"3456789A" and
			atc_lookup_function_code = "001" and atc_lookup_write = '0'
			report "PTEST level-zero lookup failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert mmu_register_write = '1' and
			mmu_register_select = MMU_REG_MMUSR and
			mmu_register_write_data = x"0000000000000A00"
			report "PTEST level-zero MMUSR result failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		finish_command;

		transparent_match <= '1';
		pulse_start;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert mmu_register_write = '1' and
			mmu_register_write_data = x"0000000000000040"
			report "transparent PTEST status priority failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		finish_command;
		transparent_match <= '0';

		-- Nonzero PTEST suppresses history, returns the final descriptor, and sets N.
		operation <= MMU_OP_PTEST;
		fc_source <= MMU_FC_SOURCE_DFC;
		read_access <= '0';
		ptest_level <= "111";
		ptest_return_address <= '1';
		ptest_address_register <= "110";
		effective_address <= x"456789AB";
		pulse_start;
		assert walker_start = '1' and walker_function_code = "101" and
			walker_write_access = '1' and walker_force_table_search = '1' and
			walker_suppress_descriptor_updates = '1' and walker_stop_level = "111"
			report "PTEST table-walk request failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		walker_mapping_valid <= '0';
		walker_limit_violation <= '1';
		walker_supervisor_violation <= '1';
		walker_write_protected <= '1';
		walker_modified <= '1';
		walker_final_descriptor_address <= x"0000ABC0";
		walker_descriptor_count <= "011";
		walker_done <= '1';
		wait until rising_edge(clk);
		walker_done <= '0';
		wait for 1 ns;
		assert mmu_register_write = '1' and
			mmu_register_write_data = x"0000000000006E03"
			report "PTEST table-walk MMUSR result failed" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert done = '1' and address_register_write = '1' and
			address_register_select = "110" and
			address_register_data = x"0000ABC0"
			report "PTEST descriptor-address return failed" severity failure;
		finish_command;
		walker_limit_violation <= '0';
		walker_supervisor_violation <= '0';
		walker_write_protected <= '0';
		walker_modified <= '0';

		-- Privilege violation has priority over unsupported-command reporting.
		command_valid <= '0';
		command_privilege_violation <= '1';
		command_unimplemented <= '0';
		operation <= MMU_OP_NONE;
		pulse_start;
		assert done = '1' and privilege_exception = '1' and
			unimplemented_exception = '0'
			report "PMMU exception priority failed" severity failure;
		finish_command;

		command_privilege_violation <= '0';
		command_unimplemented <= '1';
		pulse_start;
		assert done = '1' and unimplemented_exception = '1' and
			privilege_exception = '0'
			report "PMMU unimplemented exception failed" severity failure;
		finish_command;

		report "PASS: MC68030 MMU instruction controller" severity note;
		stop;
	end process;
end architecture;
