------------------------------------------------------------------------------
--                                                                          --
-- Copyright (c) 2026 TG68K contributors                                    --
--                                                                          --
-- This source file is free software: you can redistribute it and/or modify --
-- it under the terms of the GNU Lesser General Public License as published --
-- by the Free Software Foundation, either version 3 of the License, or     --
-- (at your option) any later version.                                      --
--                                                                          --
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Arc_Tangent is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		arc_sine : in std_logic := '0';
		arc_cosine : in std_logic := '0';
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Arc_Tangent is
	constant FRACTION_BITS : natural := 112;
	constant CORDIC_WIDTH : natural := FRACTION_BITS + 4;
	constant TINY_EXPONENT : integer := -34;
	constant ARC_SINE_TINY_EXPONENT : integer := -33;
	type arc_tangent_state_t is (IDLE, MULTIPLY_ARC_SINE_SOURCE,
		SQUARE_ROOT_ARC_SINE_COMPLEMENT, LOAD_CORDIC_ANGLE,
		ROTATE_CORDIC_XY, ROTATE_CORDIC_Z, FINISH_CORDIC,
		NORMALIZE_RESULT, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 63) of cordic_value_t;

	constant PI_BY_TWO_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		unsigned'(x"1921FB54442D18469898CC51701B8");
	constant PI_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		shift_left(PI_BY_TWO_FIXED, 1);
	signal cordic_angle_rom : cordic_angle_rom_t := (
		0 => signed'(x"0C90FDAA22168C234C4C6628B80DC"),
		1 => signed'(x"076B19C1586ED3DA2B7F222F65E1D"),
		2 => signed'(x"03EB6EBF25901BAC55B71E7BD7DE9"),
		3 => signed'(x"01FD5BA9AAC2F6DC65912F313E7D1"),
		4 => signed'(x"00FFAADDB967EF4E36CB2792DC0E3"),
		5 => signed'(x"007FF556EEA5D892A13BCEBBB6ED4"),
		6 => signed'(x"003FFEAAB776E5356EF9E31590058"),
		7 => signed'(x"001FFFD555BBBA972D00C46A3F77D"),
		8 => signed'(x"000FFFFAAAADDDDB94BB12AFB6B6D"),
		9 => signed'(x"0007FFFF55556EEEEA5CA6ADEAB02"),
		10 => signed'(x"0003FFFFEAAAAB77776E52E5A01A0"),
		11 => signed'(x"0001FFFFFD55555BBBBBA97297625"),
		12 => signed'(x"0000FFFFFFAAAAAADDDDDDB94B94D"),
		13 => signed'(x"00007FFFFFF5555556EEEEEEA5CA6"),
		14 => signed'(x"00003FFFFFFEAAAAAAB7777776E53"),
		15 => signed'(x"00001FFFFFFFD5555555BBBBBBBA9"),
		16 => signed'(x"00000FFFFFFFFAAAAAAAADDDDDDDE"),
		17 => signed'(x"000007FFFFFFFF555555556EEEEEF"),
		18 => signed'(x"000003FFFFFFFFEAAAAAAAAB77777"),
		19 => signed'(x"000001FFFFFFFFFD555555555BBBC"),
		20 => signed'(x"000000FFFFFFFFFFAAAAAAAAAADDE"),
		21 => signed'(x"0000007FFFFFFFFFF55555555556F"),
		22 => signed'(x"0000003FFFFFFFFFFEAAAAAAAAAAB"),
		23 => signed'(x"0000001FFFFFFFFFFFD5555555555"),
		24 => signed'(x"0000000FFFFFFFFFFFFAAAAAAAAAB"),
		25 => signed'(x"00000007FFFFFFFFFFFF555555555"),
		26 => signed'(x"00000003FFFFFFFFFFFFEAAAAAAAB"),
		27 => signed'(x"00000001FFFFFFFFFFFFFD5555555"),
		28 => signed'(x"00000000FFFFFFFFFFFFFFAAAAAAB"),
		29 => signed'(x"000000007FFFFFFFFFFFFFF555555"),
		30 => signed'(x"000000003FFFFFFFFFFFFFFEAAAAB"),
		31 => signed'(x"000000001FFFFFFFFFFFFFFFD5555"),
		32 => signed'(x"000000000FFFFFFFFFFFFFFFFAAAB"),
		33 => signed'(x"0000000007FFFFFFFFFFFFFFFF555"),
		34 => signed'(x"0000000003FFFFFFFFFFFFFFFFEAB"),
		35 => signed'(x"0000000001FFFFFFFFFFFFFFFFFD5"),
		36 => signed'(x"0000000000FFFFFFFFFFFFFFFFFFB"),
		37 => signed'(x"00000000007FFFFFFFFFFFFFFFFFF"),
		38 => signed'(x"00000000004000000000000000000"),
		39 => signed'(x"00000000002000000000000000000"),
		40 => signed'(x"00000000001000000000000000000"),
		41 => signed'(x"00000000000800000000000000000"),
		42 => signed'(x"00000000000400000000000000000"),
		43 => signed'(x"00000000000200000000000000000"),
		44 => signed'(x"00000000000100000000000000000"),
		45 => signed'(x"00000000000080000000000000000"),
		46 => signed'(x"00000000000040000000000000000"),
		47 => signed'(x"00000000000020000000000000000"),
		48 to 63 => (others => '0')
	);
	attribute ramstyle : string;
	attribute ramstyle of cordic_angle_rom : signal is "M10K";

	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	function or_reduce(value : unsigned) return std_logic is
		variable reduced : std_logic := '0';
	begin
		for index in value'range loop
			reduced := reduced or value(index);
		end loop;
		return reduced;
	end function;

	signal state : arc_tangent_state_t := IDLE;
	signal result_sign : std_logic := '0';
	signal arc_cosine_mode : std_logic := '0';
	signal cordic_x : cordic_value_t := (others => '0');
	signal cordic_y : cordic_value_t := (others => '0');
	signal cordic_z : cordic_value_t := (others => '0');
	signal cordic_iteration : natural range 0 to FRACTION_BITS := 0;
	signal cordic_angle_address : natural range 0 to 47 := 0;
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal cordic_z_previous : cordic_value_t := (others => '0');
	signal cordic_angle_previous : cordic_value_t := (others => '0');
	signal cordic_direction_previous : std_logic := '0';
	signal normalization_value : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalization_exponent : signed(16 downto 0) := (others => '0');
	signal arc_sine_magnitude : unsigned(FRACTION_BITS downto 0) :=
		(others => '0');
	-- The combined accumulator|multiplier shifts right around a stationary
	-- multiplicand, avoiding two full-width square-multiplier shifters.
	signal square_multiplicand : unsigned(FRACTION_BITS downto 0) :=
		(others => '0');
	signal square_product : unsigned(2 * FRACTION_BITS + 2 downto 0) :=
		(others => '0');
	signal square_iteration : natural range 0 to FRACTION_BITS := 0;
	signal root_radicand : unsigned(2 * FRACTION_BITS + 1 downto 0) :=
		(others => '0');
	signal root_remainder : unsigned(FRACTION_BITS + 2 downto 0) :=
		(others => '0');
	signal root_value : unsigned(FRACTION_BITS downto 0) := (others => '0');
	signal root_iteration : natural range 0 to FRACTION_BITS := 0;
	signal arithmetic_left_a : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal arithmetic_right_a : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal arithmetic_left_b : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal arithmetic_right_b : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal arithmetic_subtract_a : std_logic;
	signal arithmetic_subtract_b : std_logic;
	signal arithmetic_result_a : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal arithmetic_result_b : unsigned(CORDIC_WIDTH - 1 downto 0);

	signal intermediate_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal intermediate_sign : std_logic := '0';
	signal intermediate_exponent : signed(16 downto 0) := (others => '0');
	signal intermediate_significand : fpu_significand_grs_t := (others => '0');
	signal intermediate_special : fpu_extended_t := (others => '0');
	signal base_status : std_logic_vector(7 downto 0) := (others => '0');
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
begin
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	base_exception_status <= base_status;

	arithmetic_operands : process(state, cordic_x, cordic_y,
		cordic_iteration, cordic_z_previous, cordic_angle_previous,
		cordic_direction_previous)
	begin
		arithmetic_left_a <= (others => '0');
		arithmetic_right_a <= (others => '0');
		arithmetic_left_b <= (others => '0');
		arithmetic_right_b <= (others => '0');
		arithmetic_subtract_a <= '0';
		arithmetic_subtract_b <= '0';
		case state is
			when ROTATE_CORDIC_XY =>
				arithmetic_left_a <= unsigned(cordic_x);
				arithmetic_left_b <= unsigned(cordic_y);
				if cordic_y > 0 then
					arithmetic_right_a <= unsigned(shift_right(cordic_y,
						cordic_iteration));
					arithmetic_right_b <= unsigned(shift_right(cordic_x,
						cordic_iteration));
					arithmetic_subtract_b <= '1';
				elsif cordic_y < 0 then
					arithmetic_right_a <= unsigned(shift_right(cordic_y,
						cordic_iteration));
					arithmetic_right_b <= unsigned(shift_right(cordic_x,
						cordic_iteration));
					arithmetic_subtract_a <= '1';
				end if;
			when ROTATE_CORDIC_Z =>
				arithmetic_left_a <= unsigned(cordic_z_previous);
				arithmetic_right_a <= unsigned(cordic_angle_previous);
				arithmetic_subtract_a <= not cordic_direction_previous;
			when others => null;
		end case;
	end process;

	arithmetic_add_subtract : process(arithmetic_subtract_a,
		arithmetic_left_a, arithmetic_right_a, arithmetic_subtract_b,
		arithmetic_left_b, arithmetic_right_b)
	begin
		if arithmetic_subtract_a = '1' then
			arithmetic_result_a <= arithmetic_left_a - arithmetic_right_a;
		else
			arithmetic_result_a <= arithmetic_left_a + arithmetic_right_a;
		end if;
		if arithmetic_subtract_b = '1' then
			arithmetic_result_b <= arithmetic_left_b - arithmetic_right_b;
		else
			arithmetic_result_b <= arithmetic_left_b + arithmetic_right_b;
		end if;
	end process;

	angle_rom_read : process(clk)
	begin
		if rising_edge(clk) then
			cordic_angle_rom_data <= cordic_angle_rom(cordic_angle_address);
		end if;
	end process;

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		round_result : entity work.TG68K_FPU_Round
			port map(
				input_class => intermediate_class,
				input_sign => intermediate_sign,
				input_exponent => intermediate_exponent,
				input_significand => intermediate_significand,
				special_value => intermediate_special,
				rounding_precision => rounding_precision,
				rounding_mode => rounding_mode,
				single_extended_range => '0',
				result => rounded_result,
				inexact => rounded_inexact,
				overflow => rounded_overflow,
				underflow => rounded_underflow,
				signaling_nan => open
			);
	end generate;

	without_rounding : if not INCLUDE_ROUNDING_STAGE generate
		rounded_result <= (others => '0');
		rounded_inexact <= '0';
		rounded_overflow <= '0';
		rounded_underflow <= '0';
	end generate;

	outputs : process(rounded_result, base_status, rounded_inexact,
			rounded_overflow, rounded_underflow)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := base_status;
		status(4) := rounded_overflow;
		status(3) := rounded_underflow;
		status(1) := base_status(1) or rounded_inexact;
		result <= rounded_result;
		condition_codes <= fpu_condition_codes(rounded_result);
		exception_status <= status;
	end process;

	arc_tangent_sequence : process(clk)
		procedure begin_fixed_angle(
				constant angle : in unsigned(CORDIC_WIDTH - 1 downto 0);
				constant sign_value : in std_logic) is
		begin
			result_sign <= sign_value;
			if angle(FRACTION_BITS + 1) = '1' then
				normalization_value <= shift_right(angle, 1);
				normalization_exponent <= to_signed(1, 17);
			else
				normalization_value <= angle;
				normalization_exponent <= to_signed(0, 17);
			end if;
			state <= NORMALIZE_RESULT;
		end procedure;

		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable unit_value : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable mantissa_value : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable arc_sine_fixed : unsigned(FRACTION_BITS downto 0);
		variable selected_nan : fpu_extended_t;
		variable tiny_significand : fpu_significand_grs_t;
		variable square_accumulator_sum : unsigned(FRACTION_BITS + 1 downto 0);
		variable next_square_product : unsigned(2 * FRACTION_BITS + 2 downto 0);
		variable unit_square : unsigned(2 * FRACTION_BITS + 1 downto 0);
		variable shifted_remainder : unsigned(FRACTION_BITS + 2 downto 0);
		variable trial_divisor : unsigned(FRACTION_BITS + 2 downto 0);
		variable next_remainder : unsigned(FRACTION_BITS + 2 downto 0);
		variable next_root : unsigned(FRACTION_BITS downto 0);
		variable next_angle : cordic_value_t;
		variable final_significand : fpu_significand_grs_t;
		variable next_normalization : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable next_exponent : signed(16 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				result_sign <= '0';
				arc_cosine_mode <= '0';
				cordic_x <= (others => '0');
				cordic_y <= (others => '0');
				cordic_z <= (others => '0');
				cordic_iteration <= 0;
				cordic_angle_address <= 0;
				cordic_shift_angle <= (others => '0');
				cordic_z_previous <= (others => '0');
				cordic_angle_previous <= (others => '0');
				cordic_direction_previous <= '0';
				normalization_value <= (others => '0');
				normalization_exponent <= (others => '0');
				arc_sine_magnitude <= (others => '0');
				square_multiplicand <= (others => '0');
				square_product <= (others => '0');
				square_iteration <= 0;
				root_radicand <= (others => '0');
				root_remainder <= (others => '0');
				root_value <= (others => '0');
				root_iteration <= 0;
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				intermediate_exponent <= (others => '0');
				intermediate_significand <= (others => '0');
				intermediate_special <= (others => '0');
				base_status <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							source_class := fpu_classify(source);
							source_significand := unsigned(source(63 downto 0));
							source_exponent := fpu_unbiased_exponent(source);
							selected_nan := source;
							selected_nan(62) := '1';
							result_sign <= source(79);
							arc_cosine_mode <= arc_cosine;
							cordic_x <= (others => '0');
							cordic_y <= (others => '0');
							cordic_z <= (others => '0');
							cordic_iteration <= 0;
							cordic_angle_address <= 0;
							cordic_shift_angle <= (others => '0');
							cordic_z_previous <= (others => '0');
							cordic_angle_previous <= (others => '0');
							cordic_direction_previous <= '0';
							normalization_value <= (others => '0');
							normalization_exponent <= (others => '0');
							arc_sine_magnitude <= (others => '0');
							square_multiplicand <= (others => '0');
							square_product <= (others => '0');
							square_iteration <= 0;
							root_radicand <= (others => '0');
							root_remainder <= (others => '0');
							root_value <= (others => '0');
							root_iteration <= 0;
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= source(79);
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							base_status <= (others => '0');

							if source_class = FPU_CLASS_QUIET_NAN or
									source_class = FPU_CLASS_SIGNALING_NAN then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_special <= selected_nan;
								if source_class = FPU_CLASS_SIGNALING_NAN then
									base_status(6) <= '1';
								end if;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								if arc_sine = '1' or arc_cosine = '1' then
									intermediate_class <= FPU_CLASS_QUIET_NAN;
									intermediate_special <= FPU_RESET_NAN;
									base_status(5) <= '1';
									state <= COMPLETE;
								else
									base_status(1) <= '1';
									begin_fixed_angle(PI_BY_TWO_FIXED, source(79));
								end if;
							elsif source_class = FPU_CLASS_ZERO or
									source_significand = 0 then
								if arc_cosine = '1' then
									base_status(1) <= '1';
									begin_fixed_angle(PI_BY_TWO_FIXED, '0');
								else
									intermediate_class <= FPU_CLASS_ZERO;
									state <= COMPLETE;
								end if;
							else
								normalization_shift :=
									63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									normalization_shift);
								source_exponent := source_exponent - normalization_shift;
								if arc_sine = '1' or arc_cosine = '1' then
									if source_exponent > 0 or
											(source_exponent = 0 and
											source_significand > x"8000000000000000") then
										intermediate_class <= FPU_CLASS_QUIET_NAN;
										intermediate_special <= FPU_RESET_NAN;
										base_status(5) <= '1';
										state <= COMPLETE;
									elsif source_exponent = 0 then
										if arc_cosine = '1' and source(79) = '0' then
											intermediate_class <= FPU_CLASS_ZERO;
											intermediate_sign <= '0';
											state <= COMPLETE;
										elsif arc_cosine = '1' then
											base_status(1) <= '1';
											begin_fixed_angle(PI_FIXED, '0');
										else
											base_status(1) <= '1';
											begin_fixed_angle(PI_BY_TWO_FIXED, source(79));
										end if;
									elsif arc_cosine = '0' and
											source_exponent <= ARC_SINE_TINY_EXPONENT then
										base_status(1) <= '1';
										tiny_significand := shift_left(resize(
											source_significand, 67), 3) + 1;
										intermediate_class <= FPU_CLASS_NORMAL;
										intermediate_sign <= source(79);
										intermediate_exponent <= to_signed(
											source_exponent, 17);
										intermediate_significand <= tiny_significand;
										state <= COMPLETE;
									else
										base_status(1) <= '1';
										arc_sine_fixed := shift_left(resize(
											source_significand, FRACTION_BITS + 1),
											FRACTION_BITS - 63);
										arc_sine_fixed := shift_right(arc_sine_fixed,
											-source_exponent);
										arc_sine_magnitude <= arc_sine_fixed;
										square_multiplicand <= arc_sine_fixed;
										square_product <= resize(arc_sine_fixed,
											2 * FRACTION_BITS + 3);
										square_iteration <= 0;
										state <= MULTIPLY_ARC_SINE_SOURCE;
									end if;
								else
									base_status(1) <= '1';
									if source_exponent <= TINY_EXPONENT then
										if source_significand = x"8000000000000000" then
											tiny_significand := (others => '1');
											source_exponent := source_exponent - 1;
										else
											tiny_significand := shift_left(resize(
												source_significand, 67), 3) - 1;
										end if;
										intermediate_class <= FPU_CLASS_NORMAL;
										intermediate_sign <= source(79);
										intermediate_exponent <= to_signed(
											source_exponent, 17);
										intermediate_significand <= tiny_significand;
										state <= COMPLETE;
									else
										unit_value := (others => '0');
										unit_value(FRACTION_BITS) := '1';
										mantissa_value := shift_left(resize(
											source_significand, CORDIC_WIDTH),
											FRACTION_BITS - 63);
										if source_exponent >= 0 then
											cordic_y <= signed(mantissa_value);
											if source_exponent <= FRACTION_BITS then
												cordic_x <= signed(shift_right(unit_value,
													source_exponent));
											else
												cordic_x <= (others => '0');
											end if;
										else
											cordic_x <= signed(unit_value);
											cordic_y <= signed(shift_right(mantissa_value,
												-source_exponent));
										end if;
										cordic_z <= (others => '0');
										cordic_iteration <= 0;
										cordic_angle_address <= 0;
										state <= LOAD_CORDIC_ANGLE;
									end if;
								end if;
							end if;
						end if;

					when MULTIPLY_ARC_SINE_SOURCE =>
						-- asin(x) = atan2(x, sqrt(1-x*x)); keep both CORDIC
						-- operands in Q112 until the single architectural rounding.
						square_accumulator_sum := square_product(
							2 * FRACTION_BITS + 2 downto FRACTION_BITS + 1);
						if square_product(0) = '1' then
							square_accumulator_sum := square_accumulator_sum +
								resize(square_multiplicand, FRACTION_BITS + 2);
						end if;
						next_square_product := shift_right(square_accumulator_sum &
							square_product(FRACTION_BITS downto 0), 1);
						square_product <= next_square_product;
						if square_iteration = FRACTION_BITS then
							unit_square := (others => '0');
							unit_square(2 * FRACTION_BITS) := '1';
							root_radicand <= unit_square -
								next_square_product(2 * FRACTION_BITS + 1 downto 0);
							root_remainder <= (others => '0');
							root_value <= (others => '0');
							root_iteration <= 0;
							state <= SQUARE_ROOT_ARC_SINE_COMPLEMENT;
						else
							square_iteration <= square_iteration + 1;
						end if;

					when SQUARE_ROOT_ARC_SINE_COMPLEMENT =>
						shifted_remainder := shift_left(root_remainder, 2);
						shifted_remainder(1 downto 0) := root_radicand(
							2 * FRACTION_BITS + 1 downto 2 * FRACTION_BITS);
						trial_divisor := shift_left(resize(root_value,
							FRACTION_BITS + 3), 2);
						trial_divisor(0) := '1';
						next_root := shift_left(root_value, 1);
						if shifted_remainder >= trial_divisor then
							next_remainder := shifted_remainder - trial_divisor;
							next_root(0) := '1';
						else
							next_remainder := shifted_remainder;
							next_root(0) := '0';
						end if;
						root_radicand <= shift_left(root_radicand, 2);
						root_remainder <= next_remainder;
						root_value <= next_root;
						if root_iteration = FRACTION_BITS then
							cordic_x <= signed(resize(next_root, CORDIC_WIDTH));
							cordic_y <= signed(resize(arc_sine_magnitude,
								CORDIC_WIDTH));
							cordic_z <= (others => '0');
							cordic_iteration <= 0;
							cordic_angle_address <= 0;
							state <= LOAD_CORDIC_ANGLE;
						else
							root_iteration <= root_iteration + 1;
						end if;

					when LOAD_CORDIC_ANGLE =>
						state <= ROTATE_CORDIC_XY;

					when ROTATE_CORDIC_XY =>
						if cordic_iteration <= 47 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						cordic_z_previous <= cordic_z;
						if cordic_y > 0 then
							cordic_angle_previous <= next_angle;
							cordic_direction_previous <= '1';
						elsif cordic_y < 0 then
							cordic_angle_previous <= next_angle;
							cordic_direction_previous <= '0';
						else
							cordic_angle_previous <= (others => '0');
							cordic_direction_previous <= '1';
						end if;
						cordic_x <= signed(arithmetic_result_a);
						cordic_y <= signed(arithmetic_result_b);
						if cordic_iteration < 47 then
							cordic_angle_address <= cordic_iteration + 1;
						elsif cordic_iteration = 47 then
							next_angle := (others => '0');
							next_angle(FRACTION_BITS - 48) := '1';
							cordic_shift_angle <= next_angle;
						elsif cordic_iteration < FRACTION_BITS then
							cordic_shift_angle <= shift_right(
								cordic_shift_angle, 1);
						end if;
						state <= ROTATE_CORDIC_Z;

					when ROTATE_CORDIC_Z =>
						cordic_z <= signed(arithmetic_result_a);
						if cordic_iteration = FRACTION_BITS then
							state <= FINISH_CORDIC;
						else
							cordic_iteration <= cordic_iteration + 1;
							state <= ROTATE_CORDIC_XY;
						end if;

					when FINISH_CORDIC =>
						if arc_cosine_mode = '1' then
							if result_sign = '1' then
								begin_fixed_angle(PI_BY_TWO_FIXED +
									unsigned(cordic_z), '0');
							else
								begin_fixed_angle(PI_BY_TWO_FIXED -
									unsigned(cordic_z), '0');
							end if;
						else
							begin_fixed_angle(unsigned(cordic_z), result_sign);
						end if;

					when NORMALIZE_RESULT =>
						if normalization_value(FRACTION_BITS) = '1' then
							final_significand := (others => '0');
							final_significand(66 downto 3) := normalization_value(
								FRACTION_BITS downto FRACTION_BITS - 63);
							final_significand(2) := normalization_value(
								FRACTION_BITS - 64);
							final_significand(1) := normalization_value(
								FRACTION_BITS - 65);
							final_significand(0) := or_reduce(normalization_value(
								FRACTION_BITS - 66 downto 0));
							intermediate_class <= FPU_CLASS_NORMAL;
							intermediate_sign <= result_sign;
							intermediate_exponent <= normalization_exponent;
							intermediate_significand <= final_significand;
							state <= COMPLETE;
						else
							next_normalization := shift_left(normalization_value, 1);
							next_exponent := normalization_exponent - 1;
							normalization_value <= next_normalization;
							normalization_exponent <= next_exponent;
						end if;

					when COMPLETE =>
						if start = '0' then
							state <= IDLE;
						end if;
				end case;
			end if;
		end if;
	end process;
end architecture;
