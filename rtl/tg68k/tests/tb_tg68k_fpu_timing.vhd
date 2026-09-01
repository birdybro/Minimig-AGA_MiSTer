library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_timing is
end entity;

architecture test of tb_tg68k_fpu_timing is
	constant CLK_PERIOD : time := 10 ns;
	type operation_array_t is array (natural range <>) of fpu_operation_t;
	type format_array_t is array (natural range <>) of fpu_operand_format_t;
	type natural_array_t is array (natural range <>) of natural;
	type timing_matrix_t is array (natural range <>, natural range <>) of natural;

	constant OPERATIONS : operation_array_t(0 to 37) := (
		FPU_OP_MOVE, FPU_OP_INT, FPU_OP_SINH, FPU_OP_INTRZ, FPU_OP_SQRT,
		FPU_OP_LOGNP1, FPU_OP_ETOXM1, FPU_OP_TANH, FPU_OP_ATAN,
		FPU_OP_ASIN, FPU_OP_ATANH, FPU_OP_SIN, FPU_OP_TAN, FPU_OP_ETOX,
		FPU_OP_TWOTOX, FPU_OP_TENTOX, FPU_OP_LOGN, FPU_OP_LOG10,
		FPU_OP_LOG2, FPU_OP_ABS, FPU_OP_COSH, FPU_OP_NEG, FPU_OP_ACOS,
		FPU_OP_COS, FPU_OP_GETEXP, FPU_OP_GETMAN, FPU_OP_DIV, FPU_OP_MOD,
		FPU_OP_ADD, FPU_OP_MUL, FPU_OP_SGLDIV, FPU_OP_REM, FPU_OP_SCALE,
		FPU_OP_SGLMUL, FPU_OP_SUB, FPU_OP_SINCOS, FPU_OP_CMP, FPU_OP_TST);
	constant FORMATS : format_array_t(0 to 4) := (
		FPU_FORMAT_LONG_INTEGER, FPU_FORMAT_SINGLE, FPU_FORMAT_DOUBLE,
		FPU_FORMAT_EXTENDED, FPU_FORMAT_PACKED);
	constant REGISTER_TOTALS : natural_array_t(OPERATIONS'range) := (
		21, 58, 690, 58, 110, 574, 548, 664, 406, 584, 696, 394, 475,
		500, 570, 570, 528, 584, 584, 38, 610, 38, 628, 394, 48, 34,
		108, 75, 56, 76, 74, 105, 46, 54, 56, 454, 38, 36);
	constant EXTERNAL_TOTALS : timing_matrix_t(OPERATIONS'range, FORMATS'range) := (
		(48, 34, 40, 46, 891),
		(88, 71, 77, 83, 913),
		(720, 703, 709, 715, 1545),
		(88, 71, 77, 83, 913),
		(140, 123, 129, 135, 965),
		(604, 587, 593, 599, 1429),
		(578, 561, 567, 573, 1403),
		(694, 677, 683, 689, 1519),
		(436, 419, 425, 431, 1261),
		(614, 597, 603, 609, 1439),
		(725, 709, 715, 721, 1551),
		(424, 407, 413, 419, 1249),
		(506, 489, 495, 501, 1331),
		(530, 513, 519, 525, 1355),
		(600, 583, 589, 595, 1425),
		(600, 583, 589, 595, 1425),
		(558, 541, 547, 553, 1383),
		(614, 597, 603, 609, 1439),
		(614, 597, 603, 609, 1439),
		(68, 51, 57, 63, 893),
		(640, 623, 629, 635, 1465),
		(68, 51, 57, 63, 893),
		(658, 641, 647, 653, 1483),
		(424, 407, 413, 419, 1249),
		(78, 61, 67, 73, 903),
		(64, 47, 53, 59, 889),
		(146, 121, 127, 133, 961),
		(113, 88, 94, 100, 928),
		(94, 69, 75, 81, 909),
		(114, 89, 95, 101, 929),
		(112, 87, 93, 99, 927),
		(143, 118, 124, 130, 958),
		(84, 59, 65, 71, 899),
		(102, 77, 83, 89, 917),
		(94, 69, 75, 81, 909),
		(484, 467, 473, 479, 1309),
		(76, 51, 57, 63, 891),
		(66, 49, 55, 61, 891));

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal abort_operation : std_logic := '0';
	signal family : fpu_instruction_family_t := FPU_FAMILY_NONE;
	signal operation : fpu_operation_t := FPU_OP_UNDEFINED;
	signal operand_format : fpu_operand_format_t := FPU_FORMAT_EXTENDED;
	signal address_mode : std_logic_vector(2 downto 0) := "010";
	signal address_register : std_logic_vector(2 downto 0) := "000";
	signal control_register_mask : std_logic_vector(2 downto 0) := "001";
	signal data_register_mask : std_logic_vector(7 downto 0) := x"01";
	signal dynamic_register_mask : std_logic := '0';
	signal condition_true : std_logic := '0';
	signal integer_register_data : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal initialized : std_logic := '0';
	signal suspended : std_logic := '0';
	signal frame_byte_count : natural range 0 to
		FPU_STATE_FRAME_BUSY_BYTES_68882 := FPU_STATE_FRAME_NULL_BYTES;
	signal core_done : std_logic := '0';
	signal core_branch_taken : std_logic := '0';
	signal core_trap_taken : std_logic := '0';
	signal core_format_error : std_logic := '0';
	signal core_exception_trap : std_logic := '0';
	signal core_exception_class : fpu_exception_t := FPU_EXCEPTION_NONE;
	signal busy : std_logic;
	signal done : std_logic;
	signal branch_taken : std_logic;
	signal trap_taken : std_logic;
	signal format_error : std_logic;
	signal exception_trap : std_logic;
	signal exception_class : fpu_exception_t;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Timing
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			abort_operation => abort_operation,
			family => family,
			operation => operation,
			operand_format => operand_format,
			address_mode => address_mode,
			address_register => address_register,
			control_register_mask => control_register_mask,
			data_register_mask => data_register_mask,
			dynamic_register_mask => dynamic_register_mask,
			condition_true => condition_true,
			integer_register_data => integer_register_data,
			initialized => initialized,
			suspended => suspended,
			frame_byte_count => frame_byte_count,
			core_done => core_done,
			core_branch_taken => core_branch_taken,
			core_trap_taken => core_trap_taken,
			core_format_error => core_format_error,
			core_exception_trap => core_exception_trap,
			core_exception_class => core_exception_class,
			busy => busy,
			done => done,
			branch_taken => branch_taken,
			trap_taken => trap_taken,
			format_error => format_error,
			exception_trap => exception_trap,
			exception_class => exception_class
		);

	stimulus : process
		procedure run_case(
			constant expected_cycles : natural;
			constant expected_branch : std_logic := '0';
			constant expected_trap : std_logic := '0';
			constant expected_format_error : std_logic := '0';
			constant expected_exception : std_logic := '0') is
			variable cycles : natural := 0;
		begin
			wait until falling_edge(clk);
			start <= '1';
			core_done <= '1';
			core_branch_taken <= expected_branch;
			core_trap_taken <= expected_trap;
			core_format_error <= expected_format_error;
			core_exception_trap <= expected_exception;
			core_exception_class <= FPU_EXCEPTION_DZ;
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			assert busy = '1' and done = '0'
				report "timing controller did not enter busy state" severity failure;
			while done = '0' loop
				wait until rising_edge(clk);
				wait for 1 ns;
				cycles := cycles + 1;
				assert cycles <= expected_cycles
					report "timing controller completed late" severity failure;
			end loop;
			assert cycles = expected_cycles and busy = '0' and
				branch_taken = expected_branch and trap_taken = expected_trap and
				format_error = expected_format_error and
				exception_trap = expected_exception
				report "timing controller completion mismatch" severity failure;
			if expected_exception = '1' then
				assert exception_class = FPU_EXCEPTION_DZ
					report "timed exception class mismatch" severity failure;
			end if;
			core_done <= '0';
			core_branch_taken <= '0';
			core_trap_taken <= '0';
			core_format_error <= '0';
			core_exception_trap <= '0';
			wait until rising_edge(clk);
			wait for 1 ns;
			assert done = '0' and branch_taken = '0' and trap_taken = '0' and
				format_error = '0' and exception_trap = '0'
				report "timing completion signals did not clear" severity failure;
		end procedure;
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';

		family <= FPU_FAMILY_REGISTER_OPERATION;
		for index in OPERATIONS'range loop
			operation <= OPERATIONS(index);
			run_case(REGISTER_TOTALS(index));
		end loop;

		family <= FPU_FAMILY_EXTERNAL_OPERATION;
		address_mode <= "010";
		for operation_index in OPERATIONS'range loop
			operation <= OPERATIONS(operation_index);
			for format_index in FORMATS'range loop
				operand_format <= FORMATS(format_index);
				run_case(EXTERNAL_TOTALS(operation_index, format_index));
			end loop;
		end loop;
		operation <= FPU_OP_ADD;
		address_mode <= "000";
		operand_format <= FPU_FORMAT_LONG_INTEGER;
		run_case(89);
		operand_format <= FPU_FORMAT_SINGLE;
		run_case(64);

		family <= FPU_FAMILY_MOVE_CONSTANT;
		address_mode <= "010";
		run_case(32);

		family <= FPU_FAMILY_MOVE_TO_EXTERNAL;
		for format_index in FORMATS'range loop
			operand_format <= FORMATS(format_index);
			case format_index is
				when 0 => run_case(110);
				when 1 => run_case(38);
				when 2 => run_case(44);
				when 3 => run_case(50);
				when others => run_case(2006);
			end case;
		end loop;
		operand_format <= FPU_FORMAT_DYNAMIC_PACKED;
		run_case(2020);
		address_mode <= "000";
		operand_format <= FPU_FORMAT_SINGLE;
		run_case(36);

		family <= FPU_FAMILY_MOVE_TO_CONTROL;
		control_register_mask <= "001";
		run_case(28);
		address_mode <= "010";
		run_case(33);
		address_mode <= "111";
		address_register <= "100";
		run_case(32);
		control_register_mask <= "111";
		run_case(44);
		address_mode <= "010";
		run_case(45);

		family <= FPU_FAMILY_MOVE_FROM_CONTROL;
		control_register_mask <= "001";
		address_mode <= "000";
		run_case(31);
		address_mode <= "010";
		run_case(33);
		control_register_mask <= "111";
		run_case(45);

		family <= FPU_FAMILY_MOVEM_TO_FP;
		data_register_mask <= x"01";
		dynamic_register_mask <= '0';
		run_case(66);
		data_register_mask <= x"FF";
		run_case(283);
		dynamic_register_mask <= '1';
		run_case(297);
		family <= FPU_FAMILY_MOVEM_FROM_FP;
		dynamic_register_mask <= '0';
		data_register_mask <= x"01";
		run_case(62);
		data_register_mask <= x"FF";
		run_case(237);
		dynamic_register_mask <= '1';
		run_case(251);

		family <= FPU_FAMILY_SCC;
		address_mode <= "000";
		run_case(16);
		address_mode <= "011";
		run_case(18);
		address_mode <= "100";
		run_case(18);
		address_mode <= "010";
		run_case(16);

		family <= FPU_FAMILY_DBCC;
		condition_true <= '1';
		run_case(18);
		condition_true <= '0';
		integer_register_data <= x"00000001";
		run_case(18, '1');
		integer_register_data <= x"00000000";
		run_case(22);

		family <= FPU_FAMILY_BCC_WORD;
		condition_true <= '0';
		run_case(16);
		condition_true <= '1';
		run_case(18, '1');
		family <= FPU_FAMILY_BCC_LONG;
		run_case(18, '1');

		family <= FPU_FAMILY_TRAPCC;
		address_register <= "100";
		condition_true <= '0';
		run_case(16);
		condition_true <= '1';
		run_case(36, '0', '1');
		address_register <= "010";
		condition_true <= '0';
		run_case(18);
		condition_true <= '1';
		run_case(38, '0', '1');
		address_register <= "011";
		condition_true <= '0';
		run_case(20);
		condition_true <= '1';
		run_case(40, '0', '1');

		family <= FPU_FAMILY_SAVE;
		initialized <= '0';
		suspended <= '0';
		run_case(14);
		initialized <= '1';
		run_case(98);
		suspended <= '1';
		run_case(332);

		family <= FPU_FAMILY_RESTORE;
		suspended <= '0';
		frame_byte_count <= FPU_STATE_FRAME_NULL_BYTES;
		run_case(19);
		frame_byte_count <= FPU_STATE_FRAME_IDLE_BYTES_68882;
		run_case(103);
		frame_byte_count <= FPU_STATE_FRAME_BUSY_BYTES_68882;
		run_case(337);

		family <= FPU_FAMILY_REGISTER_OPERATION;
		operation <= FPU_OP_ADD;
		frame_byte_count <= FPU_STATE_FRAME_NULL_BYTES;
		run_case(56, '0', '0', '1', '1');

		wait until falling_edge(clk);
		start <= '1';
		core_done <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		start <= '0';
		for cycle in 1 to 8 loop
			wait until rising_edge(clk);
		end loop;
		wait until falling_edge(clk);
		abort_operation <= '1';
		wait until rising_edge(clk);
		wait for 1 ns;
		abort_operation <= '0';
		core_done <= '0';
		assert busy = '0' and done = '0'
			report "timing abort did not cancel retirement" severity failure;

		report "PASS: MC68882 no-overlap timing profiles" severity note;
		stop;
		wait;
	end process;
end architecture;
