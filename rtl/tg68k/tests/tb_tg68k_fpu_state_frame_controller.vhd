library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_state_frame_controller is
end entity;

architecture test of tb_tg68k_fpu_state_frame_controller is
	constant CLK_PERIOD : time := 10 ns;
	constant BASE_ADDRESS : std_logic_vector(31 downto 0) := x"00001000";
	type word_array_t is array (0 to 107) of std_logic_vector(15 downto 0);
	type address_array_t is array (0 to 107) of std_logic_vector(31 downto 0);

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal family : fpu_instruction_family_t := FPU_FAMILY_SAVE;
	signal initialized : std_logic := '0';
	signal suspended : std_logic := '0';
	signal exception_pending : std_logic := '0';
	signal command_condition : std_logic_vector(31 downto 0) := x"12345678";
	signal exceptional_operand : fpu_extended_t :=
		x"C00289ABCDEF01234567";
	signal busy_context : fpu_busy_context_t := (others => '0');
	signal busy_context_metadata : fpu_busy_context_metadata_t;
	signal busy_context_resume : fpu_busy_context_resume_t;
	signal effective_address : std_logic_vector(31 downto 0) := BASE_ADDRESS;
	signal function_code : std_logic_vector(2 downto 0) := "101";
	signal memory_image : word_array_t := (others => (others => '0'));
	signal memory_ready_enable : std_logic := '1';
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
	signal frame_byte_count : natural range 0 to
		FPU_STATE_FRAME_BUSY_BYTES_68882;
	signal save_complete : std_logic;
	signal restore_null : std_logic;
	signal restore_idle : std_logic;
	signal restore_busy : std_logic;
	signal restore_exception_pending : std_logic;
	signal restore_command_condition : std_logic_vector(31 downto 0);
	signal restore_exceptional_operand : fpu_extended_t;
	signal restore_busy_context : fpu_busy_context_t;
	signal format_error_exception : std_logic;
	signal busy : std_logic;
	signal done : std_logic;
	signal bus_error_exception : std_logic;
	signal monitor_clear : std_logic := '0';
	signal bus_count : natural range 0 to 108 := 0;
	signal bus_addresses : address_array_t := (others => (others => '0'));
	signal bus_words : word_array_t := (others => (others => '0'));
	signal bus_writes : std_logic_vector(0 to 107) := (others => '0');
