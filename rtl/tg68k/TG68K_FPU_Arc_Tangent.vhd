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
		cordic_start : out std_logic;
		cordic_x_input : out signed(147 downto 0);
		cordic_y_input : out signed(147 downto 0);
		cordic_z_input : out signed(147 downto 0);
		cordic_z_result : in signed(147 downto 0);
		cordic_done : in std_logic;

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
	type arc_tangent_state_t is (IDLE, ALIGN_SOURCE,
		MULTIPLY_ARC_SINE_SOURCE,
		SQUARE_ROOT_ARC_SINE_COMPLEMENT, LOAD_CORDIC_ANGLE,
		WAIT_CORDIC,
		NORMALIZE_RESULT, COMPLETE);
	type source_alignment_target_t is
		(ALIGN_ARC_SINE, ALIGN_ARC_TANGENT_X, ALIGN_ARC_TANGENT_Y);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);

	constant PI_BY_TWO_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		unsigned'(x"1921FB54442D18469898CC51701B8");
	constant PI_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		shift_left(PI_BY_TWO_FIXED, 1);

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
	signal cordic_source_x : cordic_value_t := (others => '0');
	signal cordic_source_y : cordic_value_t := (others => '0');
	signal normalization_value : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalization_exponent : signed(16 downto 0) := (others => '0');
	signal source_alignment_target : source_alignment_target_t :=
		ALIGN_ARC_SINE;
	signal source_alignment_remaining : natural range 0 to FRACTION_BITS := 0;
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
	cordic_start <= '1' when state = LOAD_CORDIC_ANGLE else '0';
	cordic_x_input <= resize(cordic_source_x, 148);
	cordic_y_input <= resize(cordic_source_y, 148);
	cordic_z_input <= (others => '0');
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	base_exception_status <= base_status;

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
		variable selected_nan : fpu_extended_t;
		variable tiny_significand : fpu_significand_grs_t;
		variable square_accumulator_sum : unsigned(FRACTION_BITS + 1 downto 0);
		variable next_square_product : unsigned(2 * FRACTION_BITS + 2 downto 0);
		variable unit_square : unsigned(2 * FRACTION_BITS + 1 downto 0);
		variable shifted_remainder : unsigned(FRACTION_BITS + 2 downto 0);
		variable trial_divisor : unsigned(FRACTION_BITS + 2 downto 0);
		variable next_remainder : unsigned(FRACTION_BITS + 2 downto 0);
		variable next_root : unsigned(FRACTION_BITS downto 0);
		variable final_significand : fpu_significand_grs_t;
		variable next_normalization : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable next_exponent : signed(16 downto 0);
		variable next_square_multiplicand : unsigned(FRACTION_BITS downto 0);
		variable next_cordic_source : cordic_value_t;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				result_sign <= '0';
				arc_cosine_mode <= '0';
				cordic_source_x <= (others => '0');
				cordic_source_y <= (others => '0');
				normalization_value <= (others => '0');
				normalization_exponent <= (others => '0');
				source_alignment_target <= ALIGN_ARC_SINE;
				source_alignment_remaining <= 0;
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
										if source_exponent < -FRACTION_BITS then
											square_multiplicand <= (others => '0');
											square_product <= (others => '0');
											square_iteration <= 0;
											state <= MULTIPLY_ARC_SINE_SOURCE;
										else
											square_multiplicand <= shift_left(resize(
												source_significand, FRACTION_BITS + 1),
												FRACTION_BITS - 63);
											source_alignment_target <= ALIGN_ARC_SINE;
											source_alignment_remaining <= -source_exponent;
											state <= ALIGN_SOURCE;
										end if;
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
										if source_exponent > 0 then
											cordic_source_y <= signed(mantissa_value);
											if source_exponent <= FRACTION_BITS then
												cordic_source_x <= signed(unit_value);
												source_alignment_target <=
													ALIGN_ARC_TANGENT_X;
												source_alignment_remaining <= source_exponent;
												state <= ALIGN_SOURCE;
											else
												cordic_source_x <= (others => '0');
												state <= LOAD_CORDIC_ANGLE;
											end if;
										elsif source_exponent < 0 then
											cordic_source_x <= signed(unit_value);
											cordic_source_y <= signed(mantissa_value);
											source_alignment_target <= ALIGN_ARC_TANGENT_Y;
											source_alignment_remaining <= -source_exponent;
											state <= ALIGN_SOURCE;
										else
											cordic_source_x <= signed(unit_value);
											cordic_source_y <= signed(mantissa_value);
											state <= LOAD_CORDIC_ANGLE;
										end if;
									end if;
								end if;
							end if;
						end if;

					when ALIGN_SOURCE =>
						case source_alignment_target is
							when ALIGN_ARC_SINE =>
								next_square_multiplicand := shift_right(
									square_multiplicand, 1);
								square_multiplicand <= next_square_multiplicand;
								if source_alignment_remaining = 1 then
									square_product <= resize(next_square_multiplicand,
										2 * FRACTION_BITS + 3);
									square_iteration <= 0;
									state <= MULTIPLY_ARC_SINE_SOURCE;
								end if;
							when ALIGN_ARC_TANGENT_X =>
								next_cordic_source := shift_right(cordic_source_x, 1);
								cordic_source_x <= next_cordic_source;
								if source_alignment_remaining = 1 then
									state <= LOAD_CORDIC_ANGLE;
								end if;
							when ALIGN_ARC_TANGENT_Y =>
								next_cordic_source := shift_right(cordic_source_y, 1);
								cordic_source_y <= next_cordic_source;
								if source_alignment_remaining = 1 then
									state <= LOAD_CORDIC_ANGLE;
								end if;
						end case;
						if source_alignment_remaining > 1 then
							source_alignment_remaining <=
								source_alignment_remaining - 1;
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
							cordic_source_x <= signed(resize(next_root, CORDIC_WIDTH));
							cordic_source_y <= signed(resize(square_multiplicand,
								CORDIC_WIDTH));
							state <= LOAD_CORDIC_ANGLE;
						else
							root_iteration <= root_iteration + 1;
						end if;

					when LOAD_CORDIC_ANGLE =>
						state <= WAIT_CORDIC;

					when WAIT_CORDIC =>
						if cordic_done = '1' then
							if arc_cosine_mode = '1' then
								if result_sign = '1' then
									begin_fixed_angle(PI_BY_TWO_FIXED + unsigned(
										cordic_z_result(CORDIC_WIDTH - 1 downto 0)), '0');
								else
									begin_fixed_angle(PI_BY_TWO_FIXED - unsigned(
										cordic_z_result(CORDIC_WIDTH - 1 downto 0)), '0');
								end if;
							else
								begin_fixed_angle(unsigned(cordic_z_result(
									CORDIC_WIDTH - 1 downto 0)), result_sign);
							end if;
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
