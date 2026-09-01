library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_control_controller is
end entity;

architecture test of tb_tg68k_fpu_control_controller is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 11) of std_logic_vector(31 downto 0);
	type word_trace_t is array (0 to 11) of std_logic_vector(15 downto 0);
	type control_trace_t is array (0 to 2) of fpu_control_register_t;
	type long_trace_t is array (0 to 2) of std_logic_vector(31 downto 0);

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal external_to_control : std_logic := '0';
	signal register_mask : std_logic_vector(2 downto 0) := "000";
	signal data_register_direct : std_logic := '0';
	signal address_register_direct : std_logic := '0';
	signal effective_address : std_logic_vector(31 downto 0) := x"00001000";
	signal function_code : std_logic_vector(2 downto 0) := "101";
	signal data_register_data : std_logic_vector(31 downto 0) :=
		x"00000000";
	signal address_register_data : std_logic_vector(31 downto 0) :=
		x"00000000";
	signal control_register_read_data : std_logic_vector(31 downto 0);
	signal control_register_select : fpu_control_register_t;
	signal control_register_write : std_logic;
	signal control_register_write_data : std_logic_vector(31 downto 0);
	signal memory_ready : std_logic;
	signal memory_error : std_logic := '0';
	signal retry : std_logic := '0';
	signal resume_context : std_logic := '0';
	signal saved_context_in : std_logic_vector(55 downto 0) :=
		(others => '0');
	signal saved_context_out : std_logic_vector(55 downto 0);
	signal alternate_control_values : std_logic := '0';
	signal memory_read_data : std_logic_vector(15 downto 0);
	signal memory_request : std_logic;
	signal memory_write : std_logic;
	signal memory_address : std_logic_vector(31 downto 0);
	signal memory_write_data : std_logic_vector(15 downto 0);
	signal memory_function_code : std_logic_vector(2 downto 0);
	signal data_register_write : std_logic;
	signal data_register_write_data : std_logic_vector(31 downto 0);
	signal address_register_write : std_logic;
	signal address_register_write_data : std_logic_vector(31 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
	signal bus_error_exception : std_logic;
	signal monitor_clear : std_logic := '0';
	signal bus_count : natural range 0 to 12 := 0;
	signal bus_addresses : address_trace_t := (others => (others => '0'));
	signal bus_words : word_trace_t := (others => (others => '0'));
	signal bus_writes : std_logic_vector(0 to 11) := (others => '0');
	signal control_count : natural range 0 to 3 := 0;
	signal control_selects : control_trace_t := (others => FPU_REG_FPCR);
	signal control_values : long_trace_t := (others => (others => '0'));
	signal data_write_count : natural range 0 to 1 := 0;
	signal address_write_count : natural range 0 to 1 := 0;
begin
	clk <= not clk after CLK_PERIOD / 2;
	memory_ready <= memory_request and not memory_error;

	control_read_mux : process(all)
	begin
		case control_register_select is
			when FPU_REG_FPCR =>
				if alternate_control_values = '1' then
					control_register_read_data <= x"DEADBEEF";
				else
					control_register_read_data <= x"AABBCCDD";
				end if;
			when FPU_REG_FPSR =>
				if alternate_control_values = '1' then
					control_register_read_data <= x"01234567";
				else
					control_register_read_data <= x"89ABCDEF";
				end if;
			when FPU_REG_FPIAR =>
				if alternate_control_values = '1' then
					control_register_read_data <= x"76543210";
				else
					control_register_read_data <= x"11223344";
				end if;
		end case;
	end process;

	read_memory : process(memory_address)
	begin
		case memory_address is
			when x"00001000" => memory_read_data <= x"1111";
			when x"00001002" => memory_read_data <= x"2222";
			when x"00001004" => memory_read_data <= x"3333";
			when x"00001006" => memory_read_data <= x"4444";
			when x"00001008" => memory_read_data <= x"5555";
			when x"0000100A" => memory_read_data <= x"6666";
			when others => memory_read_data <= x"0000";
		end case;
	end process;

	dut : entity work.TG68K_FPU_Control_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			external_to_control => external_to_control,
			register_mask => register_mask,
			data_register_direct => data_register_direct,
			address_register_direct => address_register_direct,
			effective_address => effective_address,
			function_code => function_code,
			data_register_data => data_register_data,
			address_register_data => address_register_data,
			control_register_read_data => control_register_read_data,
			control_register_select => control_register_select,
			control_register_write => control_register_write,
			control_register_write_data => control_register_write_data,
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
			memory_function_code => memory_function_code,
			data_register_write => data_register_write,
			data_register_write_data => data_register_write_data,
			address_register_write => address_register_write,
			address_register_write_data => address_register_write_data,
			busy => busy,
			done => done,
			bus_error_exception => bus_error_exception
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if monitor_clear = '1' then
				bus_count <= 0;
				control_count <= 0;
				data_write_count <= 0;
				address_write_count <= 0;
			else
				if memory_ready = '1' then
					bus_addresses(bus_count) <= memory_address;
					bus_words(bus_count) <= memory_write_data;
					bus_writes(bus_count) <= memory_write;
					bus_count <= bus_count + 1;
				end if;
				if control_register_write = '1' then
					control_selects(control_count) <= control_register_select;
					control_values(control_count) <= control_register_write_data;
					control_count <= control_count + 1;
				end if;
				if data_register_write = '1' then
					data_write_count <= data_write_count + 1;
				end if;
				if address_register_write = '1' then
					address_write_count <= address_write_count + 1;
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

		procedure start_transfer is
		begin
			wait until falling_edge(clk);
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
		end procedure;

		procedure wait_done is
			variable cycles : natural := 0;
		begin
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles < 50 report "control transfer did not complete"
					severity failure;
			end loop;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		clear_observations;
		external_to_control <= '1';
		register_mask <= "100";
		data_register_direct <= '1';
		data_register_data <= x"000000B0";
		start_transfer;
		wait_done;
		assert control_count = 1 and control_selects(0) = FPU_REG_FPCR and
			control_values(0) = x"000000B0" and bus_count = 0
			report "direct FPCR load mismatch" severity failure;

		clear_observations;
		data_register_direct <= '0';
		register_mask <= "111";
		effective_address <= x"00001000";
		start_transfer;
		wait_done;
		assert bus_count = 6 and bus_addresses(0) = x"00001000" and
			bus_addresses(5) = x"0000100A" and memory_function_code = "101" and
			control_count = 3 and control_selects(0) = FPU_REG_FPCR and
			control_selects(1) = FPU_REG_FPSR and
			control_selects(2) = FPU_REG_FPIAR and
			control_values(0) = x"11112222" and
			control_values(1) = x"33334444" and
			control_values(2) = x"55556666"
			report "memory-to-control FMOVEM ordering mismatch" severity failure;

		clear_observations;
		external_to_control <= '0';
		register_mask <= "101";
		start_transfer;
		wait_done;
		assert bus_count = 4 and bus_writes(0) = '1' and
			bus_addresses(0) = x"00001000" and bus_words(0) = x"AABB" and
			bus_words(1) = x"CCDD" and bus_addresses(2) = x"00001004" and
			bus_words(2) = x"1122" and bus_words(3) = x"3344"
			report "control-to-memory FMOVEM ordering mismatch" severity failure;

		clear_observations;
		register_mask <= "001";
		address_register_direct <= '1';
		start_transfer;
		wait_done;
		assert address_write_count = 1 and
			address_register_write_data = x"11223344" and bus_count = 0
			report "FPIAR-to-address-register transfer mismatch" severity failure;

		clear_observations;
		address_register_direct <= '0';
		external_to_control <= '1';
		register_mask <= "100";
		memory_error <= '1';
		start_transfer;
		wait until bus_error_exception = '1';
		assert memory_address = x"00001000" and done = '0'
			report "control transfer bus error state mismatch" severity failure;
		wait until falling_edge(clk);
		memory_error <= '0';
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		wait_done;
		assert control_count = 1 and control_values(0) = x"11112222"
			report "control transfer retry mismatch" severity failure;

		clear_observations;
		external_to_control <= '0';
		register_mask <= "100";
		alternate_control_values <= '0';
		start_transfer;
		wait until bus_count = 1;
		wait until falling_edge(clk);
		memory_error <= '1';
		wait until bus_error_exception = '1';
		saved_context_in <= saved_context_out;
		nReset <= '0';
		wait until rising_edge(clk);
		wait for 1 ns;
		nReset <= '1';
		memory_error <= '0';
		alternate_control_values <= '1';
		clear_observations;
		resume_context <= '1';
		start_transfer;
		resume_context <= '0';
		wait_done;
		assert bus_count = 1 and bus_addresses(0) = x"00001002" and
			bus_words(0) = x"CCDD"
			report "restored control transfer did not resume with saved data"
			severity failure;

		report "PASS: MC68882 control-register transfer sequencing"
			severity note;
		stop;
	end process;
end architecture;
