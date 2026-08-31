library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_walker is
end entity;

architecture test of tb_tg68k_mmu_walker is
	constant CLK_PERIOD : time := 10 ns;
	constant MAX_TRACE : natural := 64;

	type memory_t is array (0 to 32767) of std_logic_vector(15 downto 0);
	type address_trace_t is array (0 to MAX_TRACE - 1) of std_logic_vector(31 downto 0);
	type data_trace_t is array (0 to MAX_TRACE - 1) of std_logic_vector(15 downto 0);
	type bit_trace_t is array (0 to MAX_TRACE - 1) of std_logic;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code : std_logic_vector(2 downto 0) := "001";
	signal write_access : std_logic := '0';
	signal crp : mmu_root_pointer_t := (others => '0');
	signal srp : mmu_root_pointer_t := (others => '0');
	signal tc : mmu_tc_t := (others => '0');

	signal bus_ready : std_logic;
	signal bus_error : std_logic;
	signal bus_read_data : std_logic_vector(15 downto 0);
	signal bus_request : std_logic;
	signal bus_write : std_logic;
	signal bus_lock : std_logic;
	signal bus_address : std_logic_vector(31 downto 0);
	signal bus_write_data : std_logic_vector(15 downto 0);
	signal bus_function_code : std_logic_vector(2 downto 0);

	signal busy : std_logic;
	signal done : std_logic;
	signal mapping_valid : std_logic;
	signal physical_address : std_logic_vector(31 downto 0);
	signal cache_inhibit : std_logic;
	signal write_protected : std_logic;
	signal supervisor_violation : std_logic;
	signal modified : std_logic;
	signal invalid_descriptor : std_logic;
	signal limit_violation : std_logic;
	signal walk_bus_error : std_logic;
	signal fault_descriptor_address : std_logic_vector(31 downto 0);
	signal fault_during_update : std_logic;
	signal final_descriptor_address : std_logic_vector(31 downto 0);
	signal descriptor_count : std_logic_vector(2 downto 0);

	signal memory : memory_t := (others => (others => '0'));
	signal memory_load : std_logic := '0';
	signal memory_load_address : std_logic_vector(31 downto 0) := (others => '0');
	signal memory_load_data : std_logic_vector(15 downto 0) := (others => '0');
	signal allow_ready : std_logic := '1';
	signal inject_error : std_logic := '0';
	signal inject_error_on_write : std_logic := '0';
	signal error_address : std_logic_vector(31 downto 0) := (others => '0');
	signal clear_trace : std_logic := '0';
	signal trace_address : address_trace_t := (others => (others => '0'));
	signal trace_data : data_trace_t := (others => (others => '0'));
	signal trace_write : bit_trace_t := (others => '0');
	signal trace_count : natural range 0 to MAX_TRACE := 0;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_MMU_Walker
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			logical_address => logical_address,
			function_code => function_code,
			write_access => write_access,
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
			busy => busy,
			done => done,
			mapping_valid => mapping_valid,
			physical_address => physical_address,
			cache_inhibit => cache_inhibit,
			write_protected => write_protected,
			supervisor_violation => supervisor_violation,
			modified => modified,
			invalid_descriptor => invalid_descriptor,
			limit_violation => limit_violation,
			walk_bus_error => walk_bus_error,
			fault_descriptor_address => fault_descriptor_address,
			fault_during_update => fault_during_update,
			final_descriptor_address => final_descriptor_address,
			descriptor_count => descriptor_count
		);

	bus_read_data <= memory(to_integer(unsigned(bus_address(15 downto 1))));
	bus_error <= bus_request and inject_error when bus_address = error_address and
		(bus_write = inject_error_on_write) else '0';
	bus_ready <= bus_request and allow_ready and not bus_error;

	memory_and_trace : process(clk)
		variable memory_index : natural range 0 to 32767;
	begin
		if rising_edge(clk) then
			if memory_load = '1' then
				memory_index := to_integer(unsigned(memory_load_address(15 downto 1)));
				memory(memory_index) <= memory_load_data;
			end if;
			if clear_trace = '1' then
				trace_count <= 0;
			elsif bus_request = '1' and (bus_ready = '1' or bus_error = '1') then
				assert bus_lock = '1'
					report "table-walk bus cycle without lock" severity failure;
				assert bus_function_code = "101"
					report "table-walk bus cycle used wrong function code" severity failure;
				assert trace_count < MAX_TRACE
					report "table-walk trace overflow" severity failure;
				trace_address(trace_count) <= bus_address;
				trace_data(trace_count) <= bus_write_data;
				trace_write(trace_count) <= bus_write;
				trace_count <= trace_count + 1;
				if bus_ready = '1' and bus_write = '1' then
					memory_index := to_integer(unsigned(bus_address(15 downto 1)));
					memory(memory_index) <= bus_write_data;
				end if;
			end if;
		end if;
	end process;

	stimulus : process
		procedure load_word(
			constant address_value : std_logic_vector(31 downto 0);
			constant data_value : std_logic_vector(15 downto 0)) is
		begin
			memory_load_address <= address_value;
			memory_load_data <= data_value;
			memory_load <= '1';
			wait until rising_edge(clk);
			memory_load <= '0';
			wait for 1 ns;
		end procedure;

		procedure reset_trace is
		begin
			clear_trace <= '1';
			wait until rising_edge(clk);
			clear_trace <= '0';
			wait for 1 ns;
		end procedure;

		procedure run_walk(
			constant address_value : std_logic_vector(31 downto 0);
			constant fc_value : std_logic_vector(2 downto 0);
			constant is_write : std_logic) is
		begin
			logical_address <= address_value;
			function_code <= fc_value;
			write_access <= is_write;
			start <= '1';
			wait until rising_edge(clk);
			start <= '0';
			wait until done = '1' for 2 us;
			assert done = '1'
				report "table walk timed out" severity failure;
			wait for 1 ns;
		end procedure;

		procedure check_trace(
			constant trace_index : natural;
			constant expected_address : std_logic_vector(31 downto 0);
			constant expected_write : std_logic;
			constant expected_data : std_logic_vector(15 downto 0) := x"0000") is
		begin
			assert trace_address(trace_index) = expected_address
				report "table-walk bus address mismatch" severity failure;
			assert trace_write(trace_index) = expected_write
				report "table-walk bus direction mismatch" severity failure;
			if expected_write = '1' then
				assert trace_data(trace_index) = expected_data
					report "table-walk write data mismatch" severity failure;
			end if;
		end procedure;
	begin
		wait for 2 * CLK_PERIOD;
		nReset <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;

		-- Translation-disabled and CPU-space accesses never start table traffic.
		tc <= (others => '0');
		crp <= x"7FFF000200001000";
		reset_trace;
		run_walk(x"12345678", "001", '0');
		assert mapping_valid = '1' and physical_address = x"12345678"
			report "disabled translation did not pass the address through" severity failure;
		assert trace_count = 0 and descriptor_count = "000"
			report "disabled translation performed a table access" severity failure;

		tc <= x"80CC8000";
		reset_trace;
		run_walk(x"89ABCDEF", "111", '1');
		assert mapping_valid = '1' and physical_address = x"89ABCDEF"
			report "CPU-space access was translated" severity failure;
		assert trace_count = 0
			report "CPU-space access performed a table search" severity failure;

		-- One-level short-format search followed by a U-bit writeback.
		load_word(x"000010D0", x"2000");
		load_word(x"000010D2", x"0041");
		crp <= x"7FFF000200001000";
		tc <= x"80CC8000";
		reset_trace;
		run_walk(x"ABC34123", "001", '0');
		assert mapping_valid = '1' and physical_address = x"20000123"
			report "one-level short translation failed" severity failure;
		assert cache_inhibit = '1' and modified = '0'
			report "short page attributes were decoded incorrectly" severity failure;
		assert descriptor_count = "001" and final_descriptor_address = x"000010D0"
			report "short table-search descriptor accounting failed" severity failure;
		assert trace_count = 4
			report "short table-search bus cycle count mismatch" severity failure;
		check_trace(0, x"000010D0", '0');
		check_trace(1, x"000010D2", '0');
		check_trace(2, x"000010D0", '1', x"2000");
		check_trace(3, x"000010D2", '1', x"0049");
		assert memory(16#10D2# / 2) = x"0049"
			report "short descriptor U bit was not stored" severity failure;

		-- Mixed long/short/long tree. Accrued WP suppresses page M update.
		load_word(x"00001018", x"7FFF");
		load_word(x"0000101A", x"0002");
		load_word(x"0000101C", x"0000");
		load_word(x"0000101E", x"3000");
		load_word(x"00003014", x"0000");
		load_word(x"00003016", x"400F");
		load_word(x"00004048", x"0000");
		load_word(x"0000404A", x"0041");
		load_word(x"0000404C", x"5000");
		load_word(x"0000404E", x"0000");
		crp <= x"7FFF000300001000";
		tc <= x"80884660";
		reset_trace;
		run_walk(x"AB31497A", "101", '1');
		assert mapping_valid = '1' and physical_address = x"5000007A"
			report "mixed-format table translation failed" severity failure;
		assert write_protected = '1' and modified = '0' and cache_inhibit = '1'
			report "mixed-format accrued attributes failed" severity failure;
		assert supervisor_violation = '0' and descriptor_count = "011"
			report "mixed-format table-search status failed" severity failure;
		assert trace_count = 14
			report "mixed-format table-search bus count mismatch" severity failure;
		check_trace(0, x"00001018", '0');
		check_trace(1, x"0000101A", '0');
		check_trace(2, x"0000101C", '0');
		check_trace(3, x"0000101E", '0');
		check_trace(4, x"00001018", '1', x"7FFF");
		check_trace(5, x"0000101A", '1', x"000A");
		check_trace(6, x"00003014", '0');
		check_trace(7, x"00003016", '0');
		check_trace(8, x"00004048", '0');
		check_trace(9, x"0000404A", '0');
		check_trace(10, x"0000404C", '0');
		check_trace(11, x"0000404E", '0');
		check_trace(12, x"00004048", '1', x"0000");
		check_trace(13, x"0000404A", '1', x"0049");
		assert memory(16#404A# / 2) = x"0049"
			report "write-protected page history update was incorrect" severity failure;

		-- Once an S bit rejects a user access, no later descriptor is updated.
		load_word(x"00001018", x"7FFF");
		load_word(x"0000101A", x"0102");
		load_word(x"00003014", x"0000");
		load_word(x"00003016", x"4003");
		load_word(x"00004048", x"0000");
		load_word(x"0000404A", x"0001");
		reset_trace;
		run_walk(x"AB31497A", "001", '0');
		assert mapping_valid = '1' and physical_address = x"5000007A" and
			supervisor_violation = '1'
			report "long table supervisor protection did not accrue" severity failure;
		assert trace_count = 10
			report "supervisor violation performed a history write" severity failure;
		assert memory(16#101A# / 2) = x"0102" and
			memory(16#3016# / 2) = x"4003" and
			memory(16#404A# / 2) = x"0001"
			report "supervisor violation changed descriptor history" severity failure;

		-- A pointer limit is checked after that pointer's U-bit update.
		load_word(x"00001018", x"0004");
		load_word(x"0000101A", x"0002");
		reset_trace;
		run_walk(x"AB31497A", "101", '0');
		assert mapping_valid = '0' and limit_violation = '1' and
			descriptor_count = "001"
			report "long table descriptor limit was not enforced" severity failure;
		assert trace_count = 6 and memory(16#101A# / 2) = x"000A"
			report "pointer limit history ordering failed" severity failure;

		-- All four configurable logical table-index levels are traversable.
		load_word(x"00001004", x"0000");
		load_word(x"00001006", x"200A");
		load_word(x"00002008", x"0000");
		load_word(x"0000200A", x"300A");
		load_word(x"0000300C", x"0000");
		load_word(x"0000300E", x"400A");
		load_word(x"00004010", x"8000");
		load_word(x"00004012", x"0009");
		crp <= x"7FFF000200001000";
		tc <= x"80884444";
		reset_trace;
		run_walk(x"AA123456", "001", '0');
		assert mapping_valid = '1' and physical_address = x"80000056" and
			descriptor_count = "100"
			report "four-level table translation failed" severity failure;
		assert trace_count = 8
			report "four-level table bus count mismatch" severity failure;

		-- A leaf indirect descriptor fetches the indicated long page descriptor.
		load_word(x"000010D0", x"0000");
		load_word(x"000010D2", x"1803");
		load_word(x"00001800", x"0000");
		load_word(x"00001802", x"0001");
		load_word(x"00001804", x"7000");
		load_word(x"00001806", x"0000");
		crp <= x"7FFF000200001000";
		tc <= x"80CC8000";
		reset_trace;
		run_walk(x"ABC34123", "001", '0');
		assert mapping_valid = '1' and physical_address = x"70000123"
			report "indirect page translation failed" severity failure;
		assert descriptor_count = "010" and final_descriptor_address = x"00001800"
			report "indirect descriptor accounting failed" severity failure;
		assert trace_count = 8
			report "indirect descriptor bus count mismatch" severity failure;
		check_trace(0, x"000010D0", '0');
		check_trace(1, x"000010D2", '0');
		check_trace(2, x"00001800", '0');
		check_trace(3, x"00001802", '0');
		check_trace(4, x"00001804", '0');
		check_trace(5, x"00001806", '0');
		check_trace(6, x"00001800", '1', x"0000");
		check_trace(7, x"00001802", '1', x"0009");

		-- Long early termination includes unused table-index bits in the offset.
		load_word(x"00001090", x"0040");
		load_word(x"00001092", x"0001");
		load_word(x"00001094", x"6000");
		load_word(x"00001096", x"0000");
		crp <= x"7FFF000300001000";
		tc <= x"80888800";
		reset_trace;
		run_walk(x"AA123456", "001", '0');
		assert mapping_valid = '1' and physical_address = x"60003456"
			report "early-termination mapping failed" severity failure;
		assert trace_count = 6 and descriptor_count = "001"
			report "early-termination bus sequence failed" severity failure;

		-- The page history update precedes a detected early-termination limit fault.
		load_word(x"00001090", x"0020");
		load_word(x"00001092", x"0001");
		reset_trace;
		run_walk(x"AA123456", "001", '0');
		assert mapping_valid = '0' and limit_violation = '1'
			report "early-termination limit violation was not reported" severity failure;
		assert trace_count = 6 and memory(16#1092# / 2) = x"0009"
			report "limit-fault page history ordering failed" severity failure;

		-- Root page descriptors use unsigned constant-offset mapping and always limit TIA.
		crp <= x"0012000100010000";
		tc <= x"81888800";
		reset_trace;
		run_walk(x"AA123456", "001", '0');
		assert mapping_valid = '1' and physical_address = x"AA133456"
			report "root page direct mapping failed" severity failure;
		assert trace_count = 0
			report "root page direct mapping accessed memory" severity failure;
		crp <= x"0011000100010000";
		run_walk(x"AA123456", "001", '0');
		assert mapping_valid = '0' and limit_violation = '1'
			report "root page limit was skipped with FCL enabled" severity failure;

		-- An invalid memory descriptor terminates without a history update.
		load_word(x"000010D0", x"DEAD");
		load_word(x"000010D2", x"BEEC");
		crp <= x"7FFF000200001000";
		tc <= x"80CC8000";
		reset_trace;
		run_walk(x"ABC34123", "001", '0');
		assert mapping_valid = '0' and invalid_descriptor = '1' and
			descriptor_count = "001" and trace_count = 2
			report "invalid memory descriptor handling failed" severity failure;

		-- Physical wait states hold the current descriptor transfer and CPU stall.
		load_word(x"000010D0", x"2000");
		load_word(x"000010D2", x"0009");
		crp <= x"7FFF000200001000";
		tc <= x"80CC8000";
		reset_trace;
		allow_ready <= '0';
		logical_address <= x"ABC34123";
		function_code <= "001";
		write_access <= '0';
		start <= '1';
		wait until rising_edge(clk);
		start <= '0';
		wait until bus_request = '1';
		for wait_cycle in 1 to 3 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			assert bus_request = '1' and bus_address = x"000010D0" and
				bus_lock = '1' and busy = '1'
				report "descriptor transfer changed during a wait state" severity failure;
		end loop;
		assert trace_count = 0
			report "wait-state descriptor transfer completed early" severity failure;
		allow_ready <= '1';
		wait until done = '1' for 2 us;
		assert done = '1' and mapping_valid = '1' and trace_count = 2
			report "wait-state table search did not resume correctly" severity failure;

		-- Descriptor read and history-write failures retain the exact failing address.
		load_word(x"000010D0", x"2000");
		load_word(x"000010D2", x"0001");
		crp <= x"7FFF000200001000";
		tc <= x"80CC8000";
		inject_error <= '1';
		inject_error_on_write <= '0';
		error_address <= x"000010D2";
		reset_trace;
		run_walk(x"ABC34123", "001", '0');
		assert walk_bus_error = '1' and fault_descriptor_address = x"000010D2" and
			fault_during_update = '0' and mapping_valid = '0'
			report "descriptor read bus error classification failed" severity failure;
		assert trace_count = 2
			report "descriptor read bus error cycle count failed" severity failure;

		inject_error_on_write <= '1';
		reset_trace;
		run_walk(x"ABC34123", "001", '0');
		assert walk_bus_error = '1' and fault_descriptor_address = x"000010D2" and
			fault_during_update = '1' and mapping_valid = '0'
			report "descriptor update bus error classification failed" severity failure;
		assert trace_count = 4
			report "descriptor update bus error cycle count failed" severity failure;
		inject_error <= '0';

		report "PASS: MC68030 MMU physical table walker" severity note;
		stop;
	end process;
end architecture;
