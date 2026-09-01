library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_movem_controller is
end entity;

architecture test of tb_tg68k_fpu_movem_controller is
	constant CLK_PERIOD : time := 10 ns;
	type address_trace_t is array (0 to 23) of std_logic_vector(31 downto 0);
	type word_trace_t is array (0 to 23) of std_logic_vector(15 downto 0);
	type select_trace_t is array (0 to 7) of std_logic_vector(2 downto 0);
	type data_trace_t is array (0 to 7) of fpu_extended_t;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal memory_to_register : std_logic := '1';
	signal predecrement : std_logic := '0';
	signal dynamic_list : std_logic := '0';
	signal static_register_list : std_logic_vector(7 downto 0) := x"00";
	signal dynamic_register_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal effective_address : std_logic_vector(31 downto 0) := x"00001000";
	signal function_code : std_logic_vector(2 downto 0) := "101";
	signal fp_registers : fpu_register_array_t := (
		0 => x"40008000000000000000",
		1 => x"40019000000000000001",
		5 => x"4005A000000000000005",
		6 => x"C002AABBCCDDEEFF0011",
		others => FPU_RESET_NAN);
	signal fp_register_read_data : fpu_extended_t;
	signal fp_register_select : std_logic_vector(2 downto 0);
	signal fp_register_write : std_logic;
	signal fp_register_write_data : fpu_extended_t;
	signal memory_ready : std_logic;
	signal memory_error : std_logic := '0';
	signal retry : std_logic := '0';
	signal resume_context : std_logic := '0';
	signal saved_context_in : std_logic_vector(197 downto 0) :=
		(others => '0');
	signal saved_context_out : std_logic_vector(197 downto 0);
	signal alternate_fp_read : std_logic := '0';
	signal memory_read_data : std_logic_vector(15 downto 0);
	signal memory_request : std_logic;
	signal memory_write : std_logic;
	signal memory_address : std_logic_vector(31 downto 0);
	signal memory_write_data : std_logic_vector(15 downto 0);
	signal memory_function_code : std_logic_vector(2 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
	signal bus_error_exception : std_logic;
	signal monitor_clear : std_logic := '0';
	signal bus_count : natural range 0 to 24 := 0;
	signal bus_addresses : address_trace_t := (others => (others => '0'));
	signal bus_words : word_trace_t := (others => (others => '0'));
	signal bus_writes : std_logic_vector(0 to 23) := (others => '0');
	signal write_count : natural range 0 to 8 := 0;
	signal write_selects : select_trace_t := (others => "000");
	signal write_values : data_trace_t := (others => (others => '0'));
begin
	clk <= not clk after CLK_PERIOD / 2;
	memory_ready <= memory_request and not memory_error;
	fp_register_read_data <= x"DEAD0123456789ABCDEF" when
		alternate_fp_read = '1' and fp_register_select = "110" else
		fp_registers(to_integer(unsigned(fp_register_select)));

	read_memory : process(memory_address)
	begin
		case memory_address is
			when x"00001000" => memory_read_data <= x"4000";
			when x"00001002" => memory_read_data <= x"DEAD";
			when x"00001004" => memory_read_data <= x"8000";
			when x"00001006" | x"00001008" => memory_read_data <= x"0000";
			when x"0000100A" => memory_read_data <= x"0007";
			when x"0000100C" => memory_read_data <= x"4001";
			when x"0000100E" => memory_read_data <= x"BEEF";
			when x"00001010" => memory_read_data <= x"9000";
			when x"00001012" | x"00001014" | x"00001016" =>
				memory_read_data <= x"0000";
			when x"00005000" => memory_read_data <= x"4005";
			when x"00005002" => memory_read_data <= x"CAFE";
			when x"00005004" => memory_read_data <= x"A000";
			when x"00005006" | x"00005008" => memory_read_data <= x"0000";
			when x"0000500A" => memory_read_data <= x"0005";
			when others => memory_read_data <= x"0000";
		end case;
	end process;

	dut : entity work.TG68K_FPU_Movem_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			memory_to_register => memory_to_register,
			predecrement => predecrement,
			dynamic_list => dynamic_list,
			static_register_list => static_register_list,
			dynamic_register_data => dynamic_register_data,
			effective_address => effective_address,
			function_code => function_code,
			fp_register_read_data => fp_register_read_data,
			fp_register_select => fp_register_select,
			fp_register_write => fp_register_write,
			fp_register_write_data => fp_register_write_data,
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
			busy => busy,
			done => done,
			bus_error_exception => bus_error_exception
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if monitor_clear = '1' then
				bus_count <= 0;
				write_count <= 0;
			else
				if memory_ready = '1' then
					bus_addresses(bus_count) <= memory_address;
					bus_words(bus_count) <= memory_write_data;
					bus_writes(bus_count) <= memory_write;
					bus_count <= bus_count + 1;
				end if;
				if fp_register_write = '1' then
					write_selects(write_count) <= fp_register_select;
					write_values(write_count) <= fp_register_write_data;
					fp_registers(to_integer(unsigned(fp_register_select))) <=
						fp_register_write_data;
					write_count <= write_count + 1;
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
			variable cycle_count : natural := 0;
		begin
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycle_count := cycle_count + 1;
				assert cycle_count < 150
					report "FMOVEM transfer did not complete" severity failure;
			end loop;
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		clear_observations;
		memory_to_register <= '1';
		predecrement <= '0';
		dynamic_list <= '0';
		static_register_list <= x"81";
		effective_address <= x"00001000";
		start_transfer;
		wait_done;
		assert bus_count = 12 and bus_writes(0) = '0' and
			bus_addresses(0) = x"00001000" and
			bus_addresses(11) = x"00001016" and
			write_count = 2 and write_selects(0) = "111" and
			write_selects(1) = "000" and
			write_values(0) = x"40008000000000000007" and
			write_values(1) = x"40019000000000000000" and
			memory_function_code = "101"
			report "static ascending FMOVEM load mismatch" severity failure;

		clear_observations;
		memory_to_register <= '0';
		static_register_list <= x"42";
		effective_address <= x"00003000";
		start_transfer;
		wait_done;
		assert bus_count = 12 and bus_writes(0) = '1' and
			bus_addresses(0) = x"00003000" and
			bus_addresses(11) = x"00003016" and
			bus_words(0) = x"C002" and bus_words(1) = x"0000" and
			bus_words(2) = x"AABB" and bus_words(5) = x"0011" and
			bus_words(6) = x"4001"
			report "static ascending FMOVEM store mismatch" severity failure;

		clear_observations;
		predecrement <= '1';
		static_register_list <= x"41";
		effective_address <= x"00004000";
		start_transfer;
		wait_done;
		assert bus_count = 12 and bus_addresses(0) = x"00003FF4" and
			bus_addresses(5) = x"00003FFE" and
			bus_addresses(6) = x"00003FE8" and
			bus_addresses(11) = x"00003FF2" and
			bus_words(0) = x"C002" and bus_words(6) = x"4001"
			report "predecrement FMOVEM order mismatch" severity failure;

		clear_observations;
		memory_to_register <= '1';
		predecrement <= '0';
		dynamic_list <= '1';
		dynamic_register_data <= x"12340004";
		effective_address <= x"00005000";
		start_transfer;
		wait_done;
		assert bus_count = 6 and write_count = 1 and
			write_selects(0) = "101" and
			write_values(0) = x"4005A000000000000005"
			report "dynamic FMOVEM register selection mismatch" severity failure;

		clear_observations;
		memory_to_register <= '0';
		predecrement <= '1';
		dynamic_register_data <= x"00000040";
		effective_address <= x"00006000";
		start_transfer;
		wait_done;
		assert bus_count = 6 and bus_addresses(0) = x"00005FF4" and
			bus_addresses(5) = x"00005FFE" and bus_words(0) = x"C002" and
			bus_words(5) = x"0011"
			report "dynamic predecrement FMOVEM mapping mismatch"
			severity failure;

		clear_observations;
		dynamic_list <= '0';
		predecrement <= '0';
		memory_to_register <= '1';
		static_register_list <= x"00";
		start_transfer;
		wait_done;
		assert bus_count = 0 and write_count = 0
			report "empty FMOVEM list caused a transfer" severity failure;

		clear_observations;
		static_register_list <= x"01";
		effective_address <= x"00001000";
		memory_error <= '1';
		start_transfer;
		wait until bus_error_exception = '1';
		assert memory_address = x"00001000" and done = '0'
			report "FMOVEM bus-error state mismatch" severity failure;
		wait until falling_edge(clk);
		memory_error <= '0';
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		wait_done;
		assert bus_count = 6 and write_count = 1 and
			write_selects(0) = "111"
			report "FMOVEM retry mismatch" severity failure;

		clear_observations;
		memory_to_register <= '0';
		static_register_list <= x"02";
		effective_address <= x"00007000";
		start_transfer;
		wait until bus_count = 2;
		wait until falling_edge(clk);
		memory_error <= '1';
		wait until bus_error_exception = '1';
		saved_context_in <= saved_context_out;
		nReset <= '0';
		wait until rising_edge(clk);
		wait for 1 ns;
		nReset <= '1';
		memory_error <= '0';
		alternate_fp_read <= '1';
		clear_observations;
		resume_context <= '1';
		start_transfer;
		resume_context <= '0';
		wait_done;
		assert bus_count = 4 and bus_addresses(0) = x"00007004" and
			bus_addresses(3) = x"0000700A" and
			bus_words(0) = x"AABB" and bus_words(1) = x"CCDD" and
			bus_words(2) = x"EEFF" and bus_words(3) = x"0011"
			report "restored FMOVEM did not resume with saved register data"
			severity failure;

		report "PASS: MC68882 FP data-register FMOVEM sequencing"
			severity note;
		stop;
	end process;
end architecture;
