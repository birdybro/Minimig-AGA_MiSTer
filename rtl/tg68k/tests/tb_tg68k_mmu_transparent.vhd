library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_transparent is
end entity;

architecture test of tb_tg68k_mmu_transparent is
	signal logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code : std_logic_vector(2 downto 0) := (others => '0');
	signal write_access : std_logic := '0';
	signal read_modify_write : std_logic := '0';
	signal tt0 : mmu_tt_t := (others => '0');
	signal tt1 : mmu_tt_t := (others => '0');
	signal cpu_space_access : std_logic;
	signal tt0_match : std_logic;
	signal tt1_match : std_logic;
	signal transparent_match : std_logic;
	signal translation_bypass : std_logic;
	signal physical_address : std_logic_vector(31 downto 0);
	signal cache_inhibit : std_logic;
begin
	dut : entity work.TG68K_MMU_Transparent
		port map(
			logical_address => logical_address,
			function_code => function_code,
			write_access => write_access,
			read_modify_write => read_modify_write,
			tt0 => tt0,
			tt1 => tt1,
			cpu_space_access => cpu_space_access,
			tt0_match => tt0_match,
			tt1_match => tt1_match,
			transparent_match => transparent_match,
			translation_bypass => translation_bypass,
			physical_address => physical_address,
			cache_inhibit => cache_inhibit
		);

	stimulus : process
		procedure check_result(
			constant expected_cpu_space : std_logic;
			constant expected_tt0 : std_logic;
			constant expected_tt1 : std_logic;
			constant expected_ci : std_logic) is
		begin
			wait for 1 ns;
			assert cpu_space_access = expected_cpu_space and
				tt0_match = expected_tt0 and tt1_match = expected_tt1
				report "transparent translation classification mismatch" severity failure;
			assert transparent_match = (expected_tt0 or expected_tt1) and
				translation_bypass = (expected_cpu_space or expected_tt0 or expected_tt1)
				report "transparent translation bypass mismatch" severity failure;
			assert cache_inhibit = expected_ci
				report "transparent translation cache attribute mismatch" severity failure;
			assert physical_address = logical_address
				report "transparent translation changed the logical address" severity failure;
		end procedure;
	begin
		check_result('0', '0', '0', '0');

		-- Exact supervisor-data read block with caching inhibited.
		tt0 <= x"12008650";
		logical_address <= x"12345678";
		function_code <= "101";
		write_access <= '0';
		check_result('0', '1', '0', '1');
		write_access <= '1';
		check_result('0', '0', '0', '0');
		function_code <= "100";
		write_access <= '0';
		check_result('0', '0', '0', '0');
		function_code <= "101";
		logical_address <= x"13345678";
		check_result('0', '0', '0', '0');

		-- RWM admits both ordinary directions and locked read-modify-write cycles.
		tt0 <= x"12008750";
		logical_address <= x"12ABCDEF";
		write_access <= '1';
		check_result('0', '1', '0', '1');
		read_modify_write <= '1';
		write_access <= '0';
		check_result('0', '1', '0', '1');
		write_access <= '1';
		check_result('0', '1', '0', '1');
		tt0 <= x"12008650";
		check_result('0', '0', '0', '0');
		read_modify_write <= '0';

		-- Set mask bits ignore the corresponding address and FC base bits.
		tt0 <= x"A50F8121";
		logical_address <= x"AAF01234";
		function_code <= "011";
		write_access <= '0';
		check_result('0', '1', '0', '0');
		logical_address <= x"B5F01234";
		check_result('0', '0', '0', '0');
		function_code <= "000";
		logical_address <= x"AFF01234";
		check_result('0', '0', '0', '0');

		-- Overlapping registers OR CI only from registers that actually qualify.
		tt0 <= x"00FF8707";
		tt1 <= x"00FF8307";
		logical_address <= x"55FFFFFF";
		function_code <= "010";
		write_access <= '0';
		check_result('0', '1', '1', '1');
		tt0 <= x"00FF8407";
		check_result('0', '0', '1', '0');

		-- CPU space bypasses both TTs and never inherits their CI state.
		tt0 <= x"00FF8707";
		tt1 <= x"00FF8707";
		function_code <= "111";
		check_result('1', '0', '0', '0');

		report "PASS: MC68030 MMU transparent translation" severity note;
		stop;
	end process;
end architecture;
