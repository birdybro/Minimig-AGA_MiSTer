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

entity TG68K_FPU_Logarithm is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		add_one : in std_logic;
		logarithm_base : in fpu_logarithm_base_t;
		inverse_hyperbolic_tangent : in std_logic := '0';
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

architecture rtl of TG68K_FPU_Logarithm is
	constant FRACTION_BITS : natural := 96;
	constant CORDIC_WIDTH : natural := FRACTION_BITS + 4;
	constant RESULT_WIDTH : natural := FRACTION_BITS + 17;
	constant ARITHMETIC_WIDTH : natural := 128;
	constant RESULT_NORMAL_BIT : natural := RESULT_WIDTH - 2;
	constant SERIES_WIDTH : natural := 85;
	constant SERIES_NORMAL_BIT : natural := 83;
	constant SERIES_CUBIC_MAX_EXPONENT : integer := -26;
	constant SERIES_CUBIC_MIN_EXPONENT : integer := -40;
	constant ATANH_TINY_MAX_EXPONENT : integer := -33;
	constant CUBE_SQUARE_LOW_BIT : natural := 112;
	constant POSITIVE_REMAINDER_BOUND_BIT : natural := 9;
	type logarithm_state_t is
		(IDLE, NORMALIZE_SERIES_ARGUMENT, SQUARE_SMALL_ARGUMENT,
			ALIGN_SQUARE_TERM,
			CUBE_SMALL_ARGUMENT, DIVIDE_CUBE_TERM, ALIGN_CUBE_TERM,
			NORMALIZE_ATANH_RATIO, DIVIDE_ATANH_RATIO,
			NORMALIZE_INPUT, START_CORDIC, LOAD_CORDIC_ANGLE, ROTATE_CORDIC_XY,
			ROTATE_CORDIC_Z,
			FINISH_CORDIC, MULTIPLY_LN2, SCALE_LOGARITHM_BASE,
			LOAD_FIXED_RESULT, NORMALIZE_RESULT, FORMAT_SMALL_SERIES_RESULT,
			COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 31) of cordic_value_t;

	constant LN2_FIXED : unsigned(FRACTION_BITS - 1 downto 0) :=
		x"B17217F7D1CF79ABC9E3B398";
	constant LOG2_E_FIXED : unsigned(RESULT_WIDTH - 1 downto 0) :=
		unsigned'("1" & x"71547652B82FE1777D0FFDA0D23A");
	constant LOG10_E_FIXED : unsigned(RESULT_WIDTH - 1 downto 0) :=
		unsigned'("0" & x"6F2DEC549B9438CA9AADD557D69A");
	signal cordic_angle_rom : cordic_angle_rom_t := (
		0 => (others => '0'),
		1 => signed'(x"08C9F53D5681854BB520CC6AB"),
		2 => signed'(x"04162BBEA0451469C9DAF0BE1"),
		3 => signed'(x"0202B12393D5DEED328CF41ED"),
		4 => signed'(x"01005588AD375ACDCB1312A56"),
		5 => signed'(x"00800AAC448D77125A4EE9FEE"),
		6 => signed'(x"004001556222B47263834E959"),
		7 => signed'(x"0020002AAB111235A6E87A2A0"),
		8 => signed'(x"001000055558888AD1AEE1EF9"),
		9 => signed'(x"00080000AAAAC44448D68E4C6"),
		10 => signed'(x"0004000015555622222B46B4E"),
		11 => signed'(x"0002000002AAAAB11111235A3"),
		12 => signed'(x"0001000000555555888888AD2"),
		13 => signed'(x"00008000000AAAAAAC4444449"),
		14 => signed'(x"0000400000015555556222222"),
		15 => signed'(x"0000200000002AAAAAAB11111"),
		16 => signed'(x"0000100000000555555558889"),
		17 => signed'(x"00000800000000AAAAAAAAC44"),
		18 => signed'(x"0000040000000015555555562"),
		19 => signed'(x"0000020000000002AAAAAAAAB"),
		20 => signed'(x"0000010000000000555555555"),
		21 => signed'(x"00000080000000000AAAAAAAB"),
		22 => signed'(x"0000004000000000015555555"),
		23 => signed'(x"0000002000000000002AAAAAB"),
		24 => signed'(x"0000001000000000000555555"),
		25 => signed'(x"00000008000000000000AAAAB"),
		26 => signed'(x"0000000400000000000015555"),
		27 => signed'(x"0000000200000000000002AAB"),
		28 => signed'(x"0000000100000000000000555"),
		29 => signed'(x"00000000800000000000000AB"),
		30 => signed'(x"0000000040000000000000015"),
		31 => signed'(x"0000000020000000000000003")
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

	signal state : logarithm_state_t := IDLE;
	signal logarithm_base_latched : fpu_logarithm_base_t := FPU_LOG_BASE_E;
	signal inverse_hyperbolic_tangent_latched : std_logic := '0';
	signal source_sign_latched : std_logic := '0';
	signal series_source_significand : unsigned(63 downto 0) :=
		(others => '0');
	signal series_exponent : signed(16 downto 0) := (others => '0');
	signal series_multiplier : unsigned(63 downto 0) := (others => '0');
	signal series_multiplicand : unsigned(127 downto 0) := (others => '0');
	signal series_product : unsigned(127 downto 0) := (others => '0');
	signal square_high_register : unsigned(15 downto 0) := (others => '0');
	signal series_correction_register : unsigned(SERIES_WIDTH - 1 downto 0) :=
		(others => '0');
	signal correction_shift_count : natural range 0 to 111 := 0;
	signal series_index : natural range 0 to 79 := 0;
	signal cube_accumulator : unsigned(79 downto 0) := (others => '0');
	signal cube_remainder : natural range 0 to 2 := 0;
	signal cube_shift_count : natural range 0 to 74 := 0;

	signal input_mantissa : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal input_exponent : signed(16 downto 0) := (others => '0');
	signal cordic_x : cordic_value_t := (others => '0');
	signal cordic_y : cordic_value_t := (others => '0');
	signal cordic_z : signed(RESULT_WIDTH - 1 downto 0) := (others => '0');
	signal cordic_iteration : natural range 1 to FRACTION_BITS := 1;
	signal repeat_iteration : std_logic := '0';
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal cordic_angle_address : natural range 1 to 31 := 1;
	signal cordic_z_previous : signed(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal cordic_angle_previous : cordic_value_t := (others => '0');
	signal cordic_direction_previous : std_logic := '0';
	signal atanh_numerator : unsigned(CORDIC_WIDTH downto 0) :=
		(others => '0');
	signal atanh_denominator : unsigned(CORDIC_WIDTH downto 0) :=
		(others => '0');
	signal atanh_quotient : unsigned(FRACTION_BITS downto 0) :=
		(others => '0');
	signal atanh_exponent : signed(16 downto 0) := (others => '0');
	signal atanh_iteration : natural range 0 to FRACTION_BITS - 1 := 0;

	signal log_fraction : signed(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal ln2_multiplier : unsigned(14 downto 0) := (others => '0');
	signal ln2_multiplicand : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal ln2_accumulator : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal ln2_index : natural range 0 to 14 := 0;
	signal base_scale_multiplier : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal base_scale_accumulator : unsigned(RESULT_WIDTH downto 0) :=
		(others => '0');
	signal base_scale_index : natural range 0 to RESULT_WIDTH - 1 := 0;
	signal scaling_series : std_logic := '0';
	signal scaling_natural_log : std_logic := '0';
	signal base_scale_sign : std_logic := '0';
	signal normalization_value : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalization_exponent : signed(16 downto 0) :=
		(others => '0');
	signal series_result_register : unsigned(SERIES_WIDTH - 1 downto 0) :=
		(others => '0');
	signal series_result_exponent : signed(16 downto 0) := (others => '0');

	signal arithmetic_left_a : unsigned(ARITHMETIC_WIDTH - 1 downto 0);
	signal arithmetic_right_a : unsigned(ARITHMETIC_WIDTH - 1 downto 0);
	signal arithmetic_left_b : unsigned(ARITHMETIC_WIDTH - 1 downto 0);
	signal arithmetic_right_b : unsigned(ARITHMETIC_WIDTH - 1 downto 0);
	signal arithmetic_subtract_a : std_logic;
	signal arithmetic_subtract_b : std_logic;
	signal arithmetic_result_a : unsigned(ARITHMETIC_WIDTH - 1 downto 0);
	signal arithmetic_result_b : unsigned(ARITHMETIC_WIDTH - 1 downto 0);

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

	arithmetic_operands : process(state, series_product, series_multiplier,
		series_multiplicand, cube_accumulator, atanh_numerator,
		atanh_denominator, cordic_x, cordic_y, cordic_iteration,
		cordic_z_previous, cordic_angle_previous,
		cordic_direction_previous, ln2_accumulator, ln2_multiplier,
		ln2_multiplicand, base_scale_accumulator, base_scale_multiplier,
		base_scale_index, logarithm_base_latched)
		variable shifted_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable base_scale_constant : unsigned(RESULT_WIDTH - 1 downto 0);
	begin
		arithmetic_left_a <= (others => '0');
		arithmetic_right_a <= (others => '0');
		arithmetic_left_b <= (others => '0');
		arithmetic_right_b <= (others => '0');
		arithmetic_subtract_a <= '0';
		arithmetic_subtract_b <= '0';
		case state is
			when SQUARE_SMALL_ARGUMENT =>
				arithmetic_left_a <= resize(series_product, ARITHMETIC_WIDTH);
				if series_multiplier(0) = '1' then
					arithmetic_right_a <= resize(series_multiplicand,
						ARITHMETIC_WIDTH);
				end if;
			when CUBE_SMALL_ARGUMENT =>
				arithmetic_left_a <= resize(cube_accumulator, ARITHMETIC_WIDTH);
				if series_multiplier(0) = '1' then
					arithmetic_right_a <= resize(series_multiplicand(79 downto 0),
						ARITHMETIC_WIDTH);
				end if;
			when NORMALIZE_ATANH_RATIO =>
				arithmetic_left_a <= resize(atanh_numerator, ARITHMETIC_WIDTH);
				arithmetic_right_a <= resize(atanh_denominator,
					ARITHMETIC_WIDTH);
				arithmetic_subtract_a <= '1';
			when DIVIDE_ATANH_RATIO =>
				shifted_remainder := shift_left(atanh_numerator, 1);
				arithmetic_left_a <= resize(shifted_remainder, ARITHMETIC_WIDTH);
				if shifted_remainder >= atanh_denominator then
					arithmetic_right_a <= resize(atanh_denominator,
						ARITHMETIC_WIDTH);
					arithmetic_subtract_a <= '1';
				end if;
			when ROTATE_CORDIC_XY =>
				arithmetic_left_a <= unsigned(resize(cordic_x,
					ARITHMETIC_WIDTH));
				arithmetic_right_a <= unsigned(resize(shift_right(cordic_y,
					cordic_iteration), ARITHMETIC_WIDTH));
				arithmetic_left_b <= unsigned(resize(cordic_y,
					ARITHMETIC_WIDTH));
				arithmetic_right_b <= unsigned(resize(shift_right(cordic_x,
					cordic_iteration), ARITHMETIC_WIDTH));
				if cordic_y >= 0 then
					arithmetic_subtract_a <= '1';
					arithmetic_subtract_b <= '1';
				end if;
			when ROTATE_CORDIC_Z =>
				arithmetic_left_a <= unsigned(resize(cordic_z_previous,
					ARITHMETIC_WIDTH));
				arithmetic_right_a <= unsigned(resize(cordic_angle_previous,
					ARITHMETIC_WIDTH));
				arithmetic_subtract_a <= not cordic_direction_previous;
			when MULTIPLY_LN2 =>
				arithmetic_left_a <= resize(ln2_accumulator, ARITHMETIC_WIDTH);
				if ln2_multiplier(0) = '1' then
					arithmetic_right_a <= resize(ln2_multiplicand,
						ARITHMETIC_WIDTH);
				end if;
			when SCALE_LOGARITHM_BASE =>
				arithmetic_left_a <= resize(base_scale_accumulator,
					ARITHMETIC_WIDTH);
				if logarithm_base_latched = FPU_LOG_BASE_TWO then
					base_scale_constant := LOG2_E_FIXED;
				else
					base_scale_constant := LOG10_E_FIXED;
				end if;
				if base_scale_multiplier(base_scale_index) = '1' then
					arithmetic_right_a <= resize(base_scale_constant,
						ARITHMETIC_WIDTH);
				end if;
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

	logarithm_sequence : process(clk)
		procedure begin_fixed_result(constant fixed_value : in signed(
				RESULT_WIDTH - 1 downto 0)) is
		begin
			log_fraction <= fixed_value;
			state <= LOAD_FIXED_RESULT;
		end procedure;

		procedure begin_base_ten_scale(constant natural_log : in signed(
				RESULT_WIDTH - 1 downto 0)) is
			variable magnitude : unsigned(RESULT_WIDTH - 1 downto 0);
		begin
			if natural_log = 0 then
				begin_fixed_result(natural_log);
			else
				if natural_log < 0 then
					magnitude := unsigned(-natural_log);
					base_scale_sign <= '1';
				else
					magnitude := unsigned(natural_log);
					base_scale_sign <= '0';
				end if;
				base_scale_multiplier <= shift_left(magnitude, 1);
				base_scale_accumulator <= (others => '0');
				base_scale_index <= 0;
				scaling_series <= '0';
				scaling_natural_log <= '1';
				state <= SCALE_LOGARITHM_BASE;
			end if;
		end procedure;

		procedure begin_log_combine(
				constant fractional_log : in signed(RESULT_WIDTH - 1 downto 0);
				constant range_exponent : in signed(16 downto 0);
				constant base_value : in fpu_logarithm_base_t) is
			variable exponent_integer : integer range -65536 to 65535;
			variable exponent_magnitude : natural range 0 to 32767;
			variable fixed_exponent : signed(RESULT_WIDTH - 1 downto 0);
		begin
			exponent_integer := to_integer(range_exponent);
			log_fraction <= fractional_log;
			if base_value = FPU_LOG_BASE_TWO then
				fixed_exponent := shift_left(resize(range_exponent,
					RESULT_WIDTH), FRACTION_BITS);
				if fractional_log = 0 then
					begin_fixed_result(fixed_exponent);
				else
					base_scale_multiplier <= shift_left(unsigned(fractional_log), 1);
					base_scale_accumulator <= (others => '0');
					base_scale_index <= 0;
					scaling_series <= '0';
					scaling_natural_log <= '0';
					state <= SCALE_LOGARITHM_BASE;
				end if;
			elsif base_value = FPU_LOG_BASE_TEN and exponent_integer = 0 then
				begin_base_ten_scale(fractional_log);
			elsif exponent_integer = 0 then
				begin_fixed_result(fractional_log);
			else
				if exponent_integer < 0 then
					exponent_magnitude := -exponent_integer;
				else
					exponent_magnitude := exponent_integer;
				end if;
				ln2_multiplier <= to_unsigned(exponent_magnitude, 15);
				ln2_multiplicand <= resize(LN2_FIXED, RESULT_WIDTH);
				ln2_accumulator <= (others => '0');
				ln2_index <= 0;
				state <= MULTIPLY_LN2;
			end if;
		end procedure;

		procedure begin_cordic(
				constant mantissa_value : in unsigned(CORDIC_WIDTH - 1 downto 0);
				constant exponent_value : in signed(16 downto 0);
				constant base_value : in fpu_logarithm_base_t) is
		begin
			input_mantissa <= mantissa_value;
			input_exponent <= exponent_value;
			logarithm_base_latched <= base_value;
			state <= START_CORDIC;
		end procedure;

		procedure begin_atanh_ratio(
				constant magnitude_value : in unsigned(CORDIC_WIDTH downto 0)) is
			variable unit_value : unsigned(CORDIC_WIDTH downto 0);
		begin
			-- Apply the identity's factor of one half in begin_fixed_result so
			-- the ratio logarithm is rounded only once.
			unit_value := (others => '0');
			unit_value(FRACTION_BITS) := '1';
			atanh_numerator <= unit_value + magnitude_value;
			atanh_denominator <= unit_value - magnitude_value;
			atanh_quotient <= (others => '0');
			atanh_exponent <= (others => '0');
			atanh_iteration <= 0;
			state <= NORMALIZE_ATANH_RATIO;
		end procedure;

		procedure write_small_series_result(
				constant series_result : in unsigned(SERIES_WIDTH - 1 downto 0);
				constant result_exponent : in signed(16 downto 0)) is
		begin
			series_result_register <= series_result;
			series_result_exponent <= result_exponent;
			state <= FORMAT_SMALL_SERIES_RESULT;
		end procedure;

		procedure complete_small_series(
				constant series_result : in unsigned(SERIES_WIDTH - 1 downto 0)) is
		begin
			if logarithm_base_latched /= FPU_LOG_BASE_E then
				base_scale_multiplier <= shift_left(resize(series_result,
					RESULT_WIDTH), 1);
				base_scale_accumulator <= (others => '0');
				base_scale_index <= 0;
				scaling_series <= '1';
				scaling_natural_log <= '0';
				state <= SCALE_LOGARITHM_BASE;
			else
				write_small_series_result(series_result, series_exponent);
			end if;
		end procedure;

		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable delta_significand : unsigned(63 downto 0);
		variable next_series_source : unsigned(63 downto 0);
		variable initial_mantissa : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable aligned_source : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable aligned_unit : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable selected_nan : fpu_extended_t;
		variable next_input : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable next_input_exponent : signed(16 downto 0);
		variable next_angle : cordic_value_t;
		variable fractional_log : signed(RESULT_WIDTH - 1 downto 0);
		variable next_ln2 : unsigned(RESULT_WIDTH - 1 downto 0);
		variable next_base_scale : unsigned(RESULT_WIDTH downto 0);
		variable scaled_series : unsigned(SERIES_WIDTH downto 0);
		variable scaled_series_result : unsigned(SERIES_WIDTH - 1 downto 0);
		variable combined_log : signed(RESULT_WIDTH - 1 downto 0);
		variable next_normalization : unsigned(RESULT_WIDTH - 1 downto 0);
		variable next_normalization_exponent : signed(16 downto 0);
		variable final_significand : fpu_significand_grs_t;
		variable tiny_significand : fpu_significand_grs_t;
		variable next_square : unsigned(127 downto 0);
		variable next_cube : unsigned(79 downto 0);
		variable next_cube_quotient : unsigned(79 downto 0);
		variable division_trial : natural range 0 to 5;
		variable series_base : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_correction : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_cube_correction : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_value : unsigned(SERIES_WIDTH - 1 downto 0);
		variable atanh_aligned_source : unsigned(CORDIC_WIDTH downto 0);
		variable atanh_shifted_denominator : unsigned(CORDIC_WIDTH downto 0);
		variable atanh_shifted_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable atanh_next_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable atanh_next_quotient : unsigned(FRACTION_BITS downto 0);
		variable fixed_magnitude : unsigned(RESULT_WIDTH - 1 downto 0);
		variable fixed_result_exponent : integer;
		variable formatted_significand : fpu_significand_grs_t;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				logarithm_base_latched <= FPU_LOG_BASE_E;
				inverse_hyperbolic_tangent_latched <= '0';
				source_sign_latched <= '0';
				series_source_significand <= (others => '0');
				series_exponent <= (others => '0');
				series_multiplier <= (others => '0');
				series_multiplicand <= (others => '0');
				series_product <= (others => '0');
				square_high_register <= (others => '0');
				series_correction_register <= (others => '0');
				correction_shift_count <= 0;
				series_index <= 0;
				cube_accumulator <= (others => '0');
				cube_remainder <= 0;
				cube_shift_count <= 0;
				input_mantissa <= (others => '0');
				input_exponent <= (others => '0');
				cordic_x <= (others => '0');
				cordic_y <= (others => '0');
				cordic_z <= (others => '0');
				cordic_iteration <= 1;
				repeat_iteration <= '0';
				cordic_shift_angle <= (others => '0');
				cordic_angle_address <= 1;
				cordic_z_previous <= (others => '0');
				cordic_angle_previous <= (others => '0');
				cordic_direction_previous <= '0';
				atanh_numerator <= (others => '0');
				atanh_denominator <= (others => '0');
				atanh_quotient <= (others => '0');
				atanh_exponent <= (others => '0');
				atanh_iteration <= 0;
				log_fraction <= (others => '0');
				ln2_multiplier <= (others => '0');
				ln2_multiplicand <= (others => '0');
				ln2_accumulator <= (others => '0');
				ln2_index <= 0;
				base_scale_multiplier <= (others => '0');
				base_scale_accumulator <= (others => '0');
				base_scale_index <= 0;
				scaling_series <= '0';
				scaling_natural_log <= '0';
				base_scale_sign <= '0';
				normalization_value <= (others => '0');
				normalization_exponent <= (others => '0');
				series_result_register <= (others => '0');
				series_result_exponent <= (others => '0');
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
							logarithm_base_latched <= logarithm_base;
							inverse_hyperbolic_tangent_latched <=
								inverse_hyperbolic_tangent;
							source_sign_latched <= source(79);
							series_source_significand <= (others => '0');
							series_exponent <= (others => '0');
							series_multiplier <= (others => '0');
							series_multiplicand <= (others => '0');
							series_product <= (others => '0');
							square_high_register <= (others => '0');
							series_correction_register <= (others => '0');
							correction_shift_count <= 0;
							series_index <= 0;
							cube_accumulator <= (others => '0');
							cube_remainder <= 0;
							cube_shift_count <= 0;
							input_mantissa <= (others => '0');
							input_exponent <= (others => '0');
							cordic_x <= (others => '0');
							cordic_y <= (others => '0');
							cordic_z <= (others => '0');
							cordic_iteration <= 1;
							repeat_iteration <= '0';
							cordic_shift_angle <= (others => '0');
							cordic_angle_address <= 1;
							cordic_z_previous <= (others => '0');
							cordic_angle_previous <= (others => '0');
							cordic_direction_previous <= '0';
							atanh_numerator <= (others => '0');
							atanh_denominator <= (others => '0');
							atanh_quotient <= (others => '0');
							atanh_exponent <= (others => '0');
							atanh_iteration <= 0;
							log_fraction <= (others => '0');
							ln2_multiplier <= (others => '0');
							ln2_multiplicand <= (others => '0');
							ln2_accumulator <= (others => '0');
							ln2_index <= 0;
							base_scale_multiplier <= (others => '0');
							base_scale_accumulator <= (others => '0');
							base_scale_index <= 0;
							scaling_series <= '0';
							scaling_natural_log <= '0';
							base_scale_sign <= '0';
							normalization_value <= (others => '0');
							normalization_exponent <= (others => '0');
							series_result_register <= (others => '0');
							series_result_exponent <= (others => '0');
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= '0';
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							base_status <= (others => '0');

							if source_class = FPU_CLASS_QUIET_NAN or
									source_class = FPU_CLASS_SIGNALING_NAN then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_sign <= source(79);
								intermediate_special <= selected_nan;
								if source_class = FPU_CLASS_SIGNALING_NAN then
									base_status(6) <= '1';
								end if;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_ZERO or
									source_significand = 0 then
								if add_one = '1' or
										inverse_hyperbolic_tangent = '1' then
									intermediate_class <= FPU_CLASS_ZERO;
									intermediate_sign <= source(79);
								else
									intermediate_class <= FPU_CLASS_INFINITY;
									intermediate_sign <= '1';
									base_status(2) <= '1';
								end if;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								if inverse_hyperbolic_tangent = '1' then
									intermediate_class <= FPU_CLASS_QUIET_NAN;
									intermediate_special <= FPU_RESET_NAN;
									base_status(5) <= '1';
								elsif source(79) = '1' then
									intermediate_class <= FPU_CLASS_QUIET_NAN;
									intermediate_special <= FPU_RESET_NAN;
									base_status(5) <= '1';
								else
									intermediate_class <= FPU_CLASS_INFINITY;
								end if;
								state <= COMPLETE;
							else
								normalization_shift :=
									63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									normalization_shift);
								source_exponent := source_exponent -
									normalization_shift;
								if inverse_hyperbolic_tangent = '1' then
									if source_exponent >= 0 then
										if source_exponent = 0 and
												source_significand = x"8000000000000000" then
											intermediate_class <= FPU_CLASS_INFINITY;
											intermediate_sign <= source(79);
											base_status(2) <= '1';
										else
											intermediate_class <= FPU_CLASS_QUIET_NAN;
											intermediate_special <= FPU_RESET_NAN;
											base_status(5) <= '1';
										end if;
										state <= COMPLETE;
									elsif source_exponent <= SERIES_CUBIC_MAX_EXPONENT then
										base_status(1) <= '1';
										if source_exponent <= ATANH_TINY_MAX_EXPONENT then
											tiny_significand := shift_left(resize(
												source_significand, 67), 3) + 1;
											intermediate_class <= FPU_CLASS_NORMAL;
											intermediate_sign <= source(79);
											intermediate_exponent <= to_signed(
												source_exponent, 17);
											intermediate_significand <= tiny_significand;
											state <= COMPLETE;
										else
											series_source_significand <= source_significand;
											series_exponent <= to_signed(source_exponent, 17);
											series_multiplier <= source_significand;
											series_multiplicand <= resize(
												source_significand, 128);
											series_product <= (others => '0');
											series_index <= 0;
											state <= SQUARE_SMALL_ARGUMENT;
										end if;
									else
										base_status(1) <= '1';
										atanh_aligned_source := shift_left(resize(
											source_significand, CORDIC_WIDTH + 1), 33);
										atanh_aligned_source := shift_right(
											atanh_aligned_source, -source_exponent);
										begin_atanh_ratio(atanh_aligned_source);
									end if;
								elsif add_one = '0' and source(79) = '1' then
									intermediate_class <= FPU_CLASS_QUIET_NAN;
									intermediate_special <= FPU_RESET_NAN;
									base_status(5) <= '1';
									state <= COMPLETE;
								elsif add_one = '0' then
									if source_exponent = 0 and
											source_significand = x"8000000000000000" then
										intermediate_class <= FPU_CLASS_ZERO;
										state <= COMPLETE;
									else
										if logarithm_base /= FPU_LOG_BASE_TWO or
												source_significand /= x"8000000000000000" then
											base_status(1) <= '1';
										end if;
										if source_exponent = 0 then
											delta_significand := source_significand -
												x"8000000000000000";
										elsif source_exponent = -1 then
											delta_significand := not source_significand;
											delta_significand := delta_significand + 1;
										else
											delta_significand := (others => '0');
										end if;
										if (source_exponent = 0 and
												delta_significand(63 downto 38) = 0) or
												(source_exponent = -1 and
												delta_significand(63 downto 39) = 0) then
											source_sign_latched <= '0';
											if source_exponent = -1 then
												source_sign_latched <= '1';
											end if;
											series_source_significand <= delta_significand;
											series_exponent <= to_signed(source_exponent, 17);
											state <= NORMALIZE_SERIES_ARGUMENT;
										else
											initial_mantissa := shift_left(resize(
												source_significand, CORDIC_WIDTH), 33);
											begin_cordic(initial_mantissa,
												to_signed(source_exponent, 17), logarithm_base);
										end if;
									end if;
								elsif source(79) = '1' and source_exponent >= 0 then
									if source_exponent = 0 and
											source_significand = x"8000000000000000" then
										intermediate_class <= FPU_CLASS_INFINITY;
										intermediate_sign <= '1';
										base_status(2) <= '1';
									else
										intermediate_class <= FPU_CLASS_QUIET_NAN;
										intermediate_special <= FPU_RESET_NAN;
										base_status(5) <= '1';
									end if;
									state <= COMPLETE;
								elsif source_exponent <= SERIES_CUBIC_MAX_EXPONENT then
									base_status(1) <= '1';
									if source_exponent < -67 then
										tiny_significand := shift_left(resize(
											source_significand, 67), 3);
										if source(79) = '0' then
											tiny_significand := tiny_significand - 1;
										else
											tiny_significand := tiny_significand + 1;
										end if;
										intermediate_class <= FPU_CLASS_NORMAL;
										intermediate_sign <= source(79);
										if tiny_significand(66) = '0' then
											intermediate_exponent <= to_signed(
												source_exponent - 1, 17);
											intermediate_significand <= shift_left(
												tiny_significand, 1);
										else
											intermediate_exponent <= to_signed(
												source_exponent, 17);
											intermediate_significand <= tiny_significand;
										end if;
										state <= COMPLETE;
									else
										series_source_significand <= source_significand;
										series_exponent <= to_signed(source_exponent, 17);
										series_multiplier <= source_significand;
										series_multiplicand <= resize(
											source_significand, 128);
										series_product <= (others => '0');
										series_index <= 0;
										state <= SQUARE_SMALL_ARGUMENT;
									end if;
								else
									base_status(1) <= '1';
									aligned_source := shift_left(resize(
										source_significand, CORDIC_WIDTH), 33);
									aligned_unit := (others => '0');
									aligned_unit(FRACTION_BITS) := '1';
									if source_exponent >= 0 then
										initial_mantissa := aligned_source;
										if source_exponent <= FRACTION_BITS then
											initial_mantissa := initial_mantissa +
												shift_right(aligned_unit, source_exponent);
										end if;
										if initial_mantissa(FRACTION_BITS + 1) = '1' then
											initial_mantissa := shift_right(
												initial_mantissa, 1);
											begin_cordic(initial_mantissa,
												to_signed(source_exponent + 1, 17), logarithm_base);
										else
											begin_cordic(initial_mantissa,
												to_signed(source_exponent, 17), logarithm_base);
										end if;
									else
										aligned_source := shift_left(resize(
											source_significand, CORDIC_WIDTH),
											source_exponent + 33);
										if source(79) = '0' then
											initial_mantissa := aligned_unit + aligned_source;
											begin_cordic(initial_mantissa,
												to_signed(0, 17), logarithm_base);
										else
											initial_mantissa := aligned_unit - aligned_source;
											input_mantissa <= initial_mantissa;
											input_exponent <= to_signed(0, 17);
											state <= NORMALIZE_INPUT;
										end if;
									end if;
								end if;
							end if;
						end if;

					when NORMALIZE_SERIES_ARGUMENT =>
						next_series_source := shift_left(
							series_source_significand, 1);
						series_source_significand <= next_series_source;
						series_exponent <= series_exponent - 1;
						if next_series_source(63) = '1' then
							series_multiplier <= next_series_source;
							series_multiplicand <= resize(next_series_source, 128);
							series_product <= (others => '0');
							series_index <= 0;
							state <= SQUARE_SMALL_ARGUMENT;
						end if;

					when SQUARE_SMALL_ARGUMENT =>
						next_square := arithmetic_result_a(127 downto 0);
						if series_index = 63 then
							series_product <= next_square;
							square_high_register <= next_square(
								127 downto CUBE_SQUARE_LOW_BIT);
							if inverse_hyperbolic_tangent_latched = '1' then
								series_multiplier <= series_source_significand;
								series_multiplicand <= resize(next_square(
									127 downto CUBE_SQUARE_LOW_BIT), 128);
								cube_accumulator <= (others => '0');
								series_index <= 0;
								state <= CUBE_SMALL_ARGUMENT;
							else
								correction_shift_count <= 44 -
									to_integer(series_exponent);
								state <= ALIGN_SQUARE_TERM;
							end if;
						else
							series_product <= next_square;
							series_multiplier <= shift_right(series_multiplier, 1);
							series_multiplicand <= shift_left(
								series_multiplicand, 1);
							series_index <= series_index + 1;
						end if;

					when ALIGN_SQUARE_TERM =>
						next_square := shift_right(series_product, 1);
						series_product <= next_square;
						if correction_shift_count = 1 then
							series_correction := resize(next_square, SERIES_WIDTH);
							series_correction_register <= series_correction;
							correction_shift_count <= 0;
							if to_integer(series_exponent) <
									SERIES_CUBIC_MIN_EXPONENT then
								series_base := shift_left(resize(
									series_source_significand, SERIES_WIDTH),
									SERIES_NORMAL_BIT - 63);
								if source_sign_latched = '0' then
									series_value := series_base - series_correction;
								else
									series_value := series_base + series_correction;
								end if;
								complete_small_series(series_value);
							else
								series_multiplier <= series_source_significand;
								series_multiplicand <= resize(
									square_high_register, 128);
								cube_accumulator <= (others => '0');
								series_index <= 0;
								state <= CUBE_SMALL_ARGUMENT;
							end if;
						else
							correction_shift_count <= correction_shift_count - 1;
						end if;

					when CUBE_SMALL_ARGUMENT =>
						next_cube := arithmetic_result_a(79 downto 0);
						if series_index = 63 then
							series_multiplicand <= resize(next_cube, 128);
							cube_accumulator <= (others => '0');
							cube_remainder <= 0;
							series_index <= 0;
							state <= DIVIDE_CUBE_TERM;
						else
							cube_accumulator <= next_cube;
							series_multiplier <= shift_right(series_multiplier, 1);
							series_multiplicand <= shift_left(
								series_multiplicand, 1);
							series_index <= series_index + 1;
						end if;

					when DIVIDE_CUBE_TERM =>
						division_trial := cube_remainder * 2;
						if series_multiplicand(79 - series_index) = '1' then
							division_trial := division_trial + 1;
						end if;
						next_cube_quotient := cube_accumulator;
						if division_trial >= 3 then
							next_cube_quotient(79 - series_index) := '1';
							division_trial := division_trial - 3;
						end if;
						if series_index = 79 then
							cube_accumulator <= next_cube_quotient;
							cube_shift_count <= -2 *
								to_integer(series_exponent) - 6;
							series_index <= 0;
							state <= ALIGN_CUBE_TERM;
						else
							cube_accumulator <= next_cube_quotient;
							cube_remainder <= division_trial;
							series_index <= series_index + 1;
						end if;

					when ALIGN_CUBE_TERM =>
						next_cube := shift_right(cube_accumulator, 1);
						cube_accumulator <= next_cube;
						if cube_shift_count = 1 then
							series_base := shift_left(resize(
								series_source_significand, SERIES_WIDTH),
								SERIES_NORMAL_BIT - 63);
							series_cube_correction := resize(next_cube, SERIES_WIDTH);
							if inverse_hyperbolic_tangent_latched = '1' then
								series_value := series_base + series_cube_correction;
							elsif source_sign_latched = '0' then
								series_value := series_base -
									series_correction_register +
									series_cube_correction -
									shift_left(to_unsigned(1, SERIES_WIDTH),
										POSITIVE_REMAINDER_BOUND_BIT);
							else
								series_value := series_base +
									series_correction_register +
									series_cube_correction;
							end if;
							cube_shift_count <= 0;
							complete_small_series(series_value);
						else
							cube_shift_count <= cube_shift_count - 1;
						end if;

					when NORMALIZE_ATANH_RATIO =>
						atanh_shifted_denominator := shift_left(
							atanh_denominator, 1);
						if atanh_shifted_denominator <= atanh_numerator then
							atanh_denominator <= atanh_shifted_denominator;
							atanh_exponent <= atanh_exponent + 1;
						else
							atanh_numerator <= arithmetic_result_a(
								CORDIC_WIDTH downto 0);
							atanh_quotient <= (0 => '1', others => '0');
							atanh_iteration <= 0;
							state <= DIVIDE_ATANH_RATIO;
						end if;

					when DIVIDE_ATANH_RATIO =>
						atanh_shifted_remainder := shift_left(atanh_numerator, 1);
						atanh_next_remainder := arithmetic_result_a(
							CORDIC_WIDTH downto 0);
						atanh_next_quotient := shift_left(atanh_quotient, 1);
						if atanh_shifted_remainder >= atanh_denominator then
							atanh_next_quotient(0) := '1';
						else
							atanh_next_quotient(0) := '0';
						end if;
						atanh_numerator <= atanh_next_remainder;
						atanh_quotient <= atanh_next_quotient;
						if atanh_iteration = FRACTION_BITS - 1 then
							begin_cordic(resize(atanh_next_quotient, CORDIC_WIDTH),
								atanh_exponent, FPU_LOG_BASE_E);
						else
							atanh_iteration <= atanh_iteration + 1;
						end if;

					when NORMALIZE_INPUT =>
						next_input := shift_left(input_mantissa, 1);
						next_input_exponent := input_exponent - 1;
						input_mantissa <= next_input;
						input_exponent <= next_input_exponent;
						if next_input(FRACTION_BITS) = '1' then
							begin_cordic(next_input, next_input_exponent,
								logarithm_base_latched);
						end if;

					when START_CORDIC =>
						aligned_unit := (others => '0');
						aligned_unit(FRACTION_BITS) := '1';
						if input_mantissa = aligned_unit then
							begin_log_combine(to_signed(0, RESULT_WIDTH),
								input_exponent, logarithm_base_latched);
						else
							cordic_x <= signed(input_mantissa + aligned_unit);
							cordic_y <= signed(input_mantissa - aligned_unit);
							cordic_z <= (others => '0');
							cordic_iteration <= 1;
							repeat_iteration <= '0';
							cordic_angle_address <= 1;
							state <= LOAD_CORDIC_ANGLE;
						end if;

					when LOAD_CORDIC_ANGLE =>
						state <= ROTATE_CORDIC_XY;

					when ROTATE_CORDIC_XY =>
						if cordic_iteration <= 31 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						cordic_z_previous <= cordic_z;
						cordic_angle_previous <= next_angle;
						if cordic_y >= 0 then
							cordic_direction_previous <= '1';
						else
							cordic_direction_previous <= '0';
						end if;
						cordic_x <= signed(arithmetic_result_a(
							CORDIC_WIDTH - 1 downto 0));
						cordic_y <= signed(arithmetic_result_b(
							CORDIC_WIDTH - 1 downto 0));
						if not ((cordic_iteration = 4 or
								cordic_iteration = 13 or cordic_iteration = 40) and
								repeat_iteration = '0') then
							if cordic_iteration < 31 then
								cordic_angle_address <= cordic_iteration + 1;
							elsif cordic_iteration = 31 then
								next_angle := (others => '0');
								next_angle(FRACTION_BITS - 32) := '1';
								cordic_shift_angle <= next_angle;
							elsif cordic_iteration < FRACTION_BITS then
								cordic_shift_angle <= shift_right(
									cordic_shift_angle, 1);
							end if;
						end if;
						state <= ROTATE_CORDIC_Z;

					when ROTATE_CORDIC_Z =>
						cordic_z <= signed(arithmetic_result_a(
							RESULT_WIDTH - 1 downto 0));
						if (cordic_iteration = 4 or cordic_iteration = 13 or
								cordic_iteration = 40) and repeat_iteration = '0' then
							repeat_iteration <= '1';
							state <= ROTATE_CORDIC_XY;
						elsif cordic_iteration = FRACTION_BITS then
							state <= FINISH_CORDIC;
						else
							repeat_iteration <= '0';
							cordic_iteration <= cordic_iteration + 1;
							state <= ROTATE_CORDIC_XY;
						end if;

					when FINISH_CORDIC =>
						fractional_log := shift_left(cordic_z, 1);
						begin_log_combine(fractional_log, input_exponent,
							logarithm_base_latched);

					when MULTIPLY_LN2 =>
						next_ln2 := arithmetic_result_a(
							RESULT_WIDTH - 1 downto 0);
						if ln2_index = 14 then
							if input_exponent < 0 then
								combined_log := log_fraction - signed(next_ln2);
							else
								combined_log := log_fraction + signed(next_ln2);
							end if;
							if logarithm_base_latched = FPU_LOG_BASE_TEN then
								begin_base_ten_scale(combined_log);
							else
								begin_fixed_result(combined_log);
							end if;
						else
							ln2_accumulator <= next_ln2;
							ln2_multiplier <= shift_right(ln2_multiplier, 1);
							ln2_multiplicand <= shift_left(ln2_multiplicand, 1);
							ln2_index <= ln2_index + 1;
						end if;

					when SCALE_LOGARITHM_BASE =>
						next_base_scale := shift_right(arithmetic_result_a(
							RESULT_WIDTH downto 0), 1);
						base_scale_accumulator <= next_base_scale;
						if base_scale_index = RESULT_WIDTH - 1 then
							if scaling_series = '1' then
								scaled_series := resize(next_base_scale,
									SERIES_WIDTH + 1);
								if scaled_series(SERIES_WIDTH) = '1' then
									scaled_series_result := scaled_series(
										SERIES_WIDTH downto 1);
									scaled_series_result(0) :=
										scaled_series_result(0) or scaled_series(0);
									write_small_series_result(scaled_series_result,
										series_exponent + 1);
								else
									write_small_series_result(scaled_series(
										SERIES_WIDTH - 1 downto 0), series_exponent);
								end if;
							elsif scaling_natural_log = '1' then
								if base_scale_sign = '1' then
									combined_log := -signed(next_base_scale(
										RESULT_WIDTH - 1 downto 0));
								else
									combined_log := signed(next_base_scale(
										RESULT_WIDTH - 1 downto 0));
								end if;
								begin_fixed_result(combined_log);
							else
								combined_log := shift_left(resize(input_exponent,
									RESULT_WIDTH), FRACTION_BITS) + signed(
									next_base_scale(RESULT_WIDTH - 1 downto 0));
								begin_fixed_result(combined_log);
							end if;
						else
							base_scale_index <= base_scale_index + 1;
						end if;

					when LOAD_FIXED_RESULT =>
						fixed_result_exponent := RESULT_NORMAL_BIT - FRACTION_BITS;
						if inverse_hyperbolic_tangent_latched = '1' then
							fixed_result_exponent := fixed_result_exponent - 1;
						end if;
						if log_fraction = 0 then
							intermediate_class <= FPU_CLASS_ZERO;
							if inverse_hyperbolic_tangent_latched = '1' then
								intermediate_sign <= source_sign_latched;
							else
								intermediate_sign <= '0';
							end if;
							state <= COMPLETE;
						elsif log_fraction < 0 then
							fixed_magnitude := unsigned(-log_fraction);
							intermediate_sign <= '1';
							normalization_value <= fixed_magnitude;
							normalization_exponent <= to_signed(
								fixed_result_exponent, 17);
							state <= NORMALIZE_RESULT;
						else
							fixed_magnitude := unsigned(log_fraction);
							if inverse_hyperbolic_tangent_latched = '1' then
								intermediate_sign <= source_sign_latched;
							else
								intermediate_sign <= '0';
							end if;
							normalization_value <= fixed_magnitude;
							normalization_exponent <= to_signed(
								fixed_result_exponent, 17);
							state <= NORMALIZE_RESULT;
						end if;

					when NORMALIZE_RESULT =>
						if normalization_value(RESULT_NORMAL_BIT) = '1' then
							final_significand := (others => '0');
							final_significand(66 downto 3) := normalization_value(
								RESULT_NORMAL_BIT downto RESULT_NORMAL_BIT - 63);
							final_significand(2) := normalization_value(
								RESULT_NORMAL_BIT - 64);
							final_significand(1) := normalization_value(
								RESULT_NORMAL_BIT - 65);
							final_significand(0) := or_reduce(normalization_value(
								RESULT_NORMAL_BIT - 66 downto 0));
							intermediate_class <= FPU_CLASS_NORMAL;
							intermediate_exponent <= normalization_exponent;
							intermediate_significand <= final_significand;
							state <= COMPLETE;
						else
							next_normalization := shift_left(normalization_value, 1);
							next_normalization_exponent :=
								normalization_exponent - 1;
							normalization_value <= next_normalization;
							normalization_exponent <= next_normalization_exponent;
						end if;

					when FORMAT_SMALL_SERIES_RESULT =>
						formatted_significand := (others => '0');
						if series_result_register(SERIES_NORMAL_BIT + 1) = '1' then
							formatted_significand(66 downto 1) :=
								series_result_register(SERIES_NORMAL_BIT + 1 downto
									SERIES_NORMAL_BIT - 64);
							intermediate_exponent <= series_result_exponent + 1;
						elsif series_result_register(SERIES_NORMAL_BIT) = '1' then
							formatted_significand(66 downto 1) :=
								series_result_register(SERIES_NORMAL_BIT downto
									SERIES_NORMAL_BIT - 65);
							intermediate_exponent <= series_result_exponent;
						elsif series_result_register(SERIES_NORMAL_BIT - 1) = '1' then
							formatted_significand(66 downto 1) :=
								series_result_register(SERIES_NORMAL_BIT - 1 downto
									SERIES_NORMAL_BIT - 66);
							intermediate_exponent <= series_result_exponent - 1;
						else
							formatted_significand(66 downto 1) :=
								series_result_register(SERIES_NORMAL_BIT - 2 downto
									SERIES_NORMAL_BIT - 67);
							intermediate_exponent <= series_result_exponent - 2;
						end if;
						formatted_significand(0) := '1';
						intermediate_class <= FPU_CLASS_NORMAL;
						intermediate_sign <= source_sign_latched;
						intermediate_significand <= formatted_significand;
						state <= COMPLETE;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
