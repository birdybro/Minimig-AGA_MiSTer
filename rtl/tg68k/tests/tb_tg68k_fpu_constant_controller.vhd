library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_constant_controller is
end entity;

architecture test of tb_tg68k_fpu_constant_controller is
	constant CLK_PERIOD : time := 10 ns;
	type offset_array_t is array (natural range <>) of
		std_logic_vector(5 downto 0);
	type value_array_t is array (natural range <>) of fpu_extended_t;
	type inexact_array_t is array (natural range <>) of std_logic;

	constant DEFINED_OFFSETS : offset_array_t(0 to 21) := (
		std_logic_vector(to_unsigned(16#00#, 6)),
		std_logic_vector(to_unsigned(16#0B#, 6)),
		std_logic_vector(to_unsigned(16#0C#, 6)),
		std_logic_vector(to_unsigned(16#0D#, 6)),
		std_logic_vector(to_unsigned(16#0E#, 6)),
		std_logic_vector(to_unsigned(16#0F#, 6)),
		std_logic_vector(to_unsigned(16#30#, 6)),
		std_logic_vector(to_unsigned(16#31#, 6)),
		std_logic_vector(to_unsigned(16#32#, 6)),
		std_logic_vector(to_unsigned(16#33#, 6)),
		std_logic_vector(to_unsigned(16#34#, 6)),
		std_logic_vector(to_unsigned(16#35#, 6)),
		std_logic_vector(to_unsigned(16#36#, 6)),
		std_logic_vector(to_unsigned(16#37#, 6)),
		std_logic_vector(to_unsigned(16#38#, 6)),
		std_logic_vector(to_unsigned(16#39#, 6)),
		std_logic_vector(to_unsigned(16#3A#, 6)),
		std_logic_vector(to_unsigned(16#3B#, 6)),
		std_logic_vector(to_unsigned(16#3C#, 6)),
		std_logic_vector(to_unsigned(16#3D#, 6)),
		std_logic_vector(to_unsigned(16#3E#, 6)),
		std_logic_vector(to_unsigned(16#3F#, 6)));
	constant EXTENDED_NEAREST : value_array_t(0 to 21) := (
		x"4000C90FDAA22168C235", x"3FFD9A209A84FBCFF798",
		x"4000ADF85458A2BB4A9A", x"3FFFB8AA3B295C17F0BC",
		x"3FFDDE5BD8A937287195", x"00000000000000000000",
		x"3FFEB17217F7D1CF79AC", x"4000935D8DDDAAA8AC17",
		x"3FFF8000000000000000", x"4002A000000000000000",
		x"4005C800000000000000", x"400C9C40000000000000",
		x"4019BEBC200000000000", x"40348E1BC9BF04000000",
		x"40699DC5ADA82B70B59E", x"40D3C2781F49FFCFA6D5",
		x"41A893BA47C980E98CE0", x"4351AA7EEBFB9DF9DE8E",
		x"46A3E319A0AEA60E91C7", x"4D48C976758681750C17",
		x"5A929E8B3B5DC53D5DE5", x"7525C46052028A20979B");
	constant EXTENDED_INEXACT : inexact_array_t(0 to 21) := (
		'1', '1', '1', '1', '0', '0', '1', '1', '0', '0', '0',
		'0', '0', '0', '1', '1', '1', '1', '1', '1', '1', '1');

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal start : std_logic := '0';
	signal rom_offset : std_logic_vector(5 downto 0) := (others => '0');
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal fp_register_write : std_logic;
	signal fp_register_write_data : fpu_extended_t;
	signal operation_status_write : std_logic;
	signal condition_codes_write : std_logic;
	signal operation_condition_codes : std_logic_vector(3 downto 0);
	signal operation_exception_status : std_logic_vector(7 downto 0);
	signal busy : std_logic;
	signal done : std_logic;
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68K_FPU_Constant_Controller
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			rom_offset => rom_offset,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			fp_register_write => fp_register_write,
			fp_register_write_data => fp_register_write_data,
			operation_status_write => operation_status_write,
			condition_codes_write => condition_codes_write,
			operation_condition_codes => operation_condition_codes,
			operation_exception_status => operation_exception_status,
			busy => busy,
			done => done
		);

	stimulus : process
		procedure execute(
			constant offset_value : std_logic_vector(5 downto 0);
			constant precision_value : fpu_rounding_precision_t;
			constant mode_value : fpu_rounding_mode_t;
			constant expected_result : fpu_extended_t;
			constant expected_status : std_logic_vector(7 downto 0)) is
		begin
			wait until falling_edge(clk);
			rom_offset <= offset_value;
			rounding_precision <= precision_value;
			rounding_mode <= mode_value;
			start <= '1';
			wait until rising_edge(clk);
			wait for 1 ns;
			start <= '0';
			assert busy = '1' and fp_register_write = '1' and
				operation_status_write = '1' and condition_codes_write = '1'
				report "FMOVECR commit handshake mismatch" severity failure;
			assert fp_register_write_data = expected_result and
				operation_exception_status = expected_status and
				operation_condition_codes = fpu_condition_codes(expected_result)
				report "FMOVECR result mismatch for offset " &
					integer'image(to_integer(unsigned(offset_value))) & ": got " &
					to_hstring(fp_register_write_data)
				severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert done = '1' and fp_register_write = '0'
				report "FMOVECR completion handshake mismatch" severity failure;
			wait until rising_edge(clk);
			wait for 1 ns;
			assert busy = '0' and done = '0'
				report "FMOVECR controller did not return idle" severity failure;
		end procedure;
		variable expected_status : std_logic_vector(7 downto 0);
	begin
		wait for 3 * CLK_PERIOD;
		wait until rising_edge(clk);
		nReset <= '1';
		wait until rising_edge(clk);

		for index in DEFINED_OFFSETS'range loop
			expected_status := (others => '0');
			expected_status(1) := EXTENDED_INEXACT(index);
			execute(DEFINED_OFFSETS(index), FPU_PRECISION_EXTENDED,
				FPU_ROUND_NEAREST, EXTENDED_NEAREST(index), expected_status);
		end loop;

		execute(std_logic_vector(to_unsigned(16#00#, 6)),
			FPU_PRECISION_EXTENDED, FPU_ROUND_ZERO,
			x"4000C90FDAA22168C234", x"02");
		execute(std_logic_vector(to_unsigned(16#0B#, 6)),
			FPU_PRECISION_EXTENDED, FPU_ROUND_PLUS_INFINITY,
			x"3FFD9A209A84FBCFF799", x"02");
		execute(std_logic_vector(to_unsigned(16#00#, 6)),
			FPU_PRECISION_DOUBLE, FPU_ROUND_NEAREST,
			x"4000C90FDAA22168C000", x"02");
		execute(std_logic_vector(to_unsigned(16#00#, 6)),
			FPU_PRECISION_DOUBLE, FPU_ROUND_PLUS_INFINITY,
			x"4000C90FDAA22168C800", x"02");
		execute(std_logic_vector(to_unsigned(16#0C#, 6)),
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"4000ADF8540000000000", x"02");
		execute(std_logic_vector(to_unsigned(16#0C#, 6)),
			FPU_PRECISION_SINGLE, FPU_ROUND_PLUS_INFINITY,
			x"4000ADF8550000000000", x"02");
		execute(std_logic_vector(to_unsigned(16#32#, 6)),
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"3FFF8000000000000000", x"00");
		execute(std_logic_vector(to_unsigned(16#3F#, 6)),
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"7525C460520000000000", x"02");

		report "PASS: MC68882 FMOVECR constant ROM and rounding" severity note;
		stop;
	end process;
end architecture;
