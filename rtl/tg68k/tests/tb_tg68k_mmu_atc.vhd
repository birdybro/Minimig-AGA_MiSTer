library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_atc is
end entity;

architecture test of tb_tg68k_mmu_atc is
	constant CLK_PERIOD : time := 10 ns;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal page_size : std_logic_vector(3 downto 0) := x"8";
	signal lookup_request : std_logic := '0';
	signal lookup_logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal lookup_function_code : std_logic_vector(2 downto 0) := (others => '0');
	signal lookup_write : std_logic := '0';
	signal lookup_match : std_logic;
	signal lookup_hit : std_logic;
	signal lookup_requires_walk : std_logic;
	signal lookup_physical_address : std_logic_vector(31 downto 0);
	signal lookup_cache_inhibit : std_logic;
	signal lookup_write_protected : std_logic;
	signal lookup_modified : std_logic;
	signal lookup_bus_error : std_logic;
	signal fill_request : std_logic := '0';
	signal fill_logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal fill_function_code : std_logic_vector(2 downto 0) := (others => '0');
	signal fill_physical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal fill_cache_inhibit : std_logic := '0';
	signal fill_write_protected : std_logic := '0';
	signal fill_modified : std_logic := '0';
	signal fill_bus_error : std_logic := '0';
	signal flush_all : std_logic := '0';
	signal flush_request : std_logic := '0';
	signal flush_by_address : std_logic := '0';
	signal flush_logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal flush_function_code_base : std_logic_vector(2 downto 0) := (others => '0');
	signal flush_function_code_mask : std_logic_vector(2 downto 0) := (others => '0');
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_MMU_ATC
		port map(
			clk => clk,
			nReset => nReset,
			page_size => page_size,
			lookup_request => lookup_request,
			lookup_logical_address => lookup_logical_address,
			lookup_function_code => lookup_function_code,
			lookup_write => lookup_write,
			lookup_match => lookup_match,
			lookup_hit => lookup_hit,
			lookup_requires_walk => lookup_requires_walk,
			lookup_physical_address => lookup_physical_address,
			lookup_cache_inhibit => lookup_cache_inhibit,
			lookup_write_protected => lookup_write_protected,
			lookup_modified => lookup_modified,
			lookup_bus_error => lookup_bus_error,
			fill_request => fill_request,
			fill_logical_address => fill_logical_address,
			fill_function_code => fill_function_code,
			fill_physical_address => fill_physical_address,
			fill_cache_inhibit => fill_cache_inhibit,
			fill_write_protected => fill_write_protected,
			fill_modified => fill_modified,
			fill_bus_error => fill_bus_error,
			flush_all => flush_all,
			flush_request => flush_request,
			flush_by_address => flush_by_address,
			flush_logical_address => flush_logical_address,
			flush_function_code_base => flush_function_code_base,
			flush_function_code_mask => flush_function_code_mask
		);

	stimulus : process
		procedure pulse_fill(
			constant logical_value : std_logic_vector(31 downto 0);
			constant fc_value : std_logic_vector(2 downto 0);
			constant physical_value : std_logic_vector(31 downto 0);
			constant ci_value : std_logic;
			constant wp_value : std_logic;
			constant m_value : std_logic;
			constant b_value : std_logic) is
		begin
			fill_logical_address <= logical_value;
			fill_function_code <= fc_value;
			fill_physical_address <= physical_value;
			fill_cache_inhibit <= ci_value;
			fill_write_protected <= wp_value;
			fill_modified <= m_value;
			fill_bus_error <= b_value;
			fill_request <= '1';
			wait until rising_edge(clk);
			fill_request <= '0';
			wait for 1 ns;
		end procedure;

		procedure pulse_flush_all is
		begin
			flush_all <= '1';
			wait until rising_edge(clk);
			flush_all <= '0';
			wait for 1 ns;
		end procedure;

		procedure pulse_flush(
			constant by_address : std_logic;
			constant logical_value : std_logic_vector(31 downto 0);
			constant fc_base : std_logic_vector(2 downto 0);
			constant fc_mask : std_logic_vector(2 downto 0)) is
		begin
			flush_by_address <= by_address;
			flush_logical_address <= logical_value;
			flush_function_code_base <= fc_base;
			flush_function_code_mask <= fc_mask;
			flush_request <= '1';
			wait until rising_edge(clk);
			flush_request <= '0';
			wait for 1 ns;
		end procedure;

		procedure check_lookup(
			constant logical_value : std_logic_vector(31 downto 0);
			constant fc_value : std_logic_vector(2 downto 0);
			constant write_value : std_logic;
			constant expected_match : std_logic;
			constant expected_hit : std_logic;
			constant expected_walk : std_logic;
			constant expected_physical : std_logic_vector(31 downto 0);
			constant expected_ci : std_logic;
			constant expected_wp : std_logic;
			constant expected_m : std_logic;
			constant expected_b : std_logic) is
		begin
			lookup_logical_address <= logical_value;
			lookup_function_code <= fc_value;
			lookup_write <= write_value;
			lookup_request <= '1';
			wait for 1 ns;
			assert lookup_match = expected_match and lookup_hit = expected_hit and
				lookup_requires_walk = expected_walk
				report "ATC lookup classification mismatch" severity failure;
			if expected_match = '1' then
				assert lookup_physical_address = expected_physical
					report "ATC physical translation mismatch" severity failure;
				assert lookup_cache_inhibit = expected_ci and
					lookup_write_protected = expected_wp and
					lookup_modified = expected_m and lookup_bus_error = expected_b
					report "ATC status attribute mismatch" severity failure;
			end if;
			wait until rising_edge(clk);
			lookup_request <= '0';
			wait for 1 ns;
		end procedure;

		variable logical_value : unsigned(31 downto 0);
		variable physical_value : unsigned(31 downto 0);
	begin
		wait for 2 * CLK_PERIOD;
		nReset <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;

		check_lookup(x"12345678", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');

		-- Basic 256-byte entry, exact FC tag, and retained status attributes.
		pulse_fill(x"123456A5", "001", x"ABCDEFA5", '1', '0', '1', '0');
		check_lookup(x"1234565A", "001", '0', '1', '1', '0',
			x"ABCDEF5A", '1', '0', '1', '0');
		check_lookup(x"1234565A", "101", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');

		-- RESET disables translation elsewhere but does not invalidate the ATC.
		nReset <= '0';
		wait until rising_edge(clk);
		wait until rising_edge(clk);
		nReset <= '1';
		wait for 1 ns;
		check_lookup(x"12345611", "001", '0', '1', '1', '0',
			x"ABCDEF11", '1', '0', '1', '0');

		-- Current PS controls both tag comparison and physical page-index insertion.
		pulse_flush_all;
		page_size <= x"C";
		pulse_fill(x"12345ABC", "010", x"80000ABC", '0', '0', '1', '0');
		check_lookup(x"12345FED", "010", '0', '1', '1', '0',
			x"80000FED", '0', '0', '1', '0');
		check_lookup(x"12346FED", "010", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');

		-- A clean write to an unmodified entry invalidates it and requests a walk.
		pulse_flush_all;
		page_size <= x"8";
		pulse_fill(x"01000000", "001", x"02000000", '0', '0', '0', '0');
		check_lookup(x"01000044", "001", '1', '1', '0', '1',
			x"02000044", '0', '0', '0', '0');
		check_lookup(x"01000044", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');

		-- WP and B entries fault on the hit and do not trigger M-bit table searches.
		pulse_fill(x"01000000", "001", x"02000000", '0', '1', '0', '0');
		check_lookup(x"01000044", "001", '1', '1', '1', '0',
			x"02000044", '0', '1', '0', '0');
		check_lookup(x"01000044", "001", '0', '1', '1', '0',
			x"02000044", '0', '1', '0', '0');
		pulse_flush_all;
		pulse_fill(x"03000000", "101", x"00000000", '0', '0', '0', '1');
		check_lookup(x"03000022", "101", '1', '1', '1', '0',
			x"00000022", '0', '0', '0', '1');
		check_lookup(x"03000022", "101", '0', '1', '1', '0',
			x"00000022", '0', '0', '0', '1');

		-- Fill all 22 entries, then verify deterministic history-bit replacement.
		pulse_flush_all;
		for entry_number in 0 to MMU_ATC_ENTRY_COUNT - 1 loop
			logical_value := to_unsigned(entry_number * 16#100#, 32);
			physical_value := to_unsigned(16#10000000# + entry_number * 16#100#, 32);
			pulse_fill(std_logic_vector(logical_value), "001",
				std_logic_vector(physical_value), '0', '0', '1', '0');
		end loop;
		pulse_fill(x"00002000", "001", x"20002000", '0', '0', '1', '0');
		check_lookup(x"00000020", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');
		check_lookup(x"00000120", "001", '0', '1', '1', '0',
			x"10000120", '0', '0', '1', '0');
		check_lookup(x"00001520", "001", '0', '1', '1', '0',
			x"10001520", '0', '0', '1', '0');
		check_lookup(x"00002020", "001", '0', '1', '1', '0',
			x"20002020", '0', '0', '1', '0');
		pulse_fill(x"00002100", "001", x"20002100", '0', '0', '1', '0');
		check_lookup(x"00000220", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');
		check_lookup(x"00000120", "001", '0', '1', '1', '0',
			x"10000120", '0', '0', '1', '0');

		-- Replacement always consumes an invalid entry before an older valid entry.
		pulse_flush('1', x"00001577", "001", "111");
		pulse_fill(x"00002200", "001", x"20002200", '0', '0', '1', '0');
		check_lookup(x"00000320", "001", '0', '1', '1', '0',
			x"10000320", '0', '0', '1', '0');
		check_lookup(x"00001520", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');
		check_lookup(x"00002220", "001", '0', '1', '1', '0',
			x"20002220", '0', '0', '1', '0');

		-- Selective flushes combine the optional page tag and compare-enable FC mask.
		pulse_flush_all;
		pulse_fill(x"00004000", "001", x"A0004000", '0', '0', '1', '0');
		pulse_fill(x"00004000", "101", x"B0004000", '0', '0', '1', '0');
		pulse_fill(x"00005000", "001", x"A0005000", '0', '0', '1', '0');
		pulse_flush('1', x"000040AA", "001", "111");
		check_lookup(x"00004011", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');
		check_lookup(x"00004011", "101", '0', '1', '1', '0',
			x"B0004011", '0', '0', '1', '0');
		check_lookup(x"00005011", "001", '0', '1', '1', '0',
			x"A0005011", '0', '0', '1', '0');
		pulse_flush('0', x"00000000", "000", "100");
		check_lookup(x"00005011", "001", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');
		check_lookup(x"00004011", "101", '0', '1', '1', '0',
			x"B0004011", '0', '0', '1', '0');
		pulse_flush_all;
		check_lookup(x"00004011", "101", '0', '0', '0', '1',
			x"00000000", '0', '0', '0', '0');

		report "PASS: MC68030 MMU 22-entry ATC" severity note;
		stop;
	end process;
end architecture;
