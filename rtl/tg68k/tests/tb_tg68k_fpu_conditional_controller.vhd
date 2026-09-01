library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_conditional_controller is
end entity;

architecture test of tb_tg68k_fpu_conditional_controller is
	constant CLK_PERIOD : time := 10 ns;

	function expected_condition(
		predicate_value : natural;
		condition_value : natural) return std_logic is
		variable negative : boolean;
		variable zero : boolean;
		variable unordered : boolean;
		variable result : boolean;
	begin
		negative := condition_value mod 16 >= 8;
		zero := condition_value mod 8 >= 4;
		unordered := condition_value mod 2 = 1;
		case predicate_value mod 16 is
			when 0 => result := false;
			when 1 => result := zero;
			when 2 => result := not unordered and not zero and not negative;
			when 3 => result := zero or (not unordered and not negative);
			when 4 => result := negative and not unordered and not zero;
			when 5 => result := zero or (negative and not unordered);
			when 6 => result := not unordered and not zero;
			when 7 => result := not unordered;
			when 8 => result := unordered;
			when 9 => result := unordered or zero;
			when 10 => result := unordered or (not zero and not negative);
			when 11 => result := unordered or zero or not negative;
			when 12 => result := unordered or (negative and not zero);
			when 13 => result := unordered or zero or negative;
			when 14 => result := not zero;
			when others => result := true;
		end case;
		if result then
			return '1';
		end if;
		return '0';
	end function;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal family : fpu_instruction_family_t := FPU_FAMILY_SCC;
	signal predicate : std_logic_vector(5 downto 0) := (others => '0');
	signal condition_codes : std_logic_vector(3 downto 0) := (others => '0');
	signal bsun_enable : std_logic := '0';
	signal data_register_direct : std_logic := '1';
	signal integer_register_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal effective_address : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal function_code : std_logic_vector(2 downto 0) := "101";
	signal memory_ready : std_logic;
	signal memory_error : std_logic := '0';
	signal retry : std_logic := '0';
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
	signal conditional_status_write : std_logic;
	signal conditional_bsun : std_logic;
	signal condition_result : std_logic;
	signal branch_taken : std_logic;
	signal trap_taken : std_logic;
	signal busy : std_logic;
	signal done : std_logic;
	signal bus_error_exception : std_logic;
	signal status_count : natural range 0 to 512 := 0;
	signal register_write_count : natural range 0 to 512 := 0;
	signal memory_write_count : natural range 0 to 512 := 0;
	signal observed_memory_address : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal observed_memory_data : std_logic_vector(15 downto 0) :=
		(others => '0');
	signal observed_memory_nuds : std_logic := '1';
	signal observed_memory_nlds : std_logic := '1';
	signal observed_memory_fc : std_logic_vector(2 downto 0) :=
		(others => '0');