begin
	clk <= not clk after CLK_PERIOD / 2;
	busy_context_metadata <= busy_context(busy_context'high downto
		busy_context'high - busy_context_metadata'length + 1);
	busy_context_resume <= busy_context(busy_context_resume'range);
	memory_ready <= memory_request and memory_ready_enable and
		not memory_error;

	read_memory : process(memory_address, memory_image)
		variable word_index : integer;
	begin
		word_index := (to_integer(unsigned(memory_address(15 downto 0))) -
			16#1000#) / 2;
		if memory_address(31 downto 16) = x"0000" and
			word_index >= 0 and word_index <= 107 then
			memory_read_data <= memory_image(word_index);
		else
			memory_read_data <= x"0000";
		end if;
	end process;

	dut : entity work.TG68K_FPU_State_Frame_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			family => family,
			initialized => initialized,
			suspended => suspended,
			exception_pending => exception_pending,
			command_condition => command_condition,
			exceptional_operand => exceptional_operand,
			busy_context_metadata => busy_context_metadata,
			busy_context_resume => busy_context_resume,
			effective_address => effective_address,
			function_code => function_code,
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
			frame_byte_count => frame_byte_count,
			save_complete => save_complete,
			restore_null => restore_null,
			restore_idle => restore_idle,
			restore_busy => restore_busy,
			restore_exception_pending => restore_exception_pending,
			restore_command_condition => restore_command_condition,
			restore_exceptional_operand => restore_exceptional_operand,
			restore_busy_context => restore_busy_context,
			format_error_exception => format_error_exception,
			busy => busy,
			done => done,
			bus_error_exception => bus_error_exception
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if monitor_clear = '1' then
				bus_count <= 0;
			else
				if memory_ready = '1' then
					bus_addresses(bus_count) <= memory_address;
					bus_words(bus_count) <= memory_write_data;
					bus_writes(bus_count) <= memory_write;
					bus_count <= bus_count + 1;
				end if;
			end if;
		end if;
	end process;

	stimulus : process
		procedure clear_trace is
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

		procedure await_done is
			variable cycles : natural := 0;
		begin
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles < 240
					report "state-frame transfer did not complete"
					severity failure;
			end loop;
		end procedure;

		procedure finish_operation is
		begin
			wait until rising_edge(clk);
			wait for 1 ns;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		clear_trace;
		family <= FPU_FAMILY_SAVE;
		initialized <= '0';
		exception_pending <= '0';
		start_operation;
		await_done;
		assert bus_count = 2 and bus_writes(0) = '1' and
			bus_addresses(0) = BASE_ADDRESS and
			bus_addresses(1) = x"00001002" and
			bus_words(0) = x"0000" and bus_words(1) = x"0000" and
			frame_byte_count = 4 and save_complete = '1' and
			memory_function_code = "101" and memory_nuds = '0' and
			memory_nlds = '0'
			report "null FSAVE frame mismatch" severity failure;
		finish_operation;

		clear_trace;
		initialized <= '1';
		start_operation;
		await_done;
		assert bus_count = 30 and bus_words(0) = x"1F38" and
			bus_words(1) = x"0000" and
			bus_addresses(2) = x"00001038" and
			bus_words(2) = x"7C0E" and bus_words(3) = x"FFFF" and
			bus_addresses(4) = x"00001034" and
			bus_words(4) = x"0000" and bus_words(5) = x"0000" and
			bus_addresses(6) = x"00001030" and
			bus_words(6) = x"0123" and bus_words(7) = x"4567" and
			bus_words(8) = x"89AB" and bus_words(9) = x"CDEF" and
			bus_words(10) = x"C002" and bus_words(11) = x"0000" and
			bus_addresses(28) = x"00001004" and
			bus_words(28) = x"1234" and bus_words(29) = x"5678" and
			frame_byte_count = 60 and save_complete = '1'
			report "idle FSAVE frame layout mismatch" severity failure;
		finish_operation;

		clear_trace;
		exception_pending <= '1';
		start_operation;
		await_done;
		assert bus_words(2) = x"740E" and bus_words(3) = x"FFFF"
			report "pending-exception FSAVE flags mismatch" severity failure;
		finish_operation;

		clear_trace;
		suspended <= '1';
		busy_context <= (others => '0');
		busy_context(busy_context'high downto busy_context'high - 31) <=
			x"ABCD1234";
		busy_context(31 downto 0) <= x"DCBA9876";
		start_operation;
		await_done;
		assert bus_count = 108 and bus_words(0) = x"1FD4" and
			bus_words(1) = x"0000" and
			bus_addresses(2) = x"000010D4" and
			bus_words(2) = x"DCBA" and bus_words(3) = x"9876" and
			bus_addresses(106) = x"00001004" and
			bus_words(106) = x"ABCD" and bus_words(107) = x"1234" and
			frame_byte_count = FPU_STATE_FRAME_BUSY_BYTES_68882 and
			save_complete = '1'
			report "busy FSAVE frame layout mismatch" severity failure;
		finish_operation;
		suspended <= '0';

		clear_trace;
		family <= FPU_FAMILY_RESTORE;
		memory_image <= (0 => x"00A5", 1 => x"C0DE", others => x"FFFF");
		start_operation;
		await_done;
		assert bus_count = 2 and bus_writes(0) = '0' and
			bus_addresses(0) = BASE_ADDRESS and
			bus_addresses(1) = x"00001002" and
			frame_byte_count = 4 and restore_null = '1' and
			restore_idle = '0' and format_error_exception = '0'
			report "null FRESTORE mismatch" severity failure;
		finish_operation;

		clear_trace;
		memory_image <= (
			0 => x"1F38", 1 => x"BEEF", 2 => x"89AB", 3 => x"CDEF",
			20 => x"BFFE", 21 => x"FFFF", 22 => x"8000",
			23 => x"1234", 24 => x"5678", 25 => x"9ABC",
			28 => x"740E", 29 => x"1234", others => x"0000");
		start_operation;
		await_done;
		assert bus_count = 30 and bus_addresses(29) = x"0000103A" and
			frame_byte_count = 60 and restore_idle = '1' and
			restore_exception_pending = '1' and
			restore_command_condition = x"89ABCDEF" and
			restore_exceptional_operand = x"BFFE8000123456789ABC" and
			format_error_exception = '0'
			report "idle FRESTORE state mismatch" severity failure;
		finish_operation;

		clear_trace;
		memory_image <= (
			0 => x"1FD4", 1 => x"0000", 2 => x"ABCD", 3 => x"1234",
			106 => x"DCBA", 107 => x"9876", others => x"0000");
		start_operation;
		await_done;
		assert bus_count = 108 and bus_addresses(107) = x"000010D6" and
			frame_byte_count = FPU_STATE_FRAME_BUSY_BYTES_68882 and
			restore_busy = '1' and restore_null = '0' and
			restore_idle = '0' and
			restore_busy_context(
				restore_busy_context'high downto
				restore_busy_context'high - 31) = x"ABCD1234" and
			restore_busy_context(31 downto 0) = x"DCBA9876" and
			format_error_exception = '0'
			report "busy FRESTORE context mismatch" severity failure;
		finish_operation;

		clear_trace;
		memory_image <= (0 => x"2A38", 1 => x"0000", others => x"0000");
		start_operation;
		await_done;
		assert bus_count = 2 and format_error_exception = '1' and
			restore_null = '0' and restore_idle = '0'
			report "invalid-version FRESTORE mismatch" severity failure;
		finish_operation;

		clear_trace;
		memory_image <= (0 => x"1F18", 1 => x"0000", others => x"0000");
		start_operation;
		await_done;
		assert bus_count = 2 and format_error_exception = '1'
			report "invalid-size FRESTORE mismatch" severity failure;
		finish_operation;

		clear_trace;
		family <= FPU_FAMILY_SAVE;
		initialized <= '0';
		memory_error <= '1';
		start_operation;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert bus_error_exception = '1' and
			memory_address = BASE_ADDRESS and bus_count = 0
			report "FSAVE bus-error suspension mismatch" severity failure;
		wait until falling_edge(clk);
		memory_error <= '0';
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		assert memory_request = '1' and memory_address = BASE_ADDRESS
			report "FSAVE retry did not reproduce failed cycle" severity failure;
		await_done;
		assert bus_count = 2 and save_complete = '1'
			report "retried FSAVE did not complete" severity failure;
		finish_operation;

		clear_trace;
		family <= FPU_FAMILY_RESTORE;
		memory_image <= (0 => x"0000", 1 => x"0000", others => x"0000");
		memory_error <= '1';
		start_operation;
		wait until rising_edge(clk);
		wait for 1 ns;
		assert bus_error_exception = '1' and bus_count = 0
			report "FRESTORE bus-error suspension mismatch" severity failure;
		wait until falling_edge(clk);
		memory_error <= '0';
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		assert memory_request = '1' and memory_write = '0' and
			memory_address = BASE_ADDRESS
			report "FRESTORE retry did not reproduce failed cycle" severity failure;
		await_done;
		assert bus_count = 2 and restore_null = '1'
			report "retried FRESTORE did not complete" severity failure;

		report "TG68K FPU state-frame controller tests passed" severity note;
		stop;
		wait;
	end process;
end architecture;
