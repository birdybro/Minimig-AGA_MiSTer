library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_translation is
end entity;

architecture test of tb_tg68k_mmu_translation is
	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code : std_logic_vector(2 downto 0) := "001";
	signal write_access : std_logic := '0';
	signal read_modify_write : std_logic := '0';
	signal tc : mmu_tc_t := (others => '0');
	signal tt0 : mmu_tt_t := (others => '0');
	signal tt1 : mmu_tt_t := (others => '0');
	signal crp : mmu_root_pointer_t := x"7FFF000200001000";
	signal srp : mmu_root_pointer_t := x"7FFF000200002000";

	signal atc_lookup_match : std_logic;
	signal atc_lookup_hit : std_logic;
	signal atc_lookup_requires_walk : std_logic;
	signal atc_lookup_physical_address : std_logic_vector(31 downto 0);
	signal atc_lookup_cache_inhibit : std_logic;
	signal atc_lookup_write_protected : std_logic;
	signal atc_lookup_modified : std_logic;
	signal atc_lookup_bus_error : std_logic;
	signal atc_lookup_request : std_logic;
	signal atc_lookup_address : std_logic_vector(31 downto 0);
	signal atc_lookup_function_code : std_logic_vector(2 downto 0);
	signal atc_lookup_write : std_logic;
	signal atc_fill_request : std_logic;
	signal atc_fill_logical_address : std_logic_vector(31 downto 0);
	signal atc_fill_function_code : std_logic_vector(2 downto 0);
	signal atc_fill_physical_address : std_logic_vector(31 downto 0);
	signal atc_fill_cache_inhibit : std_logic;
	signal atc_fill_write_protected : std_logic;
	signal atc_fill_modified : std_logic;
	signal atc_fill_bus_error : std_logic;

	signal walker_done : std_logic;
	signal walker_mapping_valid : std_logic;
	signal walker_physical_address : std_logic_vector(31 downto 0);
	signal walker_cache_inhibit : std_logic;
	signal walker_write_protected : std_logic;
	signal walker_supervisor_violation : std_logic;
	signal walker_modified : std_logic;
	signal walker_invalid_descriptor : std_logic;
	signal walker_limit_violation : std_logic;
	signal walker_bus_error : std_logic;
	signal walker_fault_descriptor_address : std_logic_vector(31 downto 0);
	signal walker_fault_during_update : std_logic;
	signal walker_start : std_logic;
	signal walker_logical_address : std_logic_vector(31 downto 0);
	signal walker_function_code : std_logic_vector(2 downto 0);
	signal walker_write_access : std_logic;

	signal bus_ready : std_logic := '0';
	signal bus_error : std_logic := '0';
	signal bus_read_data : std_logic_vector(15 downto 0) := (others => '0');
	signal bus_request : std_logic;
	signal bus_write : std_logic;
	signal bus_lock : std_logic;
	signal bus_address : std_logic_vector(31 downto 0);
	signal bus_write_data : std_logic_vector(15 downto 0);
	signal bus_function_code : std_logic_vector(2 downto 0);

	signal busy : std_logic;
	signal done : std_logic;
	signal physical_address : std_logic_vector(31 downto 0);
	signal cache_inhibit : std_logic;
	signal translation_bypassed : std_logic;
	signal translation_atc_hit : std_logic;
	signal translation_table_walk : std_logic;
	signal fault : std_logic;
	signal fault_from_atc : std_logic;
	signal fault_bus_error : std_logic;
	signal fault_invalid : std_logic;
	signal fault_limit : std_logic;
	signal fault_supervisor : std_logic;
	signal fault_write_protect : std_logic;
	signal fault_descriptor_address : std_logic_vector(31 downto 0);
	signal fault_during_update : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_MMU_Translation
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			logical_address => logical_address,
			function_code => function_code,
			write_access => write_access,
			read_modify_write => read_modify_write,
			tc => tc,
			tt0 => tt0,
			tt1 => tt1,
			atc_lookup_match => atc_lookup_match,
			atc_lookup_hit => atc_lookup_hit,
			atc_lookup_requires_walk => atc_lookup_requires_walk,
			atc_lookup_physical_address => atc_lookup_physical_address,
			atc_lookup_cache_inhibit => atc_lookup_cache_inhibit,
			atc_lookup_write_protected => atc_lookup_write_protected,
			atc_lookup_modified => atc_lookup_modified,
			atc_lookup_bus_error => atc_lookup_bus_error,
			atc_lookup_request => atc_lookup_request,
			atc_lookup_address => atc_lookup_address,
			atc_lookup_function_code => atc_lookup_function_code,
			atc_lookup_write => atc_lookup_write,
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
			walker_fault_descriptor_address => walker_fault_descriptor_address,
			walker_fault_during_update => walker_fault_during_update,
			walker_start => walker_start,
			walker_logical_address => walker_logical_address,
			walker_function_code => walker_function_code,
			walker_write_access => walker_write_access,
			busy => busy,
			done => done,
			physical_address => physical_address,
			cache_inhibit => cache_inhibit,
			translation_bypassed => translation_bypassed,
			translation_atc_hit => translation_atc_hit,
			translation_table_walk => translation_table_walk,
			fault => fault,
			fault_from_atc => fault_from_atc,
			fault_bus_error => fault_bus_error,
			fault_invalid => fault_invalid,
			fault_limit => fault_limit,
			fault_supervisor => fault_supervisor,
			fault_write_protect => fault_write_protect,
			fault_descriptor_address => fault_descriptor_address,
			fault_during_update => fault_during_update
		);

	atc : entity work.TG68K_MMU_ATC
		port map(
			clk => clk,
			nReset => nReset,
			page_size => tc(MMU_TC_PS_HIGH downto MMU_TC_PS_LOW),
			lookup_request => atc_lookup_request,
			lookup_logical_address => atc_lookup_address,
			lookup_function_code => atc_lookup_function_code,
			lookup_write => atc_lookup_write,
			lookup_test => '0',
			lookup_match => atc_lookup_match,
			lookup_hit => atc_lookup_hit,
			lookup_requires_walk => atc_lookup_requires_walk,
			lookup_physical_address => atc_lookup_physical_address,
			lookup_cache_inhibit => atc_lookup_cache_inhibit,
			lookup_write_protected => atc_lookup_write_protected,
			lookup_modified => atc_lookup_modified,
			lookup_bus_error => atc_lookup_bus_error,
			fill_request => atc_fill_request,
			fill_logical_address => atc_fill_logical_address,
			fill_function_code => atc_fill_function_code,
			fill_physical_address => atc_fill_physical_address,
			fill_cache_inhibit => atc_fill_cache_inhibit,
			fill_write_protected => atc_fill_write_protected,
			fill_modified => atc_fill_modified,
			fill_bus_error => atc_fill_bus_error,
			flush_all => '0',
			flush_request => '0',
			flush_by_address => '0',
			flush_logical_address => (others => '0'),
			flush_function_code_base => (others => '0'),
			flush_function_code_mask => (others => '0')
		);

	walker : entity work.TG68K_MMU_Walker
		port map(
			clk => clk,
			nReset => nReset,
			start => walker_start,
			logical_address => walker_logical_address,
			function_code => walker_function_code,
			write_access => walker_write_access,
			force_table_search => '0',
			suppress_descriptor_updates => '0',
			stop_level => "000",
			crp => crp,
			srp => srp,
			tc => tc,
			bus_ready => bus_ready,
			bus_error => bus_error,
			bus_read_data => bus_read_data,
			bus_request => bus_request,
			bus_write => bus_write,
			bus_lock => bus_lock,
			bus_address => bus_address,
			bus_write_data => bus_write_data,
			bus_function_code => bus_function_code,
			busy => open,
			done => walker_done,
			mapping_valid => walker_mapping_valid,
			physical_address => walker_physical_address,
			cache_inhibit => walker_cache_inhibit,
			write_protected => walker_write_protected,
			supervisor_violation => walker_supervisor_violation,
			modified => walker_modified,
			invalid_descriptor => walker_invalid_descriptor,
			limit_violation => walker_limit_violation,
			walk_bus_error => walker_bus_error,
			fault_descriptor_address => walker_fault_descriptor_address,
			fault_during_update => walker_fault_during_update,
			final_descriptor_address => open,
			descriptor_count => open
		);

	stimulus : process
		procedure issue(
			constant address_value : std_logic_vector(31 downto 0);
			constant fc_value : std_logic_vector(2 downto 0);
			constant write_value : std_logic) is
		begin
			logical_address <= address_value;
			function_code <= fc_value;
			write_access <= write_value;
			start <= '1';
			wait until rising_edge(clk);
			start <= '0';
			wait for 1 ns;
		end procedure;

		procedure table_read(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			while bus_request = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert bus_write = '0' and bus_address = address_value and
				bus_function_code = "101"
				report "translation table read mismatch" severity failure;
			bus_read_data <= data_value;
			bus_ready <= '1';
			wait until rising_edge(clk);
			bus_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure table_write(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			while bus_request = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert bus_write = '1' and bus_lock = '1' and
				bus_address = address_value and bus_write_data = data_value
				report "translation table update mismatch" severity failure;
			bus_ready <= '1';
			wait until rising_edge(clk);
			bus_ready <= '0';
			wait for 1 ns;
		end procedure;

		procedure table_error(constant address_value : std_logic_vector(31 downto 0)) is
		begin
			while bus_request = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert bus_address = address_value
				report "table bus error address mismatch" severity failure;
			bus_error <= '1';
			wait until rising_edge(clk);
			bus_error <= '0';
			wait for 1 ns;
		end procedure;

		procedure wait_done is
		begin
			for cycle in 0 to 80 loop
				exit when done = '1';
				wait until rising_edge(clk);
				wait for 1 ns;
			end loop;
			assert done = '1' report "translation did not complete" severity failure;
		end procedure;

		procedure leave_done is
		begin
			wait until rising_edge(clk);
			wait for 1 ns;
			assert done = '0' and busy = '0'
				report "translation controller did not return idle" severity failure;
		end procedure;
	begin
		wait for 2 * CLK_PERIOD;
		nReset <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;

		-- Disabled translation completes without an ATC lookup or table cycle.
		issue(x"12345678", "001", '0');
		wait until rising_edge(clk);
		wait for 1 ns;
		assert done = '1' and physical_address = x"12345678" and
			translation_bypassed = '1' and fault = '0' and bus_request = '0'
			report "disabled translation bypass mismatch" severity failure;
		leave_done;

		tc <= x"80CC8000";
		tt0 <= x"AB008110";
		issue(x"ABC34123", "001", '0');
		wait_done;
		assert physical_address = x"ABC34123" and translation_bypassed = '1' and
			translation_atc_hit = '0' and translation_table_walk = '0'
			report "transparent translation bypass mismatch" severity failure;
		leave_done;

		-- CPU-space cycles always bypass both TT and table translation.
		issue(x"ABC34123", "111", '1');
		wait_done;
		assert physical_address = x"ABC34123" and translation_bypassed = '1' and
			fault = '0' and bus_request = '0'
			report "CPU-space translation bypass mismatch" severity failure;
		leave_done;
		tt0 <= (others => '0');

		-- A miss walks the short table, updates U, and fills the ATC.
		issue(x"ABC34123", "001", '0');
		table_read(x"000010D0", x"A000");
		table_read(x"000010D2", x"0001");
		table_write(x"000010D0", x"A000");
		table_write(x"000010D2", x"0009");
		wait_done;
		assert physical_address = x"A0000123" and fault = '0' and
			translation_table_walk = '1' and translation_atc_hit = '0'
			report "read table translation mismatch" severity failure;
		leave_done;

		-- The same read is an ATC hit and performs no physical table cycle.
		issue(x"ABC34123", "001", '0');
		wait until rising_edge(clk);
		wait for 1 ns;
		assert done = '0' report "ATC hit completed too early" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert done = '1' and physical_address = x"A0000123" and
			translation_atc_hit = '1' and translation_table_walk = '0' and
			bus_request = '0'
			report "ATC read-hit result or timing mismatch" severity failure;
		leave_done;

		-- A first write to a clean entry rewalks it to set M.
		issue(x"ABC34123", "001", '1');
		table_read(x"000010D0", x"A000");
		table_read(x"000010D2", x"0009");
		table_write(x"000010D0", x"A000");
		table_write(x"000010D2", x"0019");
		wait_done;
		assert physical_address = x"A0000123" and fault = '0' and
			translation_table_walk = '1'
			report "clean ATC write did not update the descriptor" severity failure;
		leave_done;

		issue(x"ABC34123", "001", '1');
		wait_done;
		assert translation_atc_hit = '1' and fault = '0' and bus_request = '0'
			report "modified ATC write did not hit" severity failure;
		leave_done;

		-- A read may fill a write-protected mapping; a later write faults on hit.
		issue(x"ABC35123", "001", '0');
		table_read(x"000010D4", x"B000");
		table_read(x"000010D6", x"0005");
		table_write(x"000010D4", x"B000");
		table_write(x"000010D6", x"000D");
		wait_done;
		assert physical_address = x"B0000123" and fault = '0'
			report "write-protected read translation failed" severity failure;
		leave_done;
		issue(x"ABC35123", "001", '1');
		wait_done;
		assert fault = '1' and fault_write_protect = '1' and
			fault_from_atc = '0' and translation_atc_hit = '1' and bus_request = '0'
			report "ATC write-protection fault mismatch" severity failure;
		leave_done;

		-- Invalid translations are cached as fault entries.
		issue(x"ABC36123", "001", '0');
		table_read(x"000010D8", x"0000");
		table_read(x"000010DA", x"0000");
		wait_done;
		assert fault = '1' and fault_invalid = '1' and fault_from_atc = '0'
			report "fresh invalid-descriptor fault mismatch" severity failure;
		leave_done;
		issue(x"ABC36123", "001", '0');
		wait_done;
		assert fault = '1' and fault_from_atc = '1' and translation_atc_hit = '1' and
			bus_request = '0'
			report "cached translation fault mismatch" severity failure;
		leave_done;

		-- Descriptor-fetch and descriptor-update failures retain their phase data.
		issue(x"ABC37123", "001", '0');
		table_error(x"000010DC");
		wait_done;
		assert fault = '1' and fault_bus_error = '1' and
			fault_descriptor_address = x"000010DC" and fault_during_update = '0'
			report "descriptor-fetch bus fault mismatch" severity failure;
		leave_done;

		issue(x"ABC38123", "001", '0');
		table_read(x"000010E0", x"C000");
		table_read(x"000010E2", x"0001");
		table_error(x"000010E0");
		wait_done;
		assert fault = '1' and fault_bus_error = '1' and
			fault_descriptor_address = x"000010E0" and fault_during_update = '1'
			report "descriptor-update bus fault mismatch" severity failure;
		leave_done;

		report "PASS: MC68030 MMU access translation controller" severity note;
		stop;
		wait;
	end process;
end architecture;
