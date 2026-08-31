library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_descriptor is
end entity;

architecture test of tb_tg68k_mmu_descriptor is
	signal descriptor_data : std_logic_vector(63 downto 0) := (others => '0');
	signal descriptor_format : mmu_descriptor_format_t := MMU_DESCRIPTOR_ROOT;
	signal leaf_level : std_logic := '0';
	signal descriptor_info : mmu_descriptor_info_t;
begin
	dut : entity work.TG68K_MMU_Decoder
		port map(
			descriptor_data => descriptor_data,
			descriptor_format => descriptor_format,
			leaf_level => leaf_level,
			descriptor_info => descriptor_info
		);

	stimulus : process
		procedure check_descriptor(
			constant value : std_logic_vector(63 downto 0);
			constant format : mmu_descriptor_format_t;
			constant is_leaf : std_logic;
			constant expected : mmu_descriptor_info_t) is
		begin
			descriptor_data <= value;
			descriptor_format <= format;
			leaf_level <= is_leaf;
			wait for 1 ns;
			assert descriptor_info = expected
				report "MMU descriptor decode mismatch" severity failure;
		end procedure;

		variable expected : mmu_descriptor_info_t;
	begin
		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		check_descriptor(x"0000000000000000", MMU_DESCRIPTOR_ROOT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_PAGE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_PAGE;
		expected.address_field := x"10000000";
		expected.limit_present := '1';
		expected.limit := std_logic_vector'(14 downto 0 => '0');
		expected.limit(4) := '1';
		expected.early_termination := '1';
		check_descriptor(x"001000011000000F", MMU_DESCRIPTOR_ROOT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_TABLE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_LONG;
		expected.next_format := MMU_DESCRIPTOR_LONG;
		expected.address_field := x"12345670";
		expected.limit_present := '1';
		expected.limit_lower := '1';
		expected.limit := std_logic_vector'(14 downto 0 => '0');
		expected.limit(8) := '1';
		expected.limit(5) := '1';
		expected.limit(1 downto 0) := "11";
		check_descriptor(x"812300031234567F", MMU_DESCRIPTOR_ROOT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_INVALID;
		check_descriptor(x"00000000FFFFFFFC", MMU_DESCRIPTOR_SHORT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_TABLE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_SHORT;
		expected.address_field := x"12345670";
		expected.used := '1';
		expected.write_protect := '1';
		check_descriptor(x"000000001234567E", MMU_DESCRIPTOR_SHORT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_TABLE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_LONG;
		expected.next_format := MMU_DESCRIPTOR_LONG;
		expected.address_field := x"ABCDEF00";
		check_descriptor(x"00000000ABCDEF03", MMU_DESCRIPTOR_SHORT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_PAGE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_PAGE;
		expected.address_field := x"89ABCD00";
		expected.cache_inhibit := '1';
		expected.write_protect := '1';
		expected.used := '1';
		expected.modified := '1';
		check_descriptor(x"0000000089ABCD5D", MMU_DESCRIPTOR_SHORT,
			'1', expected);
		expected.early_termination := '1';
		check_descriptor(x"0000000089ABCD5D", MMU_DESCRIPTOR_SHORT,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_INDIRECT;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_SHORT;
		expected.address_field := x"CAFEBABC";
		check_descriptor(x"00000000CAFEBABE", MMU_DESCRIPTOR_SHORT,
			'1', expected);
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_LONG;
		expected.next_format := MMU_DESCRIPTOR_LONG;
		expected.address_field := x"01234564";
		check_descriptor(x"0000000001234567", MMU_DESCRIPTOR_SHORT,
			'1', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		check_descriptor(x"FFFFFFFC12345678", MMU_DESCRIPTOR_LONG,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_TABLE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_SHORT;
		expected.address_field := x"2468ACE0";
		expected.limit_present := '1';
		expected.limit_lower := '1';
		expected.limit := std_logic_vector'(14 downto 0 => '0');
		expected.limit(12) := '1';
		expected.limit(9) := '1';
		expected.limit(5 downto 4) := "11";
		expected.limit(2) := '1';
		expected.supervisor_only := '1';
		expected.write_protect := '1';
		expected.used := '1';
		check_descriptor(x"9234FD0E2468ACEF", MMU_DESCRIPTOR_LONG,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_PAGE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_PAGE;
		expected.address_field := x"13579B00";
		expected.supervisor_only := '1';
		expected.cache_inhibit := '1';
		expected.write_protect := '1';
		expected.used := '1';
		expected.modified := '1';
		check_descriptor(x"BEEFFD5D13579BFF", MMU_DESCRIPTOR_LONG,
			'1', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_PAGE;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_PAGE;
		expected.address_field := x"1000AA00";
		expected.limit_present := '1';
		expected.limit_lower := '1';
		expected.limit := std_logic_vector'(14 downto 0 => '0');
		expected.limit(8) := '1';
		expected.limit(5) := '1';
		expected.limit(1 downto 0) := "11";
		expected.early_termination := '1';
		check_descriptor(x"8123FC011000AAFF", MMU_DESCRIPTOR_LONG,
			'0', expected);

		expected := MMU_DESCRIPTOR_INFO_DEFAULT;
		expected.kind := MMU_DESCRIPTOR_INDIRECT;
		expected.descriptor_type := MMU_DESCRIPTOR_TYPE_LONG;
		expected.next_format := MMU_DESCRIPTOR_LONG;
		expected.address_field := x"CAFEBABC";
		check_descriptor(x"DEADFD0FCAFEBABE", MMU_DESCRIPTOR_LONG,
			'1', expected);

		report "PASS: MC68030 MMU descriptor decoding" severity note;
		stop;
	end process;
end architecture;
