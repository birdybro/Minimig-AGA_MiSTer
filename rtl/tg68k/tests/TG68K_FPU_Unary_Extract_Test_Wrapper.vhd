library ieee;
use ieee.std_logic_1164.all;
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Unary_Extract_Test_Wrapper is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		get_exponent : in std_logic;
		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Unary_Extract_Test_Wrapper is
	signal operation : fpu_operation_t;
begin
	operation <= FPU_OP_GETEXP when get_exponent = '1' else FPU_OP_GETMAN;

	dut : entity work.TG68K_FPU_Unary_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			operation => operation,
			external_source => '0',
			operand_format => FPU_FORMAT_EXTENDED,
			external_data_register => '0',
			effective_address => (others => '0'),
			function_code => "001",
			integer_register_data => (others => '0'),
			fp_register_data => source,
			exception_enable => (others => '0'),
			packed_conversion_start => open,
			packed_conversion_source => open,
			packed_conversion_done => '0',
			packed_conversion_result => (others => '0'),
			packed_conversion_status => (others => '0'),
			conversion_source_format => open,
			conversion_source_data => open,
			memory_ready => '0',
			memory_error => '0',
			retry => '0',
			resume_context => '0',
			saved_context_in => (others => '0'),
			saved_context_out => open,
			memory_read_data => (others => '0'),
			memory_request => open,
			memory_write => open,
			memory_address => open,
			memory_write_data => open,
			memory_nuds => open,
			memory_nlds => open,
			memory_function_code => open,
			fp_register_write => open,
			fp_register_write_data => result,
			operation_status_write => open,
			condition_codes_write => open,
			operation_condition_codes => condition_codes,
			operation_exception_status => exception_status,
			exceptional_operand => open,
			busy => busy,
			done => done,
			bus_error_exception => open
		);
end architecture;
