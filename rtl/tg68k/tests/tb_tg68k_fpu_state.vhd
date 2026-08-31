library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_state is
end entity;

architecture test of tb_tg68k_fpu_state is
	constant CLK_PERIOD : time := 10 ns;

	signal clk : std_logic := '0';
	signal nreset : std_logic := '0';
	signal null_restore : std_logic := '0';
	signal data_register_select : std_logic_vector(2 downto 0) := "000";
	signal data_register_write : std_logic := '0';
	signal data_register_write_data : fpu_extended_t := (others => '0');
	signal data_register_read_data : fpu_extended_t;
	signal control_register_select : fpu_control_register_t := FPU_REG_FPCR;
	signal control_register_write : std_logic := '0';
	signal control_register_write_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal control_register_read_data : std_logic_vector(31 downto 0);
	signal fp_registers : fpu_register_array_t;
	signal fpcr : std_logic_vector(31 downto 0);
	signal fpsr : std_logic_vector(31 downto 0);
	signal fpiar : std_logic_vector(31 downto 0);
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU
		port map(
			clk => clk,
			nReset => nreset,
			null_restore => null_restore,
			data_register_select => data_register_select,
			data_register_write => data_register_write,
			data_register_write_data => data_register_write_data,
			data_register_read_data => data_register_read_data,
			control_register_select => control_register_select,
			control_register_write => control_register_write,
			control_register_write_data => control_register_write_data,
			control_register_read_data => control_register_read_data,
			fp_registers_out => fp_registers,
			fpcr_out => fpcr,
			fpsr_out => fpsr,
			fpiar_out => fpiar
		);

	stimulus : process
		procedure write_data_register(
			constant index : natural;
			constant value : fpu_extended_t) is
		begin
			wait until falling_edge(clk);
			data_register_select <= std_logic_vector(to_unsigned(index, 3));
			data_register_write_data <= value;
			data_register_write <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			data_register_write <= '0';
		end procedure;

		procedure write_control_register(
			constant selected_register : fpu_control_register_t;
			constant value : std_logic_vector(31 downto 0)) is
		begin
			wait until falling_edge(clk);
			control_register_select <= selected_register;
			control_register_write_data <= value;
			control_register_write <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			control_register_write <= '0';
		end procedure;

		procedure check_control_register(
			constant selected_register : fpu_control_register_t;
			constant value : std_logic_vector(31 downto 0)) is
		begin
			control_register_select <= selected_register;
			wait for 1 ns;
			assert control_register_read_data = value
				report "FPU control register readback mismatch" severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		wait for 1 ns;
		for index in fp_registers'range loop
			assert fp_registers(index) = FPU_RESET_NAN
				report "FPU data register did not reset to positive quiet NaN"
				severity failure;
		end loop;
		assert fpcr = x"00000000" and fpsr = x"00000000" and
			fpiar = x"00000000"
			report "FPU control state did not reset" severity failure;

		wait until falling_edge(clk);
		nreset <= '1';
		for index in 0 to 7 loop
			write_data_register(index,
				std_logic_vector(to_unsigned(index + 1, 16)) &
				x"0123456789ABCDEF");
		end loop;
		for index in 0 to 7 loop
			data_register_select <= std_logic_vector(to_unsigned(index, 3));
			wait for 1 ns;
			assert data_register_read_data =
				std_logic_vector(to_unsigned(index + 1, 16)) &
				x"0123456789ABCDEF"
				report "FPU data register readback mismatch" severity failure;
		end loop;

		write_control_register(FPU_REG_FPCR, x"FFFFFFFF");
		write_control_register(FPU_REG_FPSR, x"A55AA55A");
		write_control_register(FPU_REG_FPIAR, x"12345678");
		assert fpcr = FPU_FPCR_IMPLEMENTED_MASK
			report "FPCR reserved fields were retained" severity failure;
		assert fpsr = x"A55AA55A" and fpiar = x"12345678"
			report "FPSR or FPIAR write failed" severity failure;
		check_control_register(FPU_REG_FPCR, FPU_FPCR_IMPLEMENTED_MASK);
		check_control_register(FPU_REG_FPSR, x"A55AA55A");
		check_control_register(FPU_REG_FPIAR, x"12345678");

		wait until falling_edge(clk);
		null_restore <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		null_restore <= '0';
		for index in fp_registers'range loop
			assert fp_registers(index) = FPU_RESET_NAN
				report "null restore did not initialize FPU data state"
				severity failure;
		end loop;
		assert fpcr = x"00000000" and fpsr = x"00000000" and
			fpiar = x"00000000"
			report "null restore did not clear FPU control state"
			severity failure;

		report "PASS: MC68882 architectural register state" severity note;
		stop;
	end process;
end architecture;
