library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_move_controller is
end entity;

architecture test of tb_tg68k_fpu_move_controller is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 7) of std_logic_vector(31 downto 0);
	type word_trace_t is array (0 to 7) of std_logic_vector(15 downto 0);
	type bit_trace_t is array (0 to 7) of std_logic;
	type fc_trace_t is array (0 to 7) of std_logic_vector(2 downto 0);

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal direction : fpu_move_direction_t := FPU_MOVE_REGISTER_TO_REGISTER;
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
	signal k_factor : std_logic_vector(6 downto 0) := "0010001";
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
	signal integer_register_write : std_logic;
	signal integer_register_write_data : std_logic_vector(31 downto 0);
	signal integer_register_write_format : fpu_operand_format_t;
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
	signal trace_data : word_trace_t := (others => (others => '0'));
	signal trace_write : bit_trace_t := (others => '0');
	signal trace_nuds : bit_trace_t := (others => '1');
	signal trace_nlds : bit_trace_t := (others => '1');
	signal trace_fc : fc_trace_t := (others => (others => '0'));
	signal fp_write_count : natural range 0 to 2 := 0;
	signal integer_write_count : natural range 0 to 2 := 0;
	signal status_write_count : natural range 0 to 2 := 0;
	signal observed_fp_data : fpu_extended_t := (others => '0');
	signal observed_integer_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal observed_integer_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal observed_status : std_logic_vector(7 downto 0) := (others => '0');
	signal observed_cc_write : std_logic := '0';
	signal observed_cc : std_logic_vector(3 downto 0) := (others => '0');
	signal observed_bus_error : std_logic := '0';
