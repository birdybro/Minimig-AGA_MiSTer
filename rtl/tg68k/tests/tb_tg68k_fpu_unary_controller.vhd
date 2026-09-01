library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_unary_controller is
end entity;

architecture test of tb_tg68k_fpu_unary_controller is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 7) of std_logic_vector(31 downto 0);

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal operation : fpu_operation_t := FPU_OP_TST;
	signal external_source : std_logic := '0';
	signal operand_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal external_data_register : std_logic := '0';
	signal effective_address : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code : std_logic_vector(2 downto 0) := "101";
	signal integer_register_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal fp_register_data : fpu_extended_t := (others => '0');
	signal exception_enable : std_logic_vector(7 downto 0) := (others => '0');
	signal packed_conversion_start : std_logic;
	signal packed_conversion_source : std_logic_vector(95 downto 0);
	signal packed_conversion_result : fpu_extended_t;
	signal packed_conversion_status : std_logic_vector(7 downto 0);
	signal packed_conversion_done : std_logic;
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
			when x"00001000" => memory_read_data <= x"BFC0";
			when x"00001002" => memory_read_data <= x"0000";
			when x"00002001" => memory_read_data <= x"AB80";
			when x"00005000" => memory_read_data <= x"4001";
			when x"00005002" => memory_read_data <= x"0001";
			when x"00005004" | x"00005006" | x"00005008" |
					x"0000500A" => memory_read_data <= x"0000";
			when others => memory_read_data <= x"0000";
		end case;
	end process;

	dut : entity work.TG68K_FPU_Unary_Controller
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
			exception_enable => exception_enable,
			packed_conversion_start => packed_conversion_start,
			packed_conversion_source => packed_conversion_source,
			packed_conversion_done => packed_conversion_done,
			packed_conversion_result => packed_conversion_result,
			packed_conversion_status => packed_conversion_status,
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

	packed_converter : entity work.TG68K_FPU_Packed_To_Extended
		port map(
			clk => clk,
			nReset => nReset,
			start => packed_conversion_start,
			source => packed_conversion_source,
			rounding_mode => FPU_ROUND_NEAREST,
			result => packed_conversion_result,
			exception_status => packed_conversion_status,
			busy => open,
			done => packed_conversion_done
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if monitor_clear = '1' then
				trace_count <= 0;
				fp_write_count <= 0;
				status_write_count <= 0;
				observed_bus_error <= '0';
			else
				if memory_ready = '1' then
					trace_address(trace_count) <= memory_address;
					trace_count <= trace_count + 1;
				end if;
				if fp_register_write = '1' then
					fp_write_count <= fp_write_count + 1;
					observed_fp_data <= fp_register_write_data;
				end if;
				if operation_status_write = '1' then
					status_write_count <= status_write_count + 1;
					observed_status <= operation_exception_status;
					assert condition_codes_write = '1'
						report "unary operation did not write FP condition codes"
						severity failure;
					observed_cc <= operation_condition_codes;
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
				assert cycle_count < 700
					report "FPU unary controller did not complete" severity failure;
			end loop;
			assert busy = '1'
				report "FPU unary completion did not retain busy" severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "FPU unary controller did not return idle" severity failure;
		end procedure;

		procedure run_operation is
		begin
			start_operation;
			finish_operation;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		clear_observations;
		operation <= FPU_OP_ABS;
		fp_register_data <= x"80000000000000000000";
		run_operation;
		assert fp_write_count = 1 and
			observed_fp_data = x"00000000000000000000" and
			status_write_count = 1 and observed_status = x"00" and
			observed_cc = "0100" and trace_count = 0
			report "register FABS negative-zero result mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_NEG;
		fp_register_data <= x"7FFF8000000000000000";
		run_operation;
		assert fp_write_count = 1 and
			observed_fp_data = x"FFFF8000000000000000" and
			observed_cc = "1010" and observed_status = x"00"
			report "register FNEG infinity result mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_GETEXP;
		fp_register_data <= x"C001C000000000000000";
		run_operation;
		assert fp_write_count = 1 and
			observed_fp_data = x"40008000000000000000" and
			observed_cc = "0000" and observed_status = x"00"
			report "register FGETEXP result mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_GETMAN;
		run_operation;
		assert fp_write_count = 1 and
			observed_fp_data = x"BFFFC000000000000000" and
			observed_cc = "1000" and observed_status = x"00"
			report "register FGETMAN result mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_TST;
		fp_register_data <= x"FFFFC000000000000123";
		run_operation;
		assert fp_write_count = 0 and observed_cc = "1001" and
			observed_status = x"00"
			report "FTST quiet-NaN condition mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ABS;
		fp_register_data <= x"FFFF8000000000000123";
		exception_enable <= x"00";
		run_operation;
		assert fp_write_count = 1 and
			observed_fp_data = x"FFFFC000000000000123" and
			observed_status = x"40" and observed_cc = "1001"
			report "masked signaling-NaN unary result mismatch" severity failure;

		clear_observations;
		exception_enable <= x"40";
		run_operation;
		assert fp_write_count = 0 and observed_status = x"40" and
			observed_cc = "1001"
			report "enabled signaling-NaN did not suppress destination"
			severity failure;

		clear_observations;
		operation <= FPU_OP_GETEXP;
		fp_register_data <= x"7FFF8000000000000000";
		exception_enable <= x"00";
		run_operation;
		assert fp_write_count = 1 and observed_fp_data = FPU_RESET_NAN and
			observed_status = x"20" and observed_cc = "0001"
			report "masked FGETEXP operand-error result mismatch"
			severity failure;

		clear_observations;
		exception_enable <= x"20";
		run_operation;
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled FGETEXP operand error did not suppress destination"
			severity failure;

		clear_observations;
		exception_enable <= x"00";
		operation <= FPU_OP_ABS;
		external_source <= '1';
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_SINGLE;
		effective_address <= x"00001000";
		function_code <= "101";
		allow_memory <= '0';
		start_operation;
		for wait_cycle in 0 to 2 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			assert memory_request = '1' and
				memory_address = x"00001000" and trace_count = 0
				report "unary operand request changed during wait state"
				severity failure;
		end loop;
		allow_memory <= '1';
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"3FFFC000000000000000" and
			observed_cc = "0000" and memory_function_code = "101"
			report "memory single FABS transfer mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_GETMAN;
		run_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"BFFFC000000000000000" and
			observed_cc = "1000" and observed_status = x"00"
			report "memory single FGETMAN transfer mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ABS;
		operand_format <= FPU_FORMAT_PACKED;
		effective_address <= x"00005000";
		run_operation;
		assert trace_count = 6 and trace_address(0) = x"00005000" and
			trace_address(5) = x"0000500A" and
			observed_fp_data = x"3FFBCCCCCCCCCCCCCCCD" and
			observed_status = x"01" and observed_cc = "0000"
			report "packed memory FABS conversion mismatch" severity failure;

		clear_observations;
		external_data_register <= '1';
		operand_format <= FPU_FORMAT_LONG_INTEGER;
		integer_register_data <= x"FFFFFFFE";
		operation <= FPU_OP_ABS;
		run_operation;
		assert trace_count = 0 and
			observed_fp_data = x"40008000000000000000" and
			observed_status = x"00" and observed_cc = "0000"
			report "data-register long-integer FABS mismatch" severity failure;

		clear_observations;
		external_source <= '0';
		external_data_register <= '0';
		operation <= FPU_OP_ABS;
		fp_register_data <= x"3FFF8000000000000001";
		run_operation;
		assert observed_fp_data = x"3FFF8000000000000001" and
			observed_status = x"00"
			report "FABS incorrectly rounded an exact sign result" severity failure;

		clear_observations;
		fp_register_data <= x"80008000000000000000";
		run_operation;
		assert observed_fp_data = x"00008000000000000000" and
			observed_status = x"00" and observed_cc = "0000"
			report "FABS minimum-exponent normalized mismatch" severity failure;

		clear_observations;
		fp_register_data <= x"80000000000000000001";
		run_operation;
		assert observed_fp_data = x"00000000000000000001" and
			observed_status = x"08" and observed_cc = "0000"
			report "FABS extended-denormal underflow mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_TST;
		fp_register_data <= x"80000000000000000001";
		run_operation;
		assert fp_write_count = 0 and observed_cc = "1000" and
			observed_status = x"00"
			report "FTST incorrectly rounded an extended denormal" severity failure;

		clear_observations;
		external_source <= '1';
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_WORD_INTEGER;
		effective_address <= x"00003000";
		memory_error <= '1';
		start_operation;
		wait until bus_error_exception = '1';
		wait for 1 ns;
		assert busy = '1' and done = '0' and memory_request = '0' and
			trace_count = 0 and status_write_count = 0
			report "unary bus error caused side effects" severity failure;
		memory_error <= '0';
		wait until falling_edge(clk);
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		finish_operation;
		assert observed_bus_error = '1' and trace_count = 1 and
			trace_address(0) = x"00003000" and status_write_count = 1
			report "unary bus-error retry mismatch" severity failure;

		report "PASS: MC68882 unary and extraction controller"
			severity note;
		stop;
	end process;
end architecture;
