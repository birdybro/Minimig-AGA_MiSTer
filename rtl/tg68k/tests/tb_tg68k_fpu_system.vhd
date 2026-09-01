library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_system is
end entity;

architecture test of tb_tg68k_fpu_system is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 31) of std_logic_vector(31 downto 0);
	type word_trace_t is array (0 to 31) of std_logic_vector(15 downto 0);
	type fc_trace_t is array (0 to 31) of std_logic_vector(2 downto 0);

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
	signal address_register_data : std_logic_vector(31 downto 0) :=
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
	signal trace_count : natural range 0 to 32 := 0;
	signal trace_address : address_trace_t := (others => (others => '0'));
	signal trace_data : word_trace_t := (others => (others => '0'));
	signal trace_fc : fc_trace_t := (others => (others => '0'));
	signal trace_write : std_logic_vector(0 to 31) := (others => '0');
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
			when x"00002000" => memory_read_data <= x"0000";
			when x"00002002" => memory_read_data <= x"0030";
			when x"00002004" => memory_read_data <= x"A5A5";
			when x"00002006" => memory_read_data <= x"1234";
			when x"00002008" => memory_read_data <= x"1122";
			when x"0000200A" => memory_read_data <= x"3344";
			when x"00004000" => memory_read_data <= x"4000";
			when x"00004002" => memory_read_data <= x"DEAD";
			when x"00004004" => memory_read_data <= x"8000";
			when x"00004006" | x"00004008" => memory_read_data <= x"0000";
			when x"0000400A" => memory_read_data <= x"0007";
			when x"0000400C" => memory_read_data <= x"4001";
			when x"0000400E" => memory_read_data <= x"BEEF";
			when x"00004010" => memory_read_data <= x"9000";
			when x"00004012" | x"00004014" | x"00004016" =>
				memory_read_data <= x"0000";
			when x"00006000" => memory_read_data <= x"4005";
			when x"00006002" => memory_read_data <= x"CAFE";
			when x"00006004" => memory_read_data <= x"A000";
			when x"00006006" | x"00006008" => memory_read_data <= x"0000";
			when x"0000600A" => memory_read_data <= x"0005";
			when x"00009000" => memory_read_data <= x"BFC0";
			when x"00009002" => memory_read_data <= x"0000";
			when x"00009004" => memory_read_data <= x"3F00";
			when x"00009006" => memory_read_data <= x"0000";
			when x"0000A000" => memory_read_data <= x"7FFF";
			when x"0000A002" => memory_read_data <= x"0000";
			when x"0000A004" => memory_read_data <= x"8000";
			when x"0000A006" | x"0000A008" => memory_read_data <= x"0000";
			when x"0000A00A" => memory_read_data <= x"0123";
			when x"0000B000" => memory_read_data <= x"7FFF";
			when x"0000B002" => memory_read_data <= x"0000";
			when x"0000B004" => memory_read_data <= x"8000";
			when x"0000B006" | x"0000B008" | x"0000B00A" =>
				memory_read_data <= x"0000";
			when x"0000B010" => memory_read_data <= x"FFFF";
			when x"0000B012" => memory_read_data <= x"0000";
			when x"0000B014" => memory_read_data <= x"8000";
			when x"0000B016" | x"0000B018" | x"0000B01A" =>
				memory_read_data <= x"0000";
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
			address_register_data => address_register_data,
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
				assert cycle_count < 400
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
		effective_address <= x"00004000";
		function_code <= "101";
		start_instruction(x"F219", x"D081", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 12 and trace_write(0) = '0' and
			trace_address(0) = x"00004000" and
			trace_address(11) = x"00004016" and
			fp_registers(7) = x"40008000000000000007" and
			fp_registers(0) = x"40019000000000000000" and
			fpsr = x"80000000" and fpiar = x"00000000" and
			address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"00004018"
			report "static memory-to-FP-register FMOVEM mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00005000";
		start_instruction(x"F212", x"F081", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 12 and trace_write(0) = '1' and
			trace_address(0) = x"00005000" and
			trace_address(11) = x"00005016" and
			trace_data(0) = x"4000" and trace_data(1) = x"0000" and
			trace_data(2) = x"8000" and trace_data(5) = x"0007" and
			trace_data(6) = x"4001" and trace_data(7) = x"0000" and
			trace_data(8) = x"9000"
			report "static FP-register-to-memory FMOVEM mismatch"
			severity failure;

		clear_observations;
		integer_register_data <= x"12340004";
		effective_address <= x"00006000";
		start_instruction(x"F21B", x"D830", '1');
		assert integer_register_select = "011"
			report "dynamic FMOVEM selected the wrong mask register"
			severity failure;
		command_word <= x"0000";
		wait_done;
		assert trace_count = 6 and fp_registers(5) =
			x"4005A000000000000005" and address_write_count = 1 and
			observed_address_select = "011" and
			observed_address_data = x"0000600C"
			report "dynamic memory-to-FP-register FMOVEM mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00007000";
		start_instruction(x"F224", x"E081", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 12 and trace_address(0) = x"00006FF4" and
			trace_address(5) = x"00006FFE" and
			trace_address(6) = x"00006FE8" and
			trace_address(11) = x"00006FF2" and
			trace_data(0) = x"4000" and trace_data(6) = x"4001" and
			address_write_count = 1 and observed_address_select = "100" and
			observed_address_data = x"00006FE8"
			report "static predecrement FP-register FMOVEM mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00008000";
		start_instruction(x"F21D", x"D000", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and address_write_count = 0
			report "empty FMOVEM list changed memory or its address register"
			severity failure;

		clear_observations;
		integer_register_data <= x"000000B0";
		start_instruction(x"F203", x"9000", '1');
		assert instruction_requires_effective_address = '0'
			report "direct FPCR load incorrectly requested an effective address"
			severity failure;
		command_word <= x"0000";
		wait_done;
		assert fpcr = x"000000B0" and fpiar = x"00000000" and
			trace_count = 0
			report "data-register-to-FPCR transfer mismatch" severity failure;

		clear_observations;
		start_instruction(x"F204", x"B000", '1');
		command_word <= x"0000";
		wait_done;
		assert integer_write_count = 1 and
			observed_integer_data = x"000000B0" and
			observed_integer_format = FPU_FORMAT_LONG_INTEGER
			report "FPCR-to-data-register transfer mismatch" severity failure;

		clear_observations;
		start_instruction(x"F200", x"5D0C", '1');
		assert instruction_requires_effective_address = '0' and
			instruction_operand_format = FPU_FORMAT_EXTENDED
			report "FMOVECR requested an external operand" severity failure;
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and
			fp_registers(2) = x"4000ADF85458A2BB5000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "double/plus FMOVECR system result mismatch" severity failure;

		clear_observations;
		integer_register_data <= x"00000200";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"5D80", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_INEX2 and
			fp_registers(3) = x"4000C90FDAA22168C235" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02" and
			fpsr(FPU_FPSR_AEXC_INEX_BIT) = '1' and fpiar = x"00000400" and
			trace_count = 0
			report "enabled FMOVECR inexact exception mismatch" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		clear_observations;
		effective_address <= x"00002000";
		function_code <= "101";
		start_instruction(x"F210", x"9C00", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 6 and trace_write(0) = '0' and
			trace_address(0) = x"00002000" and
			trace_address(5) = x"0000200A" and trace_fc(5) = "101" and
			fpcr = x"00000030" and fpsr = x"A5A51234" and
			fpiar = x"11223344"
			report "memory-to-control FMOVEM system mismatch" severity failure;

		clear_observations;
		effective_address <= x"00003000";
		start_instruction(x"F219", x"BC00", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 6 and trace_write(0) = '1' and
			trace_address(0) = x"00003000" and trace_data(0) = x"0000" and
			trace_data(1) = x"0030" and trace_data(2) = x"A5A5" and
			trace_data(3) = x"1234" and trace_data(4) = x"1122" and
			trace_data(5) = x"3344" and address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"0000300C"
			report "control-to-memory FMOVEM system mismatch" severity failure;

		clear_observations;
		opcode <= x"F209";
		command_word <= x"A400";
		wait for 1 ns;
		assert instruction_requires_effective_address = '0'
			report "FPIAR-to-An direct transfer requested an effective address"
			severity failure;
		start_instruction(x"F209", x"A400", '1');
		command_word <= x"0000";
		wait_done;
		assert address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"11223344" and trace_count = 0
			report "FPIAR-to-address-register system mismatch" severity failure;

		clear_observations;
		address_register_data <= x"55667788";
		start_instruction(x"F209", x"8400", '1');
		command_word <= x"0000";
		wait_done;
		assert fpiar = x"55667788" and address_write_count = 0 and
			trace_count = 0
			report "address-register-to-FPIAR system mismatch" severity failure;

		clear_observations;
		start_instruction(x"F200", x"171A", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(6) = x"C005A000000000000005" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"00"
			report "register FNEG system result mismatch" severity failure;

		start_instruction(x"F200", x"1B98", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(7) = x"4005A000000000000005" and
			fpsr(31 downto 28) = "0000"
			report "register FABS system result mismatch" severity failure;

		start_instruction(x"F200", x"183A", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(6) = x"C005A000000000000005" and
			fpsr(31 downto 28) = "1000"
			report "register FTST changed its source or condition result"
			severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4518", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(2) = x"3FFFC000000000000000" and
			fpsr(31 downto 28) = "0000"
			report "memory single FABS system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		start_instruction(x"F219", x"4598", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"00009004" and
			fp_registers(3) = x"3FFFC000000000000000"
			report "postincrement FABS effective-address mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"00009004";
		start_instruction(x"F221", x"4498", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and address_write_count = 1 and
			observed_address_select = "001" and
			observed_address_data = x"00009000" and
			fp_registers(1) = x"3FFFC000000000000000"
			report "predecrement FABS effective-address mismatch"
			severity failure;

		clear_observations;
		integer_register_data <= x"00004000";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		assert fpcr = x"00004000"
			report "signaling-NaN exception enable setup mismatch"
			severity failure;

		clear_observations;
		effective_address <= x"0000A000";
		start_instruction(x"F210", x"4818", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_SNAN and
			trace_count = 6 and fp_registers(0) = x"40019000000000000000" and
			fpsr(31 downto 28) = "0001" and fpsr(15 downto 8) = x"40" and
			fpiar = x"00000400"
			report "enabled signaling-NaN FABS exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert instruction_done = '0' and instruction_busy = '0' and
			floating_point_exception = '0'
			report "signaling-NaN operation did not retire cleanly"
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

		clear_observations;
		integer_register_data <= x"00000000";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		assert fpcr = x"00000000"
			report "binary arithmetic FPCR setup mismatch" severity failure;

		start_instruction(x"F200", x"0E22", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4001D000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FADD system result mismatch" severity failure;

		start_instruction(x"F200", x"0E28", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4001A000000000000000"
			report "register FSUB system result mismatch" severity failure;

		start_instruction(x"F200", x"0E38", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4001A000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FCMP system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4622", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"4000E000000000000000"
			report "memory single FADD system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"0000B000";
		start_instruction(x"F210", x"4B00", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(6) = x"7FFF8000000000000000"
			report "positive-infinity setup mismatch" severity failure;

		effective_address <= x"0000B010";
		start_instruction(x"F210", x"4B80", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(7) = x"FFFF8000000000000000"
			report "negative-infinity setup mismatch" severity failure;

		integer_register_data <= x"00002000";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"1F22", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_OPERR and
			fp_registers(6) = x"7FFF8000000000000000" and
			fpsr(31 downto 28) = "0001" and fpsr(15 downto 8) = x"20" and
			fpiar = x"00000400"
			report "enabled FADD operand-error exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		start_instruction(x"F200", x"1E04", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_OPERR and
			fp_registers(4) = x"4000E000000000000000" and
			fpsr(31 downto 28) = "0001" and fpsr(15 downto 8) = x"20" and
			fpiar = x"00000400"
			report "enabled FSQRT operand-error exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		start_instruction(x"F200", x"1321", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_OPERR and
			fp_registers(6) = x"7FFF8000000000000000" and
			fpsr(23 downto 16) = x"00" and
			fpsr(31 downto 28) = "0001" and fpsr(15 downto 8) = x"20" and
			fpiar = x"00000400"
			report "enabled FMOD operand-error exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		start_instruction(x"F200", x"1A26", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_OPERR and
			fp_registers(4) = x"4000E000000000000000" and
			fpsr(31 downto 28) = "0001" and fpsr(15 downto 8) = x"20" and
			fpiar = x"00000400"
			report "enabled FSCALE operand-error exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		start_instruction(x"F200", x"0E23", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4001A800000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FMUL system result mismatch" severity failure;

		start_instruction(x"F200", x"0E20", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4000E000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FDIV system result mismatch" severity failure;

		integer_register_data <= x"00000080";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		assert fpcr = x"00000080"
			report "FSGL precision-override setup mismatch" severity failure;

		integer_register_data <= x"00000003";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		integer_register_data <= x"00000002";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E27", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"4001C000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FSGLMUL system result mismatch" severity failure;

		integer_register_data <= x"00000001";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E24", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"3FFDAAAAAB0000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "register FSGLDIV system result mismatch" severity failure;

		integer_register_data <= x"00000002";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4627", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"C000C000000000000000" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"00"
			report "memory single FSGLMUL system result mismatch" severity failure;

		clear_observations;
		start_instruction(x"F210", x"4624", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"40008000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "memory single FSGLDIV system result mismatch" severity failure;

		integer_register_data <= x"00002000";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;

		integer_register_data <= x"00000004";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E04", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"40008000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FSQRT system result mismatch" severity failure;

		integer_register_data <= x"00000002";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E26", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"40028000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FSCALE system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4626", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"40018000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "memory single FSCALE system result mismatch" severity failure;

		integer_register_data <= x"00000007";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E21", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"3FFF8000000000000000" and
			fpsr(23 downto 16) = x"03" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FMOD system result mismatch" severity failure;

		integer_register_data <= x"00000007";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E25", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"BFFF8000000000000000" and
			fpsr(23 downto 16) = x"04" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"00"
			report "register FREM system result mismatch" severity failure;

		integer_register_data <= x"00000007";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4621", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"3FFF8000000000000000" and
			fpsr(23 downto 16) = x"84" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "memory single FMOD system result mismatch" severity failure;

		integer_register_data <= x"00000002";
		start_instruction(x"F202", x"4200", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(4) = x"40008000000000000000"
			report "FSCALE destination restore mismatch" severity failure;

		start_instruction(x"F200", x"129E", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(5) = x"3FFF8000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FGETEXP system result mismatch" severity failure;

		start_instruction(x"F200", x"111F", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(2) = x"3FFF8000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"00"
			report "register FGETMAN system result mismatch" severity failure;

		start_instruction(x"F200", x"1A9F", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_OPERR and
			fp_registers(5) = x"3FFF8000000000000000" and
			fpsr(31 downto 28) = "0001" and fpsr(15 downto 8) = x"20" and
			fpiar = x"00000400"
			report "enabled FGETMAN operand-error exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		clear_observations;
		effective_address <= x"00009000";
		start_instruction(x"F210", x"4681", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and fp_registers(5) = x"C0008000000000000000" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"02"
			report "memory single FINT system result mismatch" severity failure;

		start_instruction(x"F210", x"4683", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(5) = x"BFFF8000000000000000" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"02"
			report "memory single FINTRZ system result mismatch" severity failure;

		integer_register_data <= x"00000200";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F210", x"4681", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_INEX2 and
			fp_registers(5) = x"C0008000000000000000" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"02" and
			fpiar = x"00000400"
			report "enabled FINT inexact exception mismatch" severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		integer_register_data <= x"00000000";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		assert fp_registers(3) = x"00000000000000000000"
			report "FDIV zero-divisor setup mismatch" severity failure;

		integer_register_data <= x"00000400";
		start_instruction(x"F203", x"9000", '1');
		command_word <= x"0000";
		wait_done;
		start_instruction(x"F200", x"0E20", '1');
		command_word <= x"0000";
		while instruction_done = '0' loop
			wait until rising_edge(clk);
			wait for 1 ns;
		end loop;
		assert floating_point_exception = '1' and
			floating_point_exception_class = FPU_EXCEPTION_DZ and
			fp_registers(4) = x"40008000000000000000" and
			fpsr(31 downto 28) = "0010" and fpsr(15 downto 8) = x"04" and
			fpiar = x"00000400"
			report "enabled FDIV divide-by-zero exception mismatch"
			severity failure;
		wait until rising_edge(clk);
		wait for 1 ns;

		integer_register_data <= x"00000001";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		start_instruction(x"F200", x"0E11", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and
			fp_registers(4) = x"40008000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "register FTWOTOX system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4611", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"3FFDB504F333F9DE6484" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "memory single FTWOTOX system result mismatch" severity failure;

		integer_register_data <= x"00000001";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		start_instruction(x"F200", x"0E10", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and
			fp_registers(4) = x"4000ADF85458A2BB4A9B" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "register FETOX system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4610", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"3FFCE47C3B925AE0EB23" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "memory single FETOX system result mismatch" severity failure;

		integer_register_data <= x"00000001";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		start_instruction(x"F200", x"0E08", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and
			fp_registers(4) = x"3FFFDBF0A8B145769535" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "register FETOXM1 system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4608", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"BFFEC6E0F11B6947C537" and
			fpsr(31 downto 28) = "1000" and fpsr(15 downto 8) = x"02"
			report "memory single FETOXM1 system result mismatch" severity failure;

		integer_register_data <= x"00000001";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		start_instruction(x"F200", x"0E12", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and
			fp_registers(4) = x"4002A000000000000000" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "register FTENTOX system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009000";
		function_code <= "101";
		start_instruction(x"F210", x"4612", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009000" and
			trace_address(1) = x"00009002" and trace_fc(1) = "101" and
			fp_registers(4) = x"3FFA8186E27501D39248" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "memory single FTENTOX system result mismatch" severity failure;

		integer_register_data <= x"00000001";
		start_instruction(x"F202", x"4180", '1');
		command_word <= x"0000";
		wait_done;
		clear_observations;
		start_instruction(x"F200", x"0E06", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 0 and
			fp_registers(4) = x"3FFEB17217F7D1CF79AC" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "register FLOGNP1 system result mismatch" severity failure;

		clear_observations;
		effective_address <= x"00009004";
		function_code <= "101";
		start_instruction(x"F210", x"4606", '1');
		command_word <= x"0000";
		wait_done;
		assert trace_count = 2 and trace_write(0) = '0' and
			trace_address(0) = x"00009004" and
			trace_address(1) = x"00009006" and trace_fc(1) = "101" and
			fp_registers(4) = x"3FFDCF991F65FCC25F96" and
			fpsr(31 downto 28) = "0000" and fpsr(15 downto 8) = x"02"
			report "memory single FLOGNP1 system result mismatch" severity failure;

		start_instruction(x"F200", x"0E02", '0');
		assert instruction_done = '1' and unimplemented_exception = '1'
			report "FSINH command was not explicitly reported as unimplemented"
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

		report "PASS: MC68882 move, extraction, unary, and arithmetic integration"
			severity note;
		stop;
	end process;
end architecture;