begin
	clk <= not clk after CLK_PERIOD / 2;
	memory_ready <= memory_request and allow_memory and not memory_error;

	read_memory : process(memory_address)
	begin
		case memory_address is
			when x"00001000" => memory_read_data <= x"C004";
			when x"00001002" => memory_read_data <= x"0000";
			when x"00001004" => memory_read_data <= x"0000";
			when x"00001006" => memory_read_data <= x"0000";
			when x"00002001" => memory_read_data <= x"ABCD";
			when x"00005000" => memory_read_data <= x"0000";
			when x"00005002" => memory_read_data <= x"0001";
			when x"00005004" | x"00005006" | x"00005008" |
					x"0000500A" => memory_read_data <= x"0000";
			when x"00005100" => memory_read_data <= x"4001";
			when x"00005102" => memory_read_data <= x"0001";
			when x"00005104" | x"00005106" | x"00005108" |
					x"0000510A" => memory_read_data <= x"0000";
			when others => memory_read_data <= x"0000";
		end case;
	end process;

	dut : entity work.TG68K_FPU_Move_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			direction => direction,
			operand_format => operand_format,
			external_data_register => external_data_register,
			effective_address => effective_address,
			function_code => function_code,
			integer_register_data => integer_register_data,
			fp_register_data => fp_register_data,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			k_factor => k_factor,
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
			integer_register_write => integer_register_write,
			integer_register_write_data => integer_register_write_data,
			integer_register_write_format => integer_register_write_format,
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
			rounding_mode => rounding_mode,
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
				integer_write_count <= 0;
				status_write_count <= 0;
				observed_cc_write <= '0';
				observed_bus_error <= '0';
			else
				if memory_request = '1' and memory_ready = '1' then
					trace_address(trace_count) <= memory_address;
					trace_data(trace_count) <= memory_write_data;
					trace_write(trace_count) <= memory_write;
					trace_nuds(trace_count) <= memory_nuds;
					trace_nlds(trace_count) <= memory_nlds;
					trace_fc(trace_count) <= memory_function_code;
					trace_count <= trace_count + 1;
				end if;
				if fp_register_write = '1' then
					fp_write_count <= fp_write_count + 1;
					observed_fp_data <= fp_register_write_data;
				end if;
				if integer_register_write = '1' then
					integer_write_count <= integer_write_count + 1;
					observed_integer_data <= integer_register_write_data;
					observed_integer_format <= integer_register_write_format;
				end if;
				if operation_status_write = '1' then
					status_write_count <= status_write_count + 1;
					observed_status <= operation_exception_status;
					observed_cc_write <= condition_codes_write;
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

		procedure launch_move is
			variable cycle_count : natural := 0;
		begin
			wait until falling_edge(clk);
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 3000
					report "FPU move controller did not complete" severity failure;
			end loop;
			assert busy = '1'
				report "FPU move completion did not retain busy" severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "FPU move controller did not return idle" severity failure;
		end procedure;

		procedure start_move is
		begin
			wait until falling_edge(clk);
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
		end procedure;

		procedure finish_move is
			variable cycle_count : natural := 0;
		begin
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 32
					report "FPU move controller did not complete" severity failure;
			end loop;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "FPU move controller did not return idle" severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		clear_observations;
		direction <= FPU_MOVE_REGISTER_TO_REGISTER;
		fp_register_data <= x"3FFF8000008000000000";
		rounding_precision <= FPU_PRECISION_SINGLE;
		rounding_mode <= FPU_ROUND_NEAREST;
		launch_move;
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF8000000000000000" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc_write = '1' and observed_cc = "0000" and
			trace_count = 0
			report "register FMOVE rounding or status mismatch" severity failure;

		clear_observations;
		fp_register_data <= x"00008000000000000000";
		rounding_precision <= FPU_PRECISION_EXTENDED;
		launch_move;
		assert fp_write_count = 1 and
			observed_fp_data = x"00008000000000000000" and
			observed_status = x"00" and observed_cc = "0000"
			report "minimum-exponent register FMOVE mismatch" severity failure;

		clear_observations;
		direction <= FPU_MOVE_EXTERNAL_TO_REGISTER;
		operand_format <= FPU_FORMAT_LONG_INTEGER;
		external_data_register <= '1';
		integer_register_data <= x"7FFFFFFF";
		rounding_precision <= FPU_PRECISION_SINGLE;
		launch_move;
		assert fp_write_count = 1 and
			observed_fp_data = x"401E8000000000000000" and
			observed_status = x"02" and trace_count = 0
			report "data-register to FP FMOVE mismatch" severity failure;

		clear_observations;
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_DOUBLE;
		effective_address <= x"00001000";
		function_code <= "101";
		rounding_precision <= FPU_PRECISION_EXTENDED;
		allow_memory <= '0';
		start_move;
		for wait_cycle in 0 to 2 loop
			wait until rising_edge(clk);
			wait for 1 ns;
			assert memory_request = '1' and memory_address = x"00001000" and
				busy = '1' and done = '0' and trace_count = 0
				report "FPU move request changed during a memory wait state"
				severity failure;
		end loop;
		allow_memory <= '1';
		finish_move;
		assert trace_count = 4 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			trace_address(2) = x"00001004" and
			trace_address(3) = x"00001006" and
			trace_write(0) = '0' and trace_fc(3) = "101" and
			observed_fp_data = x"C000A000000000000000" and
			observed_cc = "1000" and observed_status = x"00"
			report "memory double to FP FMOVE bus sequence mismatch" severity failure;

		clear_observations;
		operand_format <= FPU_FORMAT_PACKED;
		effective_address <= x"00005100";
		rounding_precision <= FPU_PRECISION_SINGLE;
		rounding_mode <= FPU_ROUND_NEAREST;
		launch_move;
		assert trace_count = 6 and trace_address(0) = x"00005100" and
			trace_address(5) = x"0000510A" and trace_write(0) = '0' and
			observed_fp_data = x"3FFBCCCCCCCCCCCCCCCD" and
			observed_status = x"01" and observed_cc = "0000"
			report "packed memory to FP FMOVE mismatch" severity failure;

		clear_observations;
		operand_format <= FPU_FORMAT_BYTE_INTEGER;
		effective_address <= x"00002001";
		launch_move;
		assert trace_count = 1 and trace_nuds(0) = '1' and
			trace_nlds(0) = '0' and
			observed_fp_data = x"C004CC00000000000000"
			report "odd byte FMOVE load mismatch" severity failure;

		clear_observations;
		direction <= FPU_MOVE_REGISTER_TO_EXTERNAL;
		operand_format <= FPU_FORMAT_EXTENDED;
		fp_register_data <= x"C000A000000000000000";
		effective_address <= x"00003000";
		launch_move;
		assert trace_count = 6 and trace_write(0) = '1' and
			trace_data(0) = x"C000" and trace_data(1) = x"0000" and
			trace_data(2) = x"A000" and trace_data(3) = x"0000" and
			trace_data(4) = x"0000" and trace_data(5) = x"0000" and
			trace_address(5) = x"0000300A" and
			fp_write_count = 0 and status_write_count = 1 and
			observed_cc_write = '0'
			report "FP to memory extended FMOVE ordering mismatch" severity failure;

		clear_observations;
		operand_format <= FPU_FORMAT_PACKED;
		fp_register_data <= x"400CC0E6B70E2C12AD82";
		k_factor <= "1111101";
		effective_address <= x"00005200";
		launch_move;
		assert trace_count = 6 and trace_write(0) = '1' and
			trace_address(0) = x"00005200" and
			trace_address(5) = x"0000520A" and
			trace_data(0) = x"0004" and trace_data(1) = x"0001" and
			trace_data(2) = x"2345" and trace_data(3) = x"6790" and
			trace_data(4) = x"0000" and trace_data(5) = x"0000" and
			observed_status = x"02" and observed_cc_write = '0'
			report "FP to packed memory static-K FMOVE mismatch" severity failure;

		clear_observations;
		operand_format <= FPU_FORMAT_DYNAMIC_PACKED;
		k_factor <= "0010010";
		effective_address <= x"00005300";
		launch_move;
		assert trace_count = 6 and trace_write(0) = '1' and
			trace_address(5) = x"0000530A" and
			trace_data(0) = x"0004" and trace_data(1) = x"0001" and
			trace_data(2) = x"2345" and trace_data(3) = x"6787" and
			trace_data(4) = x"6500" and trace_data(5) = x"0000" and
			observed_status = x"22"
			report "FP to packed memory dynamic-K OPERR mismatch" severity failure;

		clear_observations;
		external_data_register <= '1';
		operand_format <= FPU_FORMAT_SINGLE;
		fp_register_data <= x"3FFF8000008000000000";
		launch_move;
		assert integer_write_count = 1 and
			observed_integer_data = x"3F800000" and
			observed_integer_format = FPU_FORMAT_SINGLE and
			observed_status = x"02" and observed_cc_write = '0'
			report "FP to data-register single FMOVE mismatch" severity failure;

		clear_observations;
		external_data_register <= '0';
		operand_format <= FPU_FORMAT_BYTE_INTEGER;
		fp_register_data <= x"BFFF8000000000000000";
		effective_address <= x"00003001";
		launch_move;
		assert trace_count = 1 and trace_write(0) = '1' and
			trace_data(0) = x"FFFF" and trace_nuds(0) = '1' and
			trace_nlds(0) = '0'
			report "odd byte FMOVE store mismatch" severity failure;

		clear_observations;
		memory_error <= '1';
		operand_format <= FPU_FORMAT_WORD_INTEGER;
		effective_address <= x"00004000";
		start_move;
		wait until bus_error_exception = '1';
		wait for 1 ns;
		assert busy = '1' and done = '0' and memory_request = '0' and
			trace_count = 0 and status_write_count = 0
			report "FPU move bus error did not pause without side effects"
			severity failure;
		memory_error <= '0';
		wait until falling_edge(clk);
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		finish_move;
		assert observed_bus_error = '1' and trace_count = 1 and
			trace_address(0) = x"00004000" and status_write_count = 1
			report "FPU move bus-error retry mismatch" severity failure;

		assert fpu_condition_codes(x"00000000000000000000") = "0100" and
			fpu_condition_codes(x"80000000000000000000") = "1100" and
			fpu_condition_codes(x"7FFF8000000000000000") = "0010" and
			fpu_condition_codes(x"FFFF8000000000000000") = "1010" and
			fpu_condition_codes(x"7FFFC000000000000001") = "0001" and
			fpu_condition_codes(x"FFFFC000000000000001") = "1001"
			report "FPU condition-code classification mismatch" severity failure;

		report "PASS: MC68882 FMOVE transfer controller and bus ordering"
			severity note;
		stop;
	end process;
end architecture;
