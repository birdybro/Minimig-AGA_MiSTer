library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_MMU_Pack.all;

entity tb_tg68k_mmu_fault_frame is
end entity;

architecture test of tb_tg68k_mmu_fault_frame is
	signal long_format : std_logic := '0';
	signal word_index : std_logic_vector(5 downto 0) := (others => '0');
	signal internal_word : std_logic_vector(15 downto 0) := x"5A5A";
	signal frame_word_count : std_logic_vector(5 downto 0);
	signal internal_word_select : std_logic;
	signal internal_word_index : std_logic_vector(4 downto 0);
	signal frame_word : std_logic_vector(15 downto 0);
begin
	dut : entity work.TG68K_MMU_Fault_Frame
		port map(
			long_format => long_format,
			word_index => word_index,
			status_register => x"2700",
			program_counter => x"12345678",
			special_status_word => x"0145",
			pipe_stage_c => x"CAFE",
			pipe_stage_b => x"BABE",
			fault_address => x"89ABCDEF",
			data_output_buffer => x"10203040",
			stage_b_address => x"55667788",
			data_input_buffer => x"A1B2C3D4",
			version => x"3",
			internal_word => internal_word,
			frame_word_count => frame_word_count,
			internal_word_select => internal_word_select,
			internal_word_index => internal_word_index,
			frame_word => frame_word
		);

	stimulus : process
		procedure check_word(
			constant index : natural;
			constant expected : std_logic_vector(15 downto 0);
			constant internal_select : std_logic := '0';
			constant internal_index : natural := 0) is
		begin
			word_index <= std_logic_vector(to_unsigned(index, word_index'length));
			wait for 1 ns;
			assert frame_word = expected and
				internal_word_select = internal_select
				report "fault frame word " & integer'image(index) & " mismatch"
				severity failure;
			if internal_select = '1' then
				assert to_integer(unsigned(internal_word_index)) = internal_index
					report "internal word index mismatch" severity failure;
			end if;
		end procedure;
		variable expected_ssw : std_logic_vector(15 downto 0);
	begin
		wait for 1 ns;
		assert frame_word_count = std_logic_vector(to_unsigned(16, 6))
			report "short frame length mismatch" severity failure;
		check_word(0, x"2700");
		check_word(1, x"1234");
		check_word(2, x"5678");
		check_word(3, x"A008");
		check_word(4, x"5A5A", '1', 0);
		check_word(5, x"0145");
		check_word(6, x"CAFE");
		check_word(7, x"BABE");
		check_word(8, x"89AB");
		check_word(9, x"CDEF");
		check_word(10, x"5A5A", '1', 1);
		check_word(11, x"5A5A", '1', 2);
		check_word(12, x"1020");
		check_word(13, x"3040");
		check_word(14, x"5A5A", '1', 3);
		check_word(15, x"5A5A", '1', 4);

		long_format <= '1';
		wait for 1 ns;
		assert frame_word_count = std_logic_vector(to_unsigned(46, 6))
			report "long frame length mismatch" severity failure;
		check_word(3, x"B008");
		check_word(16, x"5A5A", '1', 5);
		check_word(17, x"5A5A", '1', 6);
		check_word(18, x"5566");
		check_word(19, x"7788");
		check_word(20, x"5A5A", '1', 7);
		check_word(21, x"5A5A", '1', 8);
		check_word(22, x"A1B2");
		check_word(23, x"C3D4");
		check_word(24, x"5A5A", '1', 9);
		check_word(25, x"5A5A", '1', 10);
		check_word(26, x"5A5A", '1', 11);
		check_word(27, x"3A5A", '1', 12);
		for index in 28 to 45 loop
			check_word(index, x"5A5A", '1', index - 15);
		end loop;

		for fc in 0 to 7 loop
			for size in 0 to 3 loop
				for write_access in 0 to 1 loop
					for rmw in 0 to 1 loop
						expected_ssw := (others => '0');
						expected_ssw(8) := '1';
						expected_ssw(7) := std_logic'val(rmw + 2);
						expected_ssw(6) := not std_logic'val(write_access + 2);
						expected_ssw(5 downto 4) := std_logic_vector(to_unsigned(size, 2));
						expected_ssw(2 downto 0) := std_logic_vector(to_unsigned(fc, 3));
						assert mmu_data_fault_ssw(
							std_logic_vector(to_unsigned(fc, 3)),
							std_logic'val(write_access + 2),
							std_logic'val(rmw + 2),
							std_logic_vector(to_unsigned(size, 2))) = expected_ssw
							report "data SSW construction mismatch" severity failure;
					end loop;
				end loop;
			end loop;
		end loop;
		assert mmu_instruction_fault_ssw('1', '0') = x"5000" and
			mmu_instruction_fault_ssw('0', '1') = x"A000" and
			mmu_instruction_fault_ssw('1', '1') = x"F000"
			report "instruction SSW construction mismatch" severity failure;

		report "PASS: MC68030 MMU format-A/B fault frame formatter" severity note;
		stop;
		wait;
	end process;
end architecture;
