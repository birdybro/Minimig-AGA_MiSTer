library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_system is
end entity;

architecture test of tb_tg68k_fpu_system is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 7) of std_logic_vector(31 downto 0);
	type word_trace_t is array (0 to 7) of std_logic_vector(15 downto 0);
	type fc_trace_t is array (0 to 7) of std_logic_vector(2 downto 0);

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal null_restore : std_logic := '0';
	signal opcode : std_logic_vector(15 downto 0) := x"F200";
	signal command_word : std_logic_vector(15 downto 0) := (others => '0');
	signal instruction_address : std_logic_vector(31 downto 0) := x"00000400";
	signal effective_address : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code : std_logic_vector(2 downto 0) := "001";
	signal integer_register_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal instruction_start : std_logic := '0';
	signal retry : std_logic := '0';
	signal instruction_match : std_logic;
	signal instruction_valid : std_logic;
	signal instruction_implemented : std_logic;
	signal instruction_requires_command_word : std_logic;
	signal instruction_requires_effective_address : std_logic;
	signal instruction_operand_format : fpu_operand_format_t;
	signal integer_register_select : std_logic_vector(2 downto 0);
	signal address_register_select : std_logic_vector(2 downto 0);
	signal instruction_busy : std_logic;
	signal instruction_done : std_logic;
	signal fline_exception : std_logic;
	signal unimplemented_exception : std_logic;
	signal bus_error_exception : std_logic;
	signal floating_point_exception : std_logic;
	signal floating_point_exception_class : fpu_exception_t;
	signal memory_ready : std_logic;
	signal memory_error : std_logic := '0';
	signal memory_read_data : std_logic_vector(15 downto 0);
	signal memory_request : std_logic;
	signal memory_write : std_logic;
	signal memory_address : std_logic_vector(31 downto 0);
	signal memory_write_data : std_logic_vector(15 downto 0);
	signal memory_nuds : std_logic;
	signal memory_nlds : std_logic;
	signal memory_function_code : std_logic_vector(2 downto 0);
	signal integer_register_write : std_logic;
	signal integer_register_write_data : std_logic_vector(31 downto 0);
	signal integer_register_write_format : fpu_operand_format_t;
	signal address_register_write : std_logic;
	signal address_register_write_data : std_logic_vector(31 downto 0);
	signal fp_registers : fpu_register_array_t;
	signal fpcr : std_logic_vector(31 downto 0);
	signal fpsr : std_logic_vector(31 downto 0);
	signal fpiar : std_logic_vector(31 downto 0);
	signal monitor_clear : std_logic := '0';
	signal trace_count : natural range 0 to 8 := 0;
	signal trace_address : address_trace_t := (others => (others => '0'));
	signal trace_data : word_trace_t := (others => (others => '0'));
	signal trace_fc : fc_trace_t := (others => (others => '0'));
	signal trace_write : std_logic_vector(0 to 7) := (others => '0');
	signal integer_write_count : natural range 0 to 2 := 0;
	signal observed_integer_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal observed_integer_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal address_write_count : natural range 0 to 2 := 0;
	signal observed_address_select : std_logic_vector(2 downto 0) := "000";
	signal observed_address_data : std_logic_vector(31 downto 0) :=
		(others => '0');
