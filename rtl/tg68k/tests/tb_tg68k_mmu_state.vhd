library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_state is
end entity;

architecture test of tb_tg68k_mmu_state is
	constant CLK_PERIOD : time := 10 ns;

	signal clk : std_logic := '0';
	signal nreset : std_logic := '0';
	signal register_select : mmu_register_t := MMU_REG_TC;
	signal register_write : std_logic := '0';
	signal register_write_data : std_logic_vector(63 downto 0) := (others => '0');
	signal flush_disable : std_logic := '0';
	signal register_read_data : std_logic_vector(63 downto 0);
	signal configuration_exception : std_logic;
	signal atc_flush_all : std_logic;
	signal translation_enabled : std_logic;
	signal supervisor_root_enabled : std_logic;
	signal function_code_lookup_enabled : std_logic;
	signal crp : mmu_root_pointer_t;
	signal srp : mmu_root_pointer_t;
	signal tc : mmu_tc_t;
	signal tt0 : mmu_tt_t;
	signal tt1 : mmu_tt_t;
	signal mmusr : mmu_status_t;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_MMU
		port map(
			clk => clk,
			nReset => nreset,
			register_select => register_select,
			register_write => register_write,
			register_write_data => register_write_data,
			flush_disable => flush_disable,
			register_read_data => register_read_data,
			configuration_exception => configuration_exception,
			atc_flush_all => atc_flush_all,
			translation_enabled => translation_enabled,
			supervisor_root_enabled => supervisor_root_enabled,
			function_code_lookup_enabled => function_code_lookup_enabled,
			crp_out => crp,
			srp_out => srp,
			tc_out => tc,
			tt0_out => tt0,
			tt1_out => tt1,
			mmusr_out => mmusr
		);

	stimulus : process
		procedure pmove_write(
			constant selected_register : mmu_register_t;
			constant value : std_logic_vector(63 downto 0);
			constant disable_flush : std_logic;
			constant expect_exception : std_logic;
			constant expect_flush : std_logic) is
		begin
			wait until falling_edge(clk);
			register_select <= selected_register;
			register_write_data <= value;
			flush_disable <= disable_flush;
			register_write <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			register_write <= '0';
			assert configuration_exception = expect_exception
				report "unexpected MMU configuration exception state" severity failure;
			assert atc_flush_all = expect_flush
				report "unexpected MMU ATC flush request" severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert configuration_exception = '0'
				report "MMU configuration exception was not a pulse" severity failure;
			assert atc_flush_all = '0'
				report "MMU ATC flush request was not a pulse" severity failure;
		end procedure;

		procedure check_read(
			constant selected_register : mmu_register_t;
			constant expected_value : std_logic_vector(63 downto 0)) is
		begin
			register_select <= selected_register;
			wait for 1 ns;
			assert register_read_data = expected_value
				report "MMU register readback mismatch" severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert crp = x"0000000000000000" and srp = x"0000000000000000"
			report "root pointers did not reset" severity failure;
		assert tc = x"00000000" and tt0 = x"00000000" and
			tt1 = x"00000000" and mmusr = x"0000"
			report "MMU control state did not reset" severity failure;
		assert translation_enabled = '0'
			report "translation enabled during reset" severity failure;

		wait until falling_edge(clk);
		nreset <= '1';

		pmove_write(MMU_REG_TC, x"0000000083F04445", '0', '0', '1');
		assert tc = x"83F04445" and translation_enabled = '1' and
			supervisor_root_enabled = '1' and
			function_code_lookup_enabled = '1'
			report "valid TC state was not loaded" severity failure;
		check_read(MMU_REG_TC, x"0000000083F04445");

		pmove_write(MMU_REG_TC, x"0000000083F04444", '0', '1', '1');
		assert tc = x"03F04444" and translation_enabled = '0'
			report "invalid enabled TC did not load with E cleared" severity failure;

		pmove_write(MMU_REG_TC, x"0000000000700000", '1', '1', '0');
		assert tc = x"00700000"
			report "reserved TC page size was not retained with E clear"
			severity failure;

		pmove_write(MMU_REG_TC, x"0000000000800000", '1', '0', '0');
		assert tc = x"00800000"
			report "disabled TC incorrectly required a complete table split"
			severity failure;

		pmove_write(MMU_REG_TC, x"000000008088880F", '1', '0', '0');
		assert tc = x"8088880F"
			report "TC fields after the first zero were not ignored"
			severity failure;

		pmove_write(MMU_REG_CRP, x"8000000312345678", '1', '0', '0');
		assert crp = x"8000000312345670"
			report "valid CRP was not loaded or unused bits were retained"
			severity failure;
		check_read(MMU_REG_CRP, x"8000000312345670");

		pmove_write(MMU_REG_SRP, x"000000020000100F", '0', '0', '1');
		assert srp = x"0000000200001000"
			report "valid SRP was not loaded" severity failure;

		pmove_write(MMU_REG_CRP, x"0000000012345678", '0', '1', '1');
		assert crp = x"0000000012345670"
			report "invalid CRP was not loaded before the exception"
			severity failure;

		pmove_write(MMU_REG_TT0, x"00000000A5A5FFFF", '0', '0', '1');
		assert tt0 = x"A5A58777"
			report "TT0 implemented fields were not preserved" severity failure;
		check_read(MMU_REG_TT0, x"00000000A5A58777");

		pmove_write(MMU_REG_TT1, x"000000005A5AFFFF", '1', '0', '0');
		assert tt1 = x"5A5A8777"
			report "TT1 implemented fields were not preserved" severity failure;

		pmove_write(MMU_REG_MMUSR, x"FFFFFFFFFFFFFFFF", '0', '0', '0');
		assert mmusr = MMU_STATUS_IMPLEMENTED_MASK
			report "MMUSR implemented fields were not preserved" severity failure;
		check_read(MMU_REG_MMUSR, x"000000000000EE47");

		wait until falling_edge(clk);
		nreset <= '0';
		wait until rising_edge(clk);
		wait for 1 ns;
		assert crp = x"0000000012345670" and srp = x"0000000200001000"
			report "root pointers changed across reset" severity failure;
		assert tc = x"0088880F" and tt0 = x"A5A50777" and
			tt1 = x"5A5A0777" and mmusr = x"EE47"
			report "reset changed MMU state other than TC.E and TTx.E"
			severity failure;
		assert translation_enabled = '0'
			report "translation remained enabled after reset" severity failure;

		report "PASS: MC68030 MMU architectural state" severity note;
		stop;
	end process;
end architecture;
