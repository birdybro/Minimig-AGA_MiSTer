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
	signal packed_conversion_start : std_logic;
	signal packed_conversion_source : std_logic_vector(95 downto 0);
	signal packed_conversion_result : fpu_extended_t;
	signal packed_conversion_status : std_logic_vector(7 downto 0);
	signal packed_conversion_done : std_logic;
	signal memory_ready : std_logic;
	signal memory_error : std_logic := '0';
	signal retry : std_logic := '0';
	signal resume_context : std_logic := '0';
	signal saved_context_in : std_logic_vector(98 downto 0) :=
		(others => '0');
	signal saved_context_out : std_logic_vector(98 downto 0);
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
	signal fp_register_write_cosine : std_logic;
	signal operation_status_write : std_logic;
	signal condition_codes_write : std_logic;
	signal operation_condition_codes : std_logic_vector(3 downto 0);
	signal quotient_write : std_logic;
	signal operation_quotient : std_logic_vector(7 downto 0);
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
	signal observed_first_fp_data : fpu_extended_t := (others => '0');
	signal cosine_write_count : natural range 0 to 1 := 0;
	signal observed_status : std_logic_vector(7 downto 0) := (others => '0');
	signal observed_cc : std_logic_vector(3 downto 0) := (others => '0');
	signal quotient_write_count : natural range 0 to 2 := 0;
	signal observed_quotient : std_logic_vector(7 downto 0) := (others => '0');
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
			when x"00005000" => memory_read_data <= x"0000";
			when x"00005002" => memory_read_data <= x"0001";
			when x"00005004" => memory_read_data <= x"5000";
			when x"00005006" | x"00005008" | x"0000500A" =>
				memory_read_data <= x"0000";
			when x"00005200" => memory_read_data <= x"7FFF";
			when x"00005202" | x"00005204" | x"00005206" |
					x"00005208" => memory_read_data <= x"0000";
			when x"0000520A" => memory_read_data <= x"0042";
			when x"00005400" => memory_read_data <= x"3FFF";
			when x"00005402" => memory_read_data <= x"0000";
			when x"00005404" => memory_read_data <= x"C000";
			when x"00005406" | x"00005408" | x"0000540A" =>
				memory_read_data <= x"0000";
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
			packed_conversion_start => packed_conversion_start,
			packed_conversion_source => packed_conversion_source,
			packed_conversion_done => packed_conversion_done,
			packed_conversion_result => packed_conversion_result,
			packed_conversion_status => packed_conversion_status,
			round_input => open,
			rounding_precision_out => open,
			rounding_mode_out => open,
			round_single_extended_range => open,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
			resume_context => resume_context,
			saved_context_in => saved_context_in,
			saved_context_out => saved_context_out,
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
			fp_register_write_cosine => fp_register_write_cosine,
			operation_status_write => operation_status_write,
			condition_codes_write => condition_codes_write,
			operation_condition_codes => operation_condition_codes,
			quotient_write => quotient_write,
			operation_quotient => operation_quotient,
			operation_exception_status => operation_exception_status,
			exceptional_operand => open,
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
				observed_nuds <= '0';
				observed_nlds <= '0';
				fp_write_count <= 0;
				cosine_write_count <= 0;
				status_write_count <= 0;
				quotient_write_count <= 0;
				observed_bus_error <= '0';
			else
				if memory_ready = '1' then
					trace_address(trace_count) <= memory_address;
					trace_count <= trace_count + 1;
					observed_nuds <= memory_nuds;
					observed_nlds <= memory_nlds;
				end if;
				if fp_register_write = '1' then
					if fp_write_count = 0 then
						observed_first_fp_data <= fp_register_write_data;
					end if;
					fp_write_count <= fp_write_count + 1;
					observed_fp_data <= fp_register_write_data;
					if fp_register_write_cosine = '1' then
						cosine_write_count <= cosine_write_count + 1;
					end if;
				end if;
				if operation_status_write = '1' then
					status_write_count <= status_write_count + 1;
					observed_status <= operation_exception_status;
					observed_cc <= operation_condition_codes;
					assert condition_codes_write = '1'
						report "binary operation did not write FP condition codes"
						severity failure;
				end if;
				if quotient_write = '1' then
					quotient_write_count <= quotient_write_count + 1;
					observed_quotient <= operation_quotient;
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
				assert cycle_count < 520
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
		operation <= FPU_OP_SGLMUL;
		rounding_precision <= FPU_PRECISION_DOUBLE;
		run_register_operation(x"3FFF8000010000000000",
			x"3FFF8000010000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF8000020000000000" and
			observed_status = x"02" and observed_cc = "0000" and
			trace_count = 0
			report "register FSGLMUL controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SGLDIV;
		rounding_precision <= FPU_PRECISION_EXTENDED;
		run_register_operation(x"4000C000000000000000",
			x"3FFF8000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFDAAAAAB0000000000" and
			observed_status = x"02" and observed_cc = "0000" and
			trace_count = 0
			report "register FSGLDIV controller mismatch" severity failure;

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
		operation <= FPU_OP_TWOTOX;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFFB504F333F9DE6484" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FTWOTOX controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ETOX;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"4000ADF85458A2BB4A9B" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FETOX controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ETOXM1;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFFDBF0A8B145769535" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FETOXM1 controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_TENTOX;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"4002A000000000000000" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FTENTOX controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_LOGNP1;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFEB17217F7D1CF79AC" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FLOGNP1 controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_LOGN;
		run_register_operation(x"40008000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFEB17217F7D1CF79AC" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FLOGN controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_LOG2;
		run_register_operation(x"40018000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"40008000000000000000" and
			status_write_count = 1 and observed_status = x"00" and
			observed_cc = "0000" and trace_count = 0
			report "register FLOG2 controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_LOG10;
		run_register_operation(x"4002A000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF8000000000000000" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FLOG10 controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ATAN;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFEC90FDAA22168C235" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FATAN controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ASIN;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFE860A91C16B9B2C23" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FASIN controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_ACOS;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF860A91C16B9B2C23" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FACOS controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SIN;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFDF57743A2582F7F44" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FSIN controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_COS;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFEE0A94032DBEA7CEE" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FCOS controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_TAN;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFE8BDA7ADF9A3A5219" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FTAN controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SINCOS;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 2 and cosine_write_count = 1 and
			observed_first_fp_data = x"3FFEE0A94032DBEA7CEE" and
			observed_fp_data = x"3FFDF57743A2582F7F44" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FSINCOS controller mismatch" severity failure;

		clear_observations;
		rounding_precision <= FPU_PRECISION_SINGLE;
		run_register_operation(x"00008000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 2 and cosine_write_count = 1 and
			observed_first_fp_data = x"3FFF8000000000000000" and
			observed_fp_data = x"00000000000000000000" and
			observed_status = x"0A" and observed_cc = "0100"
			report "FSINCOS sine-underflow result coupling mismatch"
			severity failure;
		rounding_precision <= FPU_PRECISION_EXTENDED;

		clear_observations;
		operation <= FPU_OP_ATANH;
		run_register_operation(x"3FFE8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFE8C9F53D5681854BB" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FATANH controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SINH;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF966CFE2275CC12D4" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FSINH controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_COSH;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFFC583AA8ECFAA8261" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FCOSH controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_TANH;
		run_register_operation(x"3FFF8000000000000000",
			x"7FFFFFFFFFFFFFFFFFFF");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFEC2F7D5A8A79CA2AC" and
			status_write_count = 1 and observed_status = x"02" and
			observed_cc = "0000" and trace_count = 0
			report "register FTANH controller mismatch" severity failure;

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
		operation <= FPU_OP_SCALE;
		run_register_operation(x"4000B000000000000000",
			x"3FFFC000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"4001C000000000000000" and
			observed_status = x"00" and observed_cc = "0000"
			report "register FSCALE controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_MOD;
		run_register_operation(x"40008000000000000000",
			x"4001E000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"3FFF8000000000000000" and
			observed_status = x"00" and observed_cc = "0000" and
			quotient_write_count = 1 and observed_quotient = x"03"
			report "register FMOD controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_REM;
		run_register_operation(x"40008000000000000000",
			x"4001E000000000000000");
		assert fp_write_count = 1 and
			observed_fp_data = x"BFFF8000000000000000" and
			observed_status = x"00" and observed_cc = "1000" and
			quotient_write_count = 1 and observed_quotient = x"04"
			report "register FREM controller mismatch" severity failure;

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
		operand_format <= FPU_FORMAT_PACKED;
		effective_address <= x"00005000";
		fp_register_data <= x"40008000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 6 and trace_address(0) = x"00005000" and
			trace_address(5) = x"0000500A" and
			observed_fp_data = x"4000E000000000000000" and
			observed_status = x"00"
			report "packed memory FADD controller mismatch" severity failure;

		clear_observations;
		effective_address <= x"00005200";
		exception_enable <= x"40";
		start_operation;
		finish_operation;
		assert trace_count = 6 and trace_address(0) = x"00005200" and
			trace_address(5) = x"0000520A" and fp_write_count = 0 and
			observed_status = x"40" and observed_cc = "0001"
			report "packed signaling-NaN FADD controller mismatch"
			severity failure;
		exception_enable <= x"00";

		clear_observations;
		operation <= FPU_OP_MUL;
		operand_format <= FPU_FORMAT_SINGLE;
		effective_address <= x"00001000";
		fp_register_data <= x"40008000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"4000C000000000000000" and
			observed_status = x"00"
			report "memory single FMUL controller mismatch" severity failure;

		clear_observations;
		operation <= FPU_OP_SGLMUL;
		fp_register_data <= x"40008000000000000000";
		start_operation;
		finish_operation;
		assert trace_count = 2 and trace_address(0) = x"00001000" and
			trace_address(1) = x"00001002" and
			observed_fp_data = x"4000C000000000000000" and
			observed_status = x"00"
			report "memory single FSGLMUL controller mismatch" severity failure;

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
		operation <= FPU_OP_MOD;
		run_register_operation(x"00000000000000000000",
			x"3FFF8000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001" and quotient_write_count = 1 and
			observed_quotient = x"00"
			report "enabled FMOD operand-error suppression mismatch"
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
		operation <= FPU_OP_LOGNP1;
		exception_enable <= x"20";
		run_register_operation(x"BFFF8000000000000001",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled FLOGNP1 OPERR suppression mismatch"
			severity failure;

		clear_observations;
		exception_enable <= x"04";
		run_register_operation(x"BFFF8000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"04" and
			observed_cc = "1010"
			report "enabled FLOGNP1 DZ suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_LOGN;
		exception_enable <= x"20";
		run_register_operation(x"BFFF8000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled FLOGN OPERR suppression mismatch"
			severity failure;

		clear_observations;
		exception_enable <= x"04";
		run_register_operation(x"80000000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"04" and
			observed_cc = "1010"
			report "enabled FLOGN DZ suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_SIN;
		exception_enable <= x"20";
		run_register_operation(x"7FFF8000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled FSIN OPERR suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_TAN;
		run_register_operation(x"7FFF8000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and observed_status = x"20" and
			observed_cc = "0001"
			report "enabled FTAN OPERR suppression mismatch"
			severity failure;

		clear_observations;
		operation <= FPU_OP_SINCOS;
		run_register_operation(x"7FFF8000000000000000",
			x"40008000000000000000");
		assert fp_write_count = 0 and cosine_write_count = 0 and
			observed_status = x"20" and observed_cc = "0001"
			report "enabled FSINCOS OPERR suppression mismatch"
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

		clear_observations;
		operation <= FPU_OP_ADD;
		operand_format <= FPU_FORMAT_EXTENDED;
		effective_address <= x"00005400";
		fp_register_data <= x"3FFF8000000000000000";
		start_operation;
		wait until trace_count = 2;
		wait until falling_edge(clk);
		memory_error <= '1';
		wait until bus_error_exception = '1';
		saved_context_in <= saved_context_out;
		nReset <= '0';
		wait until rising_edge(clk);
		wait for 1 ns;
		nReset <= '1';
		memory_error <= '0';
		clear_observations;
		resume_context <= '1';
		start_operation;
		resume_context <= '0';
		fp_register_data <= x"3FFF8000000000000000";
		finish_operation;
		assert trace_count = 4 and trace_address(0) = x"00005404" and
			trace_address(3) = x"0000540A" and
			observed_fp_data = x"4000A000000000000000" and
			status_write_count = 1
			report "restored binary operand fetch did not resume from saved data"
			severity failure;

		report "PASS: MC68882 fundamental arithmetic controller"
			severity note;
		stop;
	end process;
end architecture;
