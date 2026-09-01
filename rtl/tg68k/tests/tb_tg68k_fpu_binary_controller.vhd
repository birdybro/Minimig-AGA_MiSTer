library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_binary_controller is
end entity;

architecture test of tb_tg68k_fpu_binary_controller is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 7) of std_logic_vector(31 downto 0);

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal operation : fpu_operation_t := FPU_OP_ADD;
	signal external_source : std_logic := '0';
	signal operand_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal external_data_register : std_logic := '0';
	signal effective_address : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code : std_logic_vector(2 downto 0) := "101";
	signal integer_register_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal fp_register_data : fpu_extended_t := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal exception_enable : std_logic_vector(7 downto 0) := (others => '0');
	signal memory_ready : std_logic;
	signal memory_error : std_logic := '0';
	signal retry : std_logic := '0';
	signal memory_read_data : std_logic_vector(15 downto 0);
	signal memory_request : std_logic;
	signal memory_write : std_logic;
	signal memory_address : std_logic_vector(31 downto 0);
	signal memory_write_data : std_logic_vector(15 downto 0);
	signal memory_nuds : std_logic;
	signal memory_nlds : std_logic;
	signal memory_function_code : std_logic_vector(2 downto 0);
	signal fp_register_write : std_logic;
	signal fp_register_write_data : fpu_extended_t;
	signal operation_status_write : std_logic;
	signal condition_codes_write : std_logic;
	signal operation_condition_codes : std_logic_vector(3 downto 0);
	signal operation_exception_status : std_logic_vector(7 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
	signal bus_error_exception : std_logic;
	signal allow_memory : std_logic := '1';
	signal monitor_clear : std_logic := '0';
	signal trace_count : natural range 0 to 8 := 0;
	signal trace_address : address_trace_t := (others => (others => '0'));
	signal observed_nuds : std_logic := '0';
	signal observed_nlds : std_logic := '0';
	signal fp_write_count : natural range 0 to 2 := 0;
	signal status_write_count : natural range 0 to 2 := 0;
	signal observed_fp_data : fpu_extended_t := (others => '0');
	signal observed_status : std_logic_vector(7 downto 0) := (others => '0');
	signal observed_cc : std_logic_vector(3 downto 0) := (others => '0');
	signal observed_bus_error : std_logic := '0';
begin
	clk <= not clk after CLK_PERIOD / 2;
	memory_ready <= memory_request and allow_memory and not memory_error;

	read_memory : process(memory_address)
	begin
		case memory_address is
			when x"00001000" => memory_read_data <= x"3FC0";
			when x"00001002" => memory_read_data <= x"0000";
			when x"00002000" => memory_read_data <= x"7FFF";
			when x"00002002" => memory_read_data <= x"0000";
			when x"00002004" => memory_read_data <= x"8000";
			when x"00002006" | x"00002008" => memory_read_data <= x"0000";
			when x"0000200A" => memory_read_data <= x"0123";
			when x"00003001" => memory_read_data <= x"AB01";
			when others => memory_read_data <= x"0000";
		end case;
	end process;

	dut : entity work.TG68K_FPU_Binary_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			operation => operation,
			external_source => external_source,
			operand_format => operand_format,
			external_data_register => external_data_register,
			effective_address => effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			fp_register_data => fp_register_data,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			exception_enable => exception_enable,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			memory_read_data => memory_read_data,
			memory_request => memory_request,
			memory_write => memory_write,
			memory_address => memory_address,
			memory_write_data => memory_write_data,
			memory_nuds => memory_nuds,
			memory_nlds => memory_nlds,
			memory_function_code => memory_function_code,
			fp_register_write => fp_register_write,
			fp_register_write_data => fp_register_write_data,
			operation_status_write => operation_status_write,
			condition_codes_write => condition_codes_write,
			operation_condition_codes => operation_condition_codes,
			operation_exception_status => operation_exception_status,
			busy => busy,
			done => done,
			bus_error_exception => bus_error_exception
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if monitor_clear = '1' then
				trace_count <= 0;
				observed_nuds <= '0';
				observed_nlds <= '0';
				fp_write_count <= 0;
				status_write_count <= 0;
				observed_bus_error <= '0';
			else
				if memory_ready = '1' then
					trace_address(trace_count) <= memory_address;
					trace_count <= trace_count + 1;
					observed_nuds <= memory_nuds;
					observed_nlds <= memory_nlds;
				end if;
				if fp_register_write = '1' then
					fp_write_count <= fp_write_count + 1;
					observed_fp_data <= fp_register_write_data;
				end if;
				if operation_status_write = '1' then
					status_write_count <= status_write_count + 1;
					observed_status <= operation_exception_status;
					observed_cc <= operation_condition_codes;
					assert condition_codes_write = '1'
						report "binary operation did not write FP condition codes"
						severity failure;
				end if;
				if bus_error_exception = '1' then
					observed_bus_error <= '1';
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

		procedure start_operation is
		begin
			wait until falling_edge(clk);
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
		end procedure;

		procedure finish_operation is
			variable cycle_count : natural := 0;
		begin
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 100
					report "FPU binary controller did not complete"
					severity failure;
			end loop;
			assert busy = '1'
				report "FPU binary completion did not retain busy"
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "FPU binary controller did not return idle"
				severity failure;
		end procedure;

		procedure run_register_operation(
			constant source_value : fpu_extended_t;
			constant destination_value : fpu_extended_t) is
		begin
			fp_register_data <= source_value;
			start_operation;
			fp_register_data <= destination_value;
			finish_operation;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		clear_observations;
		operation <= FPU_OP_ADD;
		external_source <= '0';
		run_register_operation(x"3FFF8000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"4000C000000000000000" and
			status_write_count = 1 and observed_status = x"00" and
			observed_cc = "0000" and trace_count = 0
			report "register FADD controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_MUL;
		run_register_operation(x"3FFFC000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"4000C000000000000000" and
			status_write_count = 1 and observed_status = x"00" and
			observed_cc = "0000" and trace_count = 0
			report "register FMUL controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SQRT;
		run_register_operation(x"40018000000000000000",
			x"3FFF8000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"40008000000000000000" and
			status_write_count = 1 and observed_status = x"00" and
			observed_cc = "0000" and trace_count = 0
			report "register FSQRT controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_INT;
		run_register_operation(x"3FFFC000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"40008000000000000000" and
			observed_status = x"02" and observed_cc = "0000"
			report "register FINT controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_INTRZ;
		rounding_mode <= FPU_ROUND_PLUS_INFINITY;
		run_register_operation(x"3FFFC000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF8000000000000000" and
			observed_status = x"02" and observed_cc = "0000"
			report "register FINTRZ controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_INT;
		rounding_mode <= FPU_ROUND_NEAREST;
		exception_enable <= x"02";
		run_register_operation(x"3FFFC000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"40008000000000000000" and
			observed_status = x"02"
			report "enabled FINT inexact incorrectly suppressed destination"
			severity failure;
		exception_enable <= x"00";

		clear_observations;
		operation <= FPU_OP_CMP;
		run_register_operation(x"4000C000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and status_write_count = 1 and
			observed_status = x"00" and observed_cc = "1000"
			report "register FCMP controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ADD;
		external_source <= '1';
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_SINGLE;
		effective_address <= x"00001000";
		function_code <= "101";
		fp_register_data <= x"40008000000000000000";
		allow_memory <= '0';
		start_operation;
		for wait_cycle in 0 to 2 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			assert memory_request = '1' and
				memory_address = x"00001000" and trace_count = 0
				report "binary operand request changed during wait state"
				severity failure;
		end loop;
		allow_memory <= '1';
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"4000E000000000000000" and
			memory_function_code = "101"
			report "memory single FADD controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_MUL;
		fp_register_data <= x"40008000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"4000C000000000000000" and
			observed_status = x"00"
			report "memory single FMUL controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_DIV;
		fp_register_data <= x"4001C000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"40018000000000000000" and
			observed_status = x"00"
			report "memory single FDIV controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SQRT;
		start_operation;
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"3FFF9CC470A0490973E8" and
			observed_status = x"02"
			report "memory single FSQRT controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_INT;
		start_operation;
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"40008000000000000000" and
			observed_status = x"02"
			report "memory single FINT controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ADD;
		external_data_register <= '1';
		operand_format <= FPU_FORMAT_LONG_INTEGER;
		integer_register_data <= x"FFFFFFFE";
		fp_register_data <= x"4000C000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 0 and
			observed_fp_data = x"3FFF8000000000000000" and
			observed_status = x"00"
			report "data-register FADD controller mismatch" severity failure;

		clear_observations;
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_EXTENDED;
		effective_address <= x"00002000";
		exception_enable <= x"40";
		fp_register_data <= x"3FFF8000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 6 and fp_write_count = 0 and
			observed_status = x"40" and observed_cc = "0001"
			report "enabled SNAN destination suppression mismatch"
			severity failure;

		clear_observations;
		external_source <= '0';
		exception_enable <= x"20";
		run_register_operation(x"FFFF8000000000000000",
			x"7FFF8000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled OPERR destination suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_SQRT;
		run_register_operation(x"C0018000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled FSQRT OPERR destination suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_DIV;
		exception_enable <= x"04";
		run_register_operation(x"00000000000000000000",
			x"4000C000000000000000");
		assert fp_write_count = 0 and observed_status = x"04" and
			observed_cc = "0010"
			report "enabled DZ destination suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_ADD;
		exception_enable <= x"10";
		rounding_precision <= FPU_PRECISION_SINGLE;
		run_register_operation(x"407EFFFFFF0000000000",
			x"407EFFFFFF0000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"7FFF8000000000000000" and
			observed_status = x"12"
			report "enabled overflow incorrectly suppressed destination"
			severity failure;

		clear_observations;
		external_source <= '1';
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_BYTE_INTEGER;
		effective_address <= x"00003001";
		exception_enable <= x"00";
		rounding_precision <= FPU_PRECISION_EXTENDED;
		fp_register_data <= x"3FFF8000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 1 and trace_address(0) = x"00003001" and
			observed_fp_data = x"40008000000000000000" and
			observed_nuds = '1' and observed_nlds = '0'
			report "odd-byte binary transfer mismatch" severity failure;

		clear_observations;
		operand_format <= FPU_FORMAT_WORD_INTEGER;
		effective_address <= x"00004000";
		memory_error <= '1';
		start_operation;
		wait until bus_error_exception = '1';
		wait for 1 ns;
		assert busy = '1' and done = '0' and memory_request = '0' and
			trace_count = 0 and status_write_count = 0
			report "binary bus error caused side effects" severity failure;
		memory_error <= '0';
		wait until falling_edge(clk);
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		finish_operation;
		assert observed_bus_error = '1' and trace_count = 1 and
			trace_address(0) = x"00004000" and status_write_count = 1
			report "binary bus-error retry mismatch" severity failure;

		report "PASS: MC68882 fundamental arithmetic controller"
			severity note;
		stop;
	end process;
end architecture;
