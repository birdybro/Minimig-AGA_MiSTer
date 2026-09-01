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
	constant RESULT_NORMAL_BIT : natural := RESULT_WIDTH - 2;
	constant SERIES_WIDTH : natural := 85;
	constant SERIES_NORMAL_BIT : natural := 83;
	constant SERIES_CUBIC_MAX_EXPONENT : integer := -26;
	constant SERIES_CUBIC_MIN_EXPONENT : integer := -40;
	constant CUBE_SQUARE_LOW_BIT : natural := 112;
	constant POSITIVE_REMAINDER_BOUND_BIT : natural := 9;
	type logarithm_state_t is
		(IDLE, SQUARE_SMALL_ARGUMENT, ALIGN_SQUARE_TERM,
			CUBE_SMALL_ARGUMENT, DIVIDE_CUBE_TERM, ALIGN_CUBE_TERM,
			NORMALIZE_INPUT, LOAD_CORDIC_ANGLE, CORDIC, MULTIPLY_LN2,
			NORMALIZE_RESULT, WRITE_PENDING_RESULT, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 31) of cordic_value_t;

	constant LN2_FIXED : unsigned(FRACTION_BITS - 1 downto 0) :=
		x"B17217F7D1CF79ABC9E3B398";
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
	signal cordic_z : cordic_value_t := (others => '0');
	signal cordic_iteration : natural range 1 to FRACTION_BITS := 1;
	signal repeat_iteration : std_logic := '0';
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal cordic_angle_address : natural range 1 to 31 := 1;

	signal log_fraction : signed(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal ln2_multiplier : unsigned(14 downto 0) := (others => '0');
	signal ln2_multiplicand : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal ln2_accumulator : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal ln2_index : natural range 0 to 14 := 0;
	signal normalization_value : unsigned(RESULT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalization_exponent : signed(16 downto 0) :=
		(others => '0');
	signal pending_sign : std_logic := '0';
	signal pending_exponent : signed(16 downto 0) := (others => '0');
	signal pending_significand : fpu_significand_grs_t := (others => '0');

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
			variable magnitude : unsigned(RESULT_WIDTH - 1 downto 0);
		begin
			if fixed_value = 0 then
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				state <= COMPLETE;
			elsif fixed_value < 0 then
				magnitude := unsigned(-fixed_value);
				intermediate_sign <= '1';
				normalization_value <= magnitude;
				normalization_exponent <= to_signed(
					RESULT_NORMAL_BIT - FRACTION_BITS, 17);
				state <= NORMALIZE_RESULT;
			else
				magnitude := unsigned(fixed_value);
				intermediate_sign <= '0';
				normalization_value <= magnitude;
				normalization_exponent <= to_signed(
					RESULT_NORMAL_BIT - FRACTION_BITS, 17);
				state <= NORMALIZE_RESULT;
			end if;
		end procedure;

		procedure begin_log_combine(
				constant fractional_log : in signed(RESULT_WIDTH - 1 downto 0);
				constant range_exponent : in signed(16 downto 0)) is
			variable exponent_integer : integer range -65536 to 65535;
			variable exponent_magnitude : natural range 0 to 32767;
		begin
			exponent_integer := to_integer(range_exponent);
			log_fraction <= fractional_log;
			if exponent_integer = 0 then
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
				constant exponent_value : in signed(16 downto 0)) is
			variable unit_value : unsigned(CORDIC_WIDTH - 1 downto 0);
		begin
			unit_value := (others => '0');
			unit_value(FRACTION_BITS) := '1';
			input_exponent <= exponent_value;
			if mantissa_value = unit_value then
				begin_log_combine(to_signed(0, RESULT_WIDTH), exponent_value);
			else
				cordic_x <= signed(mantissa_value + unit_value);
				cordic_y <= signed(mantissa_value - unit_value);
				cordic_z <= (others => '0');
				cordic_iteration <= 1;
				repeat_iteration <= '0';
				cordic_angle_address <= 1;
				state <= LOAD_CORDIC_ANGLE;
			end if;
		end procedure;

		procedure complete_small_series(
				constant series_result : in unsigned(SERIES_WIDTH - 1 downto 0)) is
			variable final_significand : fpu_significand_grs_t;
		begin
			final_significand := (others => '0');
			if series_result(SERIES_NORMAL_BIT + 1) = '1' then
				final_significand(66 downto 1) := series_result(
					SERIES_NORMAL_BIT + 1 downto SERIES_NORMAL_BIT - 64);
			elsif series_result(SERIES_NORMAL_BIT) = '1' then
				final_significand(66 downto 1) := series_result(
					SERIES_NORMAL_BIT downto SERIES_NORMAL_BIT - 65);
			else
				final_significand(66 downto 1) := series_result(
					SERIES_NORMAL_BIT - 1 downto SERIES_NORMAL_BIT - 66);
			end if;
			final_significand(0) := '1';
			pending_sign <= source_sign_latched;
			if series_result(SERIES_NORMAL_BIT + 1) = '1' then
				pending_exponent <= series_exponent + 1;
			elsif series_result(SERIES_NORMAL_BIT) = '1' then
				pending_exponent <= series_exponent;
			else
				pending_exponent <= series_exponent - 1;
			end if;
			pending_significand <= final_significand;
			state <= WRITE_PENDING_RESULT;
		end procedure;

		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable initial_mantissa : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable aligned_source : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable aligned_unit : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable selected_nan : fpu_extended_t;
		variable next_input : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable next_input_exponent : signed(16 downto 0);
		variable next_x : cordic_value_t;
		variable next_y : cordic_value_t;
		variable next_z : cordic_value_t;
		variable next_angle : cordic_value_t;
		variable fractional_log : signed(RESULT_WIDTH - 1 downto 0);
		variable ln2_sum : unsigned(RESULT_WIDTH - 1 downto 0);
		variable next_ln2 : unsigned(RESULT_WIDTH - 1 downto 0);
		variable combined_log : signed(RESULT_WIDTH - 1 downto 0);
		variable next_normalization : unsigned(RESULT_WIDTH - 1 downto 0);
		variable next_normalization_exponent : signed(16 downto 0);
		variable final_significand : fpu_significand_grs_t;
		variable tiny_significand : fpu_significand_grs_t;
		variable square_sum : unsigned(127 downto 0);
		variable next_square : unsigned(127 downto 0);
		variable cube_sum : unsigned(79 downto 0);
		variable next_cube : unsigned(79 downto 0);
		variable next_cube_quotient : unsigned(79 downto 0);
		variable division_trial : natural range 0 to 5;
		variable series_base : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_correction : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_cube_correction : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_value : unsigned(SERIES_WIDTH - 1 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
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
				log_fraction <= (others => '0');
				ln2_multiplier <= (others => '0');
				ln2_multiplicand <= (others => '0');
				ln2_accumulator <= (others => '0');
				ln2_index <= 0;
				normalization_value <= (others => '0');
				normalization_exponent <= (others => '0');
				pending_sign <= '0';
				pending_exponent <= (others => '0');
				pending_significand <= (others => '0');
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
							log_fraction <= (others => '0');
							ln2_multiplier <= (others => '0');
							ln2_multiplicand <= (others => '0');
							ln2_accumulator <= (others => '0');
							ln2_index <= 0;
							normalization_value <= (others => '0');
							normalization_exponent <= (others => '0');
							pending_sign <= '0';
							pending_exponent <= (others => '0');
							pending_significand <= (others => '0');
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
								intermediate_class <= FPU_CLASS_ZERO;
								intermediate_sign <= source(79);
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								if source(79) = '1' then
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
								if source(79) = '1' and source_exponent >= 0 then
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
												to_signed(source_exponent + 1, 17));
										else
											begin_cordic(initial_mantissa,
												to_signed(source_exponent, 17));
										end if;
									else
										aligned_source := shift_left(resize(
											source_significand, CORDIC_WIDTH),
											source_exponent + 33);
										if source(79) = '0' then
											initial_mantissa := aligned_unit + aligned_source;
											begin_cordic(initial_mantissa,
												to_signed(0, 17));
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

					when SQUARE_SMALL_ARGUMENT =>
						square_sum := series_product;
						if series_multiplier(0) = '1' then
							square_sum := square_sum + series_multiplicand;
						end if;
						next_square := square_sum;
						if series_index = 63 then
							series_product <= next_square;
							square_high_register <= next_square(
								127 downto CUBE_SQUARE_LOW_BIT);
							correction_shift_count <= 44 -
								to_integer(series_exponent);
							state <= ALIGN_SQUARE_TERM;
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
									series_value := series_base - series_correction - 1;
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
						cube_sum := cube_accumulator;
						if series_multiplier(0) = '1' then
							cube_sum := cube_sum + series_multiplicand(79 downto 0);
						end if;
						next_cube := cube_sum;
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
							if source_sign_latched = '0' then
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

					when NORMALIZE_INPUT =>
						next_input := shift_left(input_mantissa, 1);
						next_input_exponent := input_exponent - 1;
						input_mantissa <= next_input;
						input_exponent <= next_input_exponent;
						if next_input(FRACTION_BITS) = '1' then
							begin_cordic(next_input, next_input_exponent);
						end if;

					when LOAD_CORDIC_ANGLE =>
						state <= CORDIC;

					when CORDIC =>
						if cordic_iteration <= 31 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						if cordic_y >= 0 then
							next_x := cordic_x - shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y - shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z + next_angle;
						else
							next_x := cordic_x + shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y + shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z - next_angle;
						end if;
						cordic_x <= next_x;
						cordic_y <= next_y;
						cordic_z <= next_z;
						if (cordic_iteration = 4 or cordic_iteration = 13 or
								cordic_iteration = 40) and repeat_iteration = '0' then
							repeat_iteration <= '1';
						elsif cordic_iteration = FRACTION_BITS then
							fractional_log := shift_left(resize(next_z,
								RESULT_WIDTH), 1);
							begin_log_combine(fractional_log, input_exponent);
						else
							repeat_iteration <= '0';
							cordic_iteration <= cordic_iteration + 1;
							if cordic_iteration < 31 then
								cordic_angle_address <= cordic_iteration + 1;
								state <= LOAD_CORDIC_ANGLE;
							elsif cordic_iteration = 31 then
								next_angle := (others => '0');
								next_angle(FRACTION_BITS - 32) := '1';
								cordic_shift_angle <= next_angle;
							else
								cordic_shift_angle <= shift_right(
									cordic_shift_angle, 1);
							end if;
						end if;

					when MULTIPLY_LN2 =>
						ln2_sum := ln2_accumulator;
						if ln2_multiplier(0) = '1' then
							ln2_sum := ln2_sum + ln2_multiplicand;
						end if;
						next_ln2 := ln2_sum;
						if ln2_index = 14 then
							if input_exponent < 0 then
								combined_log := log_fraction - signed(next_ln2);
							else
								combined_log := log_fraction + signed(next_ln2);
							end if;
							begin_fixed_result(combined_log);
						else
							ln2_accumulator <= next_ln2;
							ln2_multiplier <= shift_right(ln2_multiplier, 1);
							ln2_multiplicand <= shift_left(ln2_multiplicand, 1);
							ln2_index <= ln2_index + 1;
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

					when WRITE_PENDING_RESULT =>
						intermediate_class <= FPU_CLASS_NORMAL;
						intermediate_sign <= pending_sign;
						intermediate_exponent <= pending_exponent;
						intermediate_significand <= pending_significand;
						state <= COMPLETE;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