begin
	clk <= not clk after CLK_PERIOD / 2;
	memory_ready <= memory_request and not memory_error;

	read_memory : process(memory_address)
	begin
		case memory_address is
			when x"00001000" => memory_read_data <= x"C004";
			when x"00001002" => memory_read_data <= x"0000";
			when x"00001004" => memory_read_data <= x"0000";
			when x"00001006" => memory_read_data <= x"0000";
			when others => memory_read_data <= x"0000";
		end case;
	end process;

	dut : entity work.TG68K_FPU_System
		port map(
			clk => clk,
			nReset => nReset,
			null_restore => null_restore,
			opcode => opcode,
			command_word => command_word,
			instruction_address => instruction_address,
			effective_address => effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			instruction_start => instruction_start,
			retry => retry,
			instruction_match => instruction_match,
			instruction_valid => instruction_valid,
			instruction_implemented => instruction_implemented,
			instruction_requires_command_word =>
				instruction_requires_command_word,
			instruction_requires_effective_address =>
				instruction_requires_effective_address,
			instruction_operand_format => instruction_operand_format,
			integer_register_select => integer_register_select,
			address_register_select => address_register_select,
			instruction_busy => instruction_busy,
			instruction_done => instruction_done,
			fline_exception => fline_exception,
			unimplemented_exception => unimplemented_exception,
			bus_error_exception => bus_error_exception,
			floating_point_exception => floating_point_exception,
			floating_point_exception_class => floating_point_exception_class,
			memory_ready => memory_ready,
			memory_error => memory_error,
			memory_read_data => memory_read_data,
			memory_request => memory_request,
			memory_write => memory_write,
			memory_address => memory_address,
			memory_write_data => memory_write_data,
			memory_nuds => memory_nuds,
			memory_nlds => memory_nlds,
			memory_function_code => memory_function_code,
			integer_register_write => integer_register_write,
			integer_register_write_data => integer_register_write_data,
			integer_register_write_format => integer_register_write_format,
			address_register_write => address_register_write,
			address_register_write_data => address_register_write_data,
			fp_registers_out => fp_registers,
			fpcr_out => fpcr,
			fpsr_out => fpsr,
			fpiar_out => fpiar
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if monitor_clear = '1' then
				trace_count <= 0;
				integer_write_count <= 0;
				address_write_count <= 0;
			else
				if memory_ready = '1' then
					trace_address(trace_count) <= memory_address;
					trace_data(trace_count) <= memory_write_data;
					trace_fc(trace_count) <= memory_function_code;
					trace_write(trace_count) <= memory_write;
					trace_count <= trace_count + 1;
				end if;
				if integer_register_write = '1' then
					integer_write_count <= integer_write_count + 1;
					observed_integer_data <= integer_register_write_data;
					observed_integer_format <= integer_register_write_format;
				end if;
				if address_register_write = '1' then
					address_write_count <= address_write_count + 1;
					observed_address_select <= address_register_select;
					observed_address_data <= address_register_write_data;
				end if;
			end if;
		end if;
	end process;

	stimulus : process
		procedure clear_observations is
		begin
			wait until falling_edge(clk);
			monitor_clear <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			monitor_clear <= '0';
		end procedure;

		procedure start_instruction(
			constant opcode_value : std_logic_vector(15 downto 0);
			constant command_value : std_logic_vector(15 downto 0);
			constant expected_implemented : std_logic) is
		begin
			opcode <= opcode_value;
			command_word <= command_value;
			wait for 1 ns;
			assert instruction_match = '1' and instruction_valid = '1' and
				instruction_implemented = expected_implemented
				report "FPU system dispatch classification mismatch" severity failure;
			wait until falling_edge(clk);
			instruction_start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			instruction_start <= '0';
		end procedure;

		procedure wait_done is
			variable cycle_count : natural := 0;
		begin
			while instruction_done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 40
					report "FPU system command did not complete" severity failure;
			end loop;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert instruction_done = '0' and instruction_busy = '0'
				report "FPU system did not return idle" severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;

		command_word <= x"0040";
		wait for 1 ns;
		assert instruction_match = '1' and instruction_valid = '0' and
			fline_exception = '1'
			report "FPU system did not report a reserved operation" severity failure;

		clear_observations;
		integer_register_data <= x"00000005";
		start_instruction(x"F202", x"4180", '1');
		assert integer_register_select = "010"
			report "FPU system selected the wrong source data register"
			severity failure;
		command_word <= x"4000";
		wait_done;
		assert fp_registers(3) = x"4001A000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00" and
			fpiar = x"00000000" and trace_count = 0
			report "external-to-register FMOVE system result mismatch"
			severity failure;

		start_instruction(x"F200", x"0E00", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4001A000000000000000"
			report "register FMOVE did not retain source/destination selection"
			severity failure;

		clear_observations;
		effective_address <= x"00003000";
		function_code <= "101";
		start_instruction(x"F210", x"6600", '1');
		command_word <= x"6000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '1' and
			trace_address(0) = x"00003000" and
			trace_address(1) = x"00003002" and
			trace_data(0) = x"40A0" and trace_data(1) = x"0000" and
			trace_fc(1) = "101"
			report "register-to-memory FMOVE system bus sequence mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00000400";
		start_instruction(x"F219", x"6980", '1');
		command_word <= x"6000";
		wait_done;
		assert trace_count = 6 and trace_address(0) = x"00000400" and
			trace_address(5) = x"0000040A" and address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"0000040C"
			report "extended postincrement FMOVE address update mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00000500";
		start_instruction(x"F21F", x"7980", '1');
		command_word <= x"6000";
		wait_done;
		assert trace_count = 1 and trace_address(0) = x"00000500" and
			trace_data(0) = x"0505" and address_write_count = 1 and
			observed_address_select = "111" and
			observed_address_data = x"00000502"
			report "byte postincrement FMOVE A7 alignment mismatch: cycles=" &
				integer'image(trace_count) & " data=" &
				to_hstring(trace_data(0)) & " address=" &
				to_hstring(observed_address_data)
			severity failure;

		clear_observations;
		effective_address <= x"00000400";
		start_instruction(x"F221", x"4A80", '1');
		command_word <= x"4000";
		wait_done;
		assert trace_count = 6 and trace_address(0) = x"000003F4" and
			trace_address(5) = x"000003FE" and address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"000003F4"
			report "extended predecrement FMOVE address update mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00001000";
		function_code <= "001";
		start_instruction(x"F210", x"5680", '1');
		command_word <= x"4000";
		wait_done;
		assert trace_count = 4 and trace_write(0) = '0' and
			trace_address(3) = x"00001006" and trace_fc(0) = "001" and
			fp_registers(5) = x"C000A000000000000000" and
			fpsr(31 downto 28) = "1000"
			report "memory-to-register FMOVE system result mismatch"
			severity failure;

		clear_observations;
		start_instruction(x"F201", x"6680", '1');
		assert integer_register_select = "001"
			report "FPU system selected the wrong destination data register"
			severity failure;
		command_word <= x"6000";
		wait_done;
		assert integer_write_count = 1 and
			observed_integer_data = x"C0200000" and
			observed_integer_format = FPU_FORMAT_SINGLE
			report "register-to-data-register FMOVE system result mismatch"
			severity failure;

		clear_observations;
		start_instruction(x"F210", x"4C00", '0');
		assert instruction_done = '1' and unimplemented_exception = '1' and
			memory_request = '0'
			report "packed FMOVE was not explicitly reported as unimplemented"
			severity failure;
		wait_done;
		assert trace_count = 0
			report "unimplemented packed FMOVE caused a bus cycle" severity failure;

		start_instruction(x"F200", x"0E22", '0');
		assert instruction_done = '1' and unimplemented_exception = '1'
			report "arithmetic command was not explicitly reported as unimplemented"
			severity failure;
		wait_done;

		wait until falling_edge(clk);
		null_restore <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		null_restore <= '0';
		assert fp_registers(3) = FPU_RESET_NAN and
			fp_registers(4) = FPU_RESET_NAN and fpcr = x"00000000" and
			fpsr = x"00000000" and fpiar = x"00000000"
			report "FPU system null restore mismatch" severity failure;

		assert bus_error_exception = '0' and floating_point_exception = '0' and
			floating_point_exception_class = FPU_EXCEPTION_NONE
			report "unexpected FPU system exception" severity failure;

		report "PASS: MC68882 FMOVE decode, state, and transfer integration"
			severity note;
		stop;
	end process;
end architecture;
