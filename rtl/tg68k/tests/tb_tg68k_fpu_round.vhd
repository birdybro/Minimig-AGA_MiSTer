library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_round is
end entity;

architecture test of tb_tg68k_fpu_round is
	signal input_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal input_sign : std_logic := '0';
	signal input_exponent : signed(16 downto 0) := (others => '0');
	signal input_significand : unsigned(66 downto 0) := (others => '0');
	signal special_value : fpu_extended_t := FPU_RESET_NAN;
	signal rounding_precision : fpu_rounding_precision_t :=
		FPU_PRECISION_EXTENDED;
	signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal single_extended_range : std_logic := '0';
	signal result : fpu_extended_t;
	signal inexact : std_logic;
	signal overflow : std_logic;
	signal underflow : std_logic;
	signal signaling_nan : std_logic;
begin
	dut : entity work.TG68K_FPU_Round
		port map(
			input_class => input_class,
			input_sign => input_sign,
			input_exponent => input_exponent,
			input_significand => input_significand,
			special_value => special_value,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			single_extended_range => single_extended_range,
			result => result,
			inexact => inexact,
			overflow => overflow,
			underflow => underflow,
			signaling_nan => signaling_nan
		);

	stimulus : process
		procedure check_round(
			constant class_value : fpu_data_class_t;
			constant sign_value : std_logic;
			constant exponent_value : integer;
			constant significand_value : std_logic_vector(66 downto 0);
			constant special_data : fpu_extended_t;
			constant precision_value : fpu_rounding_precision_t;
			constant mode_value : fpu_rounding_mode_t;
			constant expected_result : fpu_extended_t;
			constant expected_inexact : std_logic;
			constant expected_overflow : std_logic;
			constant expected_underflow : std_logic;
			constant expected_snan : std_logic := '0';
			constant single_extended_range_value : std_logic := '0') is
		begin
			input_class <= class_value;
			input_sign <= sign_value;
			input_exponent <= to_signed(exponent_value, 17);
			input_significand <= unsigned(significand_value);
			special_value <= special_data;
			rounding_precision <= precision_value;
			rounding_mode <= mode_value;
			single_extended_range <= single_extended_range_value;
			wait for 1 ns;
			assert result = expected_result
				report "FPU rounded result mismatch" severity failure;
			assert inexact = expected_inexact and
				overflow = expected_overflow and
				underflow = expected_underflow and
				signaling_nan = expected_snan
				report "FPU rounding exception classification mismatch"
				severity failure;
		end procedure;
	begin
		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"3FFF8000000000000000", '0', '0', '0');
		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"8000000000000000" & "100", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"3FFF8000000000000000", '1', '0', '0');
		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"8000000000000001" & "100", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"3FFF8000000000000002", '1', '0', '0');

		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"8000008000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"3FFF8000000000000000", '1', '0', '0');
		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"8000018000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"3FFF8000020000000000", '1', '0', '0');
		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"8000000000000000" & "001", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_PLUS_INFINITY,
			x"3FFF8000010000000000", '1', '0', '0');
		check_round(FPU_CLASS_NORMAL, '1', 0,
			x"8000000000000000" & "001", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_MINUS_INFINITY,
			x"BFFF8000010000000000", '1', '0', '0');
		check_round(FPU_CLASS_NORMAL, '1', 0,
			x"8000000000000000" & "001", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_PLUS_INFINITY,
			x"BFFF8000000000000000", '1', '0', '0');
		check_round(FPU_CLASS_NORMAL, '0', 0,
			x"FFFFFF8000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"40008000000000000000", '1', '0', '0');

		check_round(FPU_CLASS_NORMAL, '0', -126,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"3F818000000000000000", '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -127,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"3F808000000000000000", '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -149,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"3F6A8000000000000000", '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -150,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"00000000000000000000", '1', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -150,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_PLUS_INFINITY,
			x"3F6A8000000000000000", '1', '0', '1');
		check_round(FPU_CLASS_NORMAL, '1', -150,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_MINUS_INFINITY,
			x"BF6A8000000000000000", '1', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -1074,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_DOUBLE, FPU_ROUND_NEAREST,
			x"3BCD8000000000000000", '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -16383,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"00008000000000000000", '0', '0', '0');
		check_round(FPU_CLASS_NORMAL, '0', -16384,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"00004000000000000000", '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -16447,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"00000000000000000000", '1', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -16447,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_EXTENDED, FPU_ROUND_PLUS_INFINITY,
			x"00000000000000000001", '1', '0', '1');

		check_round(FPU_CLASS_NORMAL, '0', 200,
			x"8000008000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"40C78000000000000000", '1', '0', '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -16383,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"00008000000000000000", '0', '0', '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -16384,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"00004000000000000000", '0', '0', '1', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', -16447,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_PLUS_INFINITY,
			x"00000000000000000001", '1', '0', '1', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', 16384,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_ZERO,
			x"7FFEFFFFFFFFFFFFFFFF", '1', '1', '0', '0', '1');
		check_round(FPU_CLASS_NORMAL, '0', 16384,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"7FFF8000000000000000", '1', '1', '0', '0', '1');

		check_round(FPU_CLASS_NORMAL, '0', 128,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"7FFF8000000000000000", '1', '1', '0');
		check_round(FPU_CLASS_NORMAL, '0', 128,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_ZERO,
			x"407EFFFFFF0000000000", '1', '1', '0');
		check_round(FPU_CLASS_NORMAL, '1', 128,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_MINUS_INFINITY,
			x"FFFF8000000000000000", '1', '1', '0');
		check_round(FPU_CLASS_NORMAL, '1', 128,
			x"8000000000000000" & "000", FPU_RESET_NAN,
			FPU_PRECISION_SINGLE, FPU_ROUND_PLUS_INFINITY,
			x"C07EFFFFFF0000000000", '1', '1', '0');

		check_round(FPU_CLASS_ZERO, '1', 0, (others => '0'),
			FPU_RESET_NAN, FPU_PRECISION_EXTENDED, FPU_ROUND_NEAREST,
			x"80000000000000000000", '0', '0', '0');
		check_round(FPU_CLASS_INFINITY, '1', 0, (others => '0'),
			FPU_RESET_NAN, FPU_PRECISION_SINGLE, FPU_ROUND_NEAREST,
			x"FFFF8000000000000000", '0', '0', '0');
		check_round(FPU_CLASS_QUIET_NAN, '1', 0, (others => '0'),
			x"FFFFC123456789ABCDEF", FPU_PRECISION_SINGLE,
			FPU_ROUND_NEAREST, x"FFFFC123456789ABCDEF", '0', '0', '0');
		check_round(FPU_CLASS_SIGNALING_NAN, '0', 0, (others => '0'),
			x"7FFF8000010000000000", FPU_PRECISION_EXTENDED,
			FPU_ROUND_NEAREST, x"7FFFC000010000000000", '0', '0', '0', '1');

		assert fpu_classify(x"00000000000000000000") = FPU_CLASS_ZERO and
			fpu_classify(x"80000000000000000000") = FPU_CLASS_ZERO and
			fpu_classify(x"7FFF0000000000000000") = FPU_CLASS_INFINITY and
			fpu_classify(x"FFFF8000000000000000") = FPU_CLASS_INFINITY and
			fpu_classify(x"7FFFC000000000000001") = FPU_CLASS_QUIET_NAN and
			fpu_classify(x"7FFF8000000000000001") = FPU_CLASS_SIGNALING_NAN and
			fpu_classify(x"3FFF8000000000000000") = FPU_CLASS_NORMAL
			report "FPU extended data classification mismatch" severity failure;

		report "PASS: MC68882 precision, rounding, and range handling"
			severity note;
		stop;
	end process;
end architecture;