begin
	clk <= not clk after CLK_PERIOD / 2;
	memory_ready <= memory_request and not memory_error;

	dut : entity work.TG68K_FPU_Conditional_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			family => family,
			predicate => predicate,
			condition_codes => condition_codes,
			bsun_enable => bsun_enable,
			data_register_direct => data_register_direct,
			integer_register_data => integer_register_data,
			effective_address => effective_address,
			function_code => function_code,
			memory_ready => memory_ready,
			memory_error => memory_error,
			retry => retry,
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
			conditional_status_write => conditional_status_write,
			conditional_bsun => conditional_bsun,
			condition_result => condition_result,
			branch_taken => branch_taken,
			trap_taken => trap_taken,
			busy => busy,
			done => done,
			bus_error_exception => bus_error_exception
		);

	monitor : process(clk)
	begin
		if rising_edge(clk) then
			if conditional_status_write = '1' then
				status_count <= status_count + 1;
			end if;
			if integer_register_write = '1' then
				register_write_count <= register_write_count + 1;
			end if;
			if memory_ready = '1' and memory_write = '1' then
				memory_write_count <= memory_write_count + 1;
				observed_memory_address <= memory_address;
				observed_memory_data <= memory_write_data;
				observed_memory_nuds <= memory_nuds;
				observed_memory_nlds <= memory_nlds;
				observed_memory_fc <= memory_function_code;
			end if;
		end if;
	end process;

	stimulus : process
		procedure issue is
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
				assert cycles < 12 report "conditional operation timed out"
					severity failure;
			end loop;
		end procedure;

		procedure await_idle is
		begin
			wait until rising_edge(clk);
			wait for 1 ns;
			assert done = '0' and busy = '0'
				report "conditional controller did not return idle"
				severity failure;
		end procedure;

		variable status_before : natural;
		variable register_before : natural;
		variable memory_before : natural;
		variable condition_value : natural;
		variable expected_result : std_logic;
		variable expected_bsun : std_logic;
	begin
		wait for 2 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		family <= FPU_FAMILY_SCC;
		predicate <= "000001";
		condition_codes <= "0100";
		data_register_direct <= '1';
		status_before := status_count;
		register_before := register_write_count;
		issue;
		await_done;
		assert condition_result = '1' and
			register_write_count = register_before + 1 and
			integer_register_write_data(7 downto 0) = x"FF" and
			integer_register_write_format = FPU_FORMAT_BYTE_INTEGER and
			status_count = status_before + 1 and conditional_bsun = '0'
			report "true register FScc mismatch" severity failure;
		await_idle;

		predicate <= "000000";
		register_before := register_write_count;
		issue;
		await_done;
		assert condition_result = '0' and
			register_write_count = register_before + 1 and
			integer_register_write_data(7 downto 0) = x"00"
			report "false register FScc mismatch" severity failure;
		await_idle;

		predicate <= "001111";
		data_register_direct <= '0';
		effective_address <= x"12345678";
		memory_before := memory_write_count;
		issue;
		await_done;
		assert memory_write_count = memory_before + 1 and
			observed_memory_address = x"12345678" and
			observed_memory_data = x"FFFF" and
			observed_memory_nuds = '0' and observed_memory_nlds = '1' and
			observed_memory_fc = "101"
			report "even memory FScc mismatch" severity failure;
		await_idle;

		effective_address <= x"12345679";
		memory_before := memory_write_count;
		issue;
		await_done;
		assert memory_write_count = memory_before + 1 and
			observed_memory_nuds = '1' and observed_memory_nlds = '0'
			report "odd memory FScc mismatch" severity failure;
		await_idle;

		family <= FPU_FAMILY_DBCC;
		data_register_direct <= '1';
		predicate <= "000001";
		condition_codes <= "0100";
		integer_register_data <= x"CAFE0002";
		register_before := register_write_count;
		issue;
		await_done;
		assert branch_taken = '0' and
			register_write_count = register_before
			report "true FDBcc changed its counter" severity failure;
		await_idle;

		condition_codes <= "0000";
		register_before := register_write_count;
		issue;
		await_done;
		assert branch_taken = '1' and
			register_write_count = register_before + 1 and
			integer_register_write_data(15 downto 0) = x"0001" and
			integer_register_write_format = FPU_FORMAT_WORD_INTEGER
			report "taken FDBcc mismatch" severity failure;
		await_idle;

		integer_register_data <= x"CAFE0000";
		register_before := register_write_count;
		issue;
		await_done;
		assert branch_taken = '0' and
			register_write_count = register_before + 1 and
			integer_register_write_data(15 downto 0) = x"FFFF"
			report "exhausted FDBcc mismatch" severity failure;
		await_idle;

		family <= FPU_FAMILY_BCC_LONG;
		predicate <= "001111";
		issue;
		await_done;
		assert branch_taken = '1' and trap_taken = '0'
			report "true FBcc mismatch" severity failure;
		await_idle;

		family <= FPU_FAMILY_TRAPCC;
		issue;
		await_done;
		assert trap_taken = '1' and branch_taken = '0'
			report "true FTRAPcc mismatch" severity failure;
		await_idle;

		family <= FPU_FAMILY_SCC;
		data_register_direct <= '1';
		predicate <= "010001";
		condition_codes <= "0001";
		bsun_enable <= '0';
		status_before := status_count;
		register_before := register_write_count;
		issue;
		await_done;
		assert conditional_bsun = '1' and condition_result = '0' and
			status_count = status_before + 1 and
			register_write_count = register_before + 1
			report "masked BSUN conditional mismatch" severity failure;
		await_idle;

		bsun_enable <= '1';
		register_before := register_write_count;
		issue;
		await_done;
		assert conditional_bsun = '1' and
			register_write_count = register_before and branch_taken = '0' and
			trap_taken = '0'
			report "enabled BSUN did not suppress the destination"
			severity failure;
		await_idle;

		data_register_direct <= '0';
		predicate <= "001111";
		condition_codes <= "0000";
		bsun_enable <= '0';
		memory_error <= '1';
		issue;
		wait until rising_edge(clk) and bus_error_exception = '1';
		wait for 1 ns;
		assert done = '0' report "faulted FScc completed before retry"
			severity failure;
		memory_error <= '0';
		retry <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		retry <= '0';
		await_done;
		await_idle;

		data_register_direct <= '1';
		integer_register_data <= x"00000002";
		bsun_enable <= '0';
		for family_index in 0 to 4 loop
			case family_index is
				when 0 => family <= FPU_FAMILY_SCC;
				when 1 => family <= FPU_FAMILY_DBCC;
				when 2 => family <= FPU_FAMILY_BCC_WORD;
				when 3 => family <= FPU_FAMILY_BCC_LONG;
				when others => family <= FPU_FAMILY_TRAPCC;
			end case;
			for predicate_value in 0 to 63 loop
				condition_value := (predicate_value * 5 + family_index) mod 16;
				predicate <= std_logic_vector(to_unsigned(predicate_value, 6));
				condition_codes <= std_logic_vector(to_unsigned(
					condition_value, 4));
				expected_result := expected_condition(predicate_value,
					condition_value);
				if predicate_value mod 32 >= 16 and
						condition_value mod 2 = 1 then
					expected_bsun := '1';
				else
					expected_bsun := '0';
				end if;
				issue;
				await_done;
				assert condition_result = expected_result and
					conditional_bsun = expected_bsun
					report "conditional predicate result mismatch"
					severity failure;
				case family_index is
					when 0 =>
						assert branch_taken = '0' and trap_taken = '0'
							report "exhaustive FScc result mismatch"
							severity failure;
						if expected_result = '1' then
							assert integer_register_write_data(7 downto 0) = x"FF"
								report "exhaustive true FScc byte mismatch"
								severity failure;
						else
							assert integer_register_write_data(7 downto 0) = x"00"
								report "exhaustive false FScc byte mismatch"
								severity failure;
						end if;
					when 1 =>
						assert trap_taken = '0' and
							branch_taken = not expected_result
							report "exhaustive FDBcc result mismatch"
							severity failure;
					when 2 | 3 =>
						assert branch_taken = expected_result and
							trap_taken = '0'
							report "exhaustive FBcc result mismatch"
							severity failure;
					when others =>
						assert trap_taken = expected_result and
							branch_taken = '0'
							report "exhaustive FTRAPcc result mismatch"
							severity failure;
				end case;
				await_idle;
			end loop;
		end loop;

		report "PASS: MC68882 conditional controller and all predicate encodings"
			severity note;
		stop;
	end process;
end architecture;
