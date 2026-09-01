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

entity TG68K_FPU_Exponential is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		exponential_base : in fpu_exponential_base_t;
		subtract_one : in std_logic;
		hyperbolic_sine : in std_logic := '0';
		hyperbolic_cosine : in std_logic := '0';
		hyperbolic_tangent : in std_logic := '0';
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

architecture rtl of TG68K_FPU_Exponential is
	constant FRACTION_BITS : natural := 96;
	constant CORDIC_WIDTH : natural := FRACTION_BITS + 4;
	constant FIXED_WIDTH : natural := FRACTION_BITS + 16;
	constant SERIES_WIDTH : natural := 197;
	constant ARITHMETIC_WIDTH : natural := SERIES_WIDTH;
	constant SERIES_NORMAL_BIT : natural := 195;
	constant SERIES_CUBIC_MAX_EXPONENT : integer := -26;
	constant SERIES_CUBIC_MIN_EXPONENT : integer := -32;
	constant SINH_TINY_MAX_EXPONENT : integer := -33;
	constant COSH_TINY_MAX_EXPONENT : integer := -34;
	constant TANH_TINY_MAX_EXPONENT : integer := -33;
	constant CUBE_SQUARE_LOW_BIT : natural := 112;
	constant CUBE_ALIGNMENT_BASE : integer := 118;
	constant NEGATIVE_REMAINDER_BOUND_BIT : natural := 118;
	type exponential_state_t is
		(IDLE, SQUARE_SMALL_ARGUMENT, CUBE_SMALL_ARGUMENT,
			DIVIDE_CUBE_TERM, SCALE_E_TO_BASE_TWO, SCALE_TEN_TO_BASE_TWO,
			MULTIPLY_LOG2, ROTATE_CORDIC_XY, ROTATE_CORDIC_Z,
			FINISH_CORDIC,
			ALIGN_HYPERBOLIC, NORMALIZE_HYPERBOLIC_TANGENT,
			DIVIDE_HYPERBOLIC_TANGENT, ALIGN_SUBTRACTION,
			NORMALIZE_SUBTRACTION, FORMAT_NORMALIZED_RESULT,
			WRITE_PENDING_RESULT, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 31) of cordic_value_t;

	constant LN2_FIXED : unsigned(FRACTION_BITS - 1 downto 0) :=
		x"B17217F7D1CF79ABC9E3B398";
	constant LOG2_E_FIXED : unsigned(FIXED_WIDTH downto 0) :=
		unsigned'("1" & x"71547652B82FE1777D0FFDA0D23A");
	constant LOG2_TEN_FIXED : unsigned(FIXED_WIDTH + 1 downto 0) :=
		unsigned'("11" & x"5269E12F346E2BF924AFDBFD36BF");
	constant CORDIC_INVERSE_GAIN : cordic_value_t :=
		signed'(x"1351E87200EEC232964A4EC8F");
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
	-- Quartus 17 otherwise implements this 100-bit table as a wide LUT mux.
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

	signal state : exponential_state_t := IDLE;
	signal fraction_register : unsigned(FRACTION_BITS - 1 downto 0) :=
		(others => '0');
	signal product_accumulator : unsigned(FRACTION_BITS downto 0) :=
		(others => '0');
	signal multiply_index : natural range 0 to FRACTION_BITS - 1 := 0;
	signal scale_magnitude_register : unsigned(FIXED_WIDTH - 1 downto 0) :=
		(others => '0');
	signal scale_accumulator : unsigned(FIXED_WIDTH + 2 downto 0) :=
		(others => '0');
	signal scale_index : natural range 0 to FIXED_WIDTH - 1 := 0;
	signal source_sign_latched : std_logic := '0';
	signal subtract_one_latched : std_logic := '0';
	signal hyperbolic_sine_latched : std_logic := '0';
	signal hyperbolic_cosine_latched : std_logic := '0';
	signal hyperbolic_tangent_latched : std_logic := '0';
	signal series_source_significand : unsigned(63 downto 0) :=
		(others => '0');
	signal series_exponent : signed(16 downto 0) := (others => '0');
	signal series_multiplier : unsigned(63 downto 0) := (others => '0');
	signal series_multiplicand : unsigned(127 downto 0) := (others => '0');
	signal series_product : unsigned(127 downto 0) := (others => '0');
	signal series_index : natural range 0 to 79 := 0;
	signal cube_accumulator : unsigned(79 downto 0) := (others => '0');
	signal cube_remainder : natural range 0 to 5 := 0;
	signal subtraction_value : unsigned(CORDIC_WIDTH downto 0) :=
		(others => '0');
	signal subtraction_one : unsigned(CORDIC_WIDTH downto 0) :=
		(others => '0');
	signal subtraction_exponent : signed(16 downto 0) := (others => '0');
	signal subtraction_shift_count : natural range 0 to CORDIC_WIDTH := 0;
	signal subtraction_sticky : std_logic := '0';
	signal tangent_quotient : unsigned(65 downto 0) := (others => '0');
	signal tangent_iteration : natural range 0 to 64 := 0;
	signal pending_sign : std_logic := '0';
	signal pending_exponent : signed(16 downto 0) := (others => '0');
	signal pending_significand : fpu_significand_grs_t := (others => '0');
	signal result_exponent : signed(16 downto 0) := (others => '0');
	signal cordic_x : cordic_value_t := (others => '0');
	signal cordic_y : cordic_value_t := (others => '0');
	signal cordic_z : cordic_value_t := (others => '0');
	signal cordic_iteration : natural range 1 to FRACTION_BITS := 1;
	signal repeat_iteration : std_logic := '0';
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal cordic_angle_address : natural range 1 to 31 := 1;
	signal cordic_z_previous : cordic_value_t := (others => '0');
	signal cordic_angle_previous : cordic_value_t := (others => '0');
	signal cordic_direction_previous : std_logic := '0';
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
		series_multiplicand, cube_accumulator, scale_accumulator,
		scale_magnitude_register, scale_index, product_accumulator,
		fraction_register, multiply_index, cordic_x, cordic_y, cordic_z,
		cordic_iteration, cordic_z_previous, cordic_angle_previous,
		cordic_direction_previous, subtraction_value, subtraction_one)
		variable shifted_remainder : unsigned(CORDIC_WIDTH downto 0);
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
			when SCALE_E_TO_BASE_TWO =>
				arithmetic_left_a <= resize(scale_accumulator,
					ARITHMETIC_WIDTH);
				if scale_magnitude_register(scale_index) = '1' then
					arithmetic_right_a <= resize(LOG2_E_FIXED,
						ARITHMETIC_WIDTH);
				end if;
			when SCALE_TEN_TO_BASE_TWO =>
				arithmetic_left_a <= resize(scale_accumulator,
					ARITHMETIC_WIDTH);
				if scale_magnitude_register(scale_index) = '1' then
					arithmetic_right_a <= resize(LOG2_TEN_FIXED,
						ARITHMETIC_WIDTH);
				end if;
			when MULTIPLY_LOG2 =>
				arithmetic_left_a <= resize(product_accumulator,
					ARITHMETIC_WIDTH);
				if fraction_register(multiply_index) = '1' then
					arithmetic_right_a <= resize(LN2_FIXED,
						ARITHMETIC_WIDTH);
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
				if cordic_z < 0 then
					arithmetic_subtract_a <= '1';
					arithmetic_subtract_b <= '1';
				end if;
			when ROTATE_CORDIC_Z =>
				arithmetic_left_a <= unsigned(resize(cordic_z_previous,
					ARITHMETIC_WIDTH));
				arithmetic_right_a <= unsigned(resize(cordic_angle_previous,
					ARITHMETIC_WIDTH));
				arithmetic_subtract_a <= cordic_direction_previous;
			when NORMALIZE_HYPERBOLIC_TANGENT =>
				arithmetic_left_a <= resize(subtraction_value,
					ARITHMETIC_WIDTH);
				if subtraction_value >= subtraction_one then
					arithmetic_right_a <= resize(subtraction_one,
						ARITHMETIC_WIDTH);
					arithmetic_subtract_a <= '1';
				end if;
			when DIVIDE_HYPERBOLIC_TANGENT =>
				shifted_remainder := shift_left(subtraction_value, 1);
				arithmetic_left_a <= resize(shifted_remainder,
					ARITHMETIC_WIDTH);
				if shifted_remainder >= subtraction_one then
					arithmetic_right_a <= resize(subtraction_one,
						ARITHMETIC_WIDTH);
					arithmetic_subtract_a <= '1';
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

	exponential_sequence : process(clk)
		procedure format_normalized_result(
				constant normalized_value : in unsigned(CORDIC_WIDTH downto 0);
				constant normalized_exponent : in signed(16 downto 0);
				constant normalized_sign : in std_logic;
				constant prior_sticky : in std_logic) is
		begin
			subtraction_value <= normalized_value;
			subtraction_exponent <= normalized_exponent;
			intermediate_sign <= normalized_sign;
			subtraction_sticky <= prior_sticky;
			state <= FORMAT_NORMALIZED_RESULT;
		end procedure;

		procedure complete_subtraction(
				constant difference : in unsigned(CORDIC_WIDTH downto 0);
				constant difference_exponent : in signed(16 downto 0);
				constant difference_sign : in std_logic;
				constant prior_sticky : in std_logic) is
		begin
			format_normalized_result(difference, difference_exponent,
				difference_sign, prior_sticky);
		end procedure;

		procedure complete_hyperbolic_sine(
				constant positive_exponential : in unsigned(CORDIC_WIDTH downto 0);
				constant reciprocal_exponential : in unsigned(CORDIC_WIDTH downto 0);
				constant binary_exponent : in signed(16 downto 0);
				constant prior_sticky : in std_logic) is
			variable difference : unsigned(CORDIC_WIDTH downto 0);
			variable result_exponent_value : signed(16 downto 0);
			variable exponent_integer : integer range 0 to 65535;
		begin
			exponent_integer := to_integer(binary_exponent);
			if exponent_integer > CORDIC_WIDTH / 2 then
				difference := positive_exponential - 1;
				complete_subtraction(difference, binary_exponent - 1,
					source_sign_latched, '1');
			elsif exponent_integer = 0 then
				difference := positive_exponential - reciprocal_exponential;
				result_exponent_value := binary_exponent - 1;
				if difference(FRACTION_BITS) = '1' then
					complete_subtraction(difference, result_exponent_value,
						source_sign_latched, prior_sticky);
				else
					subtraction_value <= difference;
					subtraction_exponent <= result_exponent_value;
					subtraction_sticky <= prior_sticky;
					intermediate_sign <= source_sign_latched;
					state <= NORMALIZE_SUBTRACTION;
				end if;
			else
				subtraction_value <= positive_exponential;
				subtraction_one <= reciprocal_exponential;
				subtraction_exponent <= binary_exponent - 1;
				subtraction_shift_count <= 2 * exponent_integer;
				subtraction_sticky <= prior_sticky;
				intermediate_sign <= source_sign_latched;
				state <= ALIGN_HYPERBOLIC;
			end if;
		end procedure;

		procedure complete_hyperbolic_sum(
				constant sum : in unsigned(CORDIC_WIDTH downto 0);
				constant sum_exponent : in signed(16 downto 0);
				constant prior_sticky : in std_logic) is
			variable normalized_sum : unsigned(CORDIC_WIDTH downto 0);
			variable normalized_exponent : signed(16 downto 0);
			variable final_sticky : std_logic;
		begin
			normalized_sum := sum;
			normalized_exponent := sum_exponent;
			final_sticky := prior_sticky;
			if normalized_sum(FRACTION_BITS + 1) = '1' then
				final_sticky := final_sticky or normalized_sum(0);
				normalized_sum := shift_right(normalized_sum, 1);
				normalized_exponent := normalized_exponent + 1;
			end if;
			format_normalized_result(normalized_sum, normalized_exponent,
				'0', final_sticky);
		end procedure;

		procedure complete_hyperbolic_cosine(
				constant positive_exponential : in unsigned(CORDIC_WIDTH downto 0);
				constant reciprocal_exponential : in unsigned(CORDIC_WIDTH downto 0);
				constant binary_exponent : in signed(16 downto 0);
				constant prior_sticky : in std_logic) is
			variable sum : unsigned(CORDIC_WIDTH downto 0);
			variable exponent_integer : integer range 0 to 65535;
		begin
			exponent_integer := to_integer(binary_exponent);
			if exponent_integer > CORDIC_WIDTH / 2 then
				complete_hyperbolic_sum(positive_exponential,
					binary_exponent - 1, '1');
			elsif exponent_integer = 0 then
				sum := positive_exponential + reciprocal_exponential;
				complete_hyperbolic_sum(sum, binary_exponent - 1,
					prior_sticky);
			else
				subtraction_value <= positive_exponential;
				subtraction_one <= reciprocal_exponential;
				subtraction_exponent <= binary_exponent - 1;
				subtraction_shift_count <= 2 * exponent_integer;
				subtraction_sticky <= prior_sticky;
				state <= ALIGN_HYPERBOLIC;
			end if;
		end procedure;

		procedure begin_hyperbolic_tangent_division(
				constant numerator : in unsigned(CORDIC_WIDTH downto 0);
				constant denominator : in unsigned(CORDIC_WIDTH downto 0);
				constant prior_sticky : in std_logic) is
		begin
			subtraction_value <= numerator;
			subtraction_one <= denominator;
			subtraction_exponent <= (others => '0');
			subtraction_sticky <= prior_sticky;
			intermediate_sign <= source_sign_latched;
			state <= NORMALIZE_HYPERBOLIC_TANGENT;
		end procedure;

		procedure complete_hyperbolic_tangent(
				constant positive_exponential : in unsigned(CORDIC_WIDTH downto 0);
				constant reciprocal_exponential : in unsigned(CORDIC_WIDTH downto 0);
				constant binary_exponent : in signed(16 downto 0);
				constant prior_sticky : in std_logic) is
			variable numerator : unsigned(CORDIC_WIDTH downto 0);
			variable denominator : unsigned(CORDIC_WIDTH downto 0);
			variable exponent_integer : integer range 0 to 65535;
		begin
			exponent_integer := to_integer(binary_exponent);
			if exponent_integer > CORDIC_WIDTH / 2 then
				intermediate_class <= FPU_CLASS_NORMAL;
				intermediate_sign <= source_sign_latched;
				intermediate_exponent <= to_signed(-1, 17);
				intermediate_significand <= (others => '1');
				state <= COMPLETE;
			elsif exponent_integer = 0 then
				numerator := positive_exponential - reciprocal_exponential;
				denominator := positive_exponential + reciprocal_exponential;
				begin_hyperbolic_tangent_division(numerator, denominator,
					prior_sticky);
			else
				subtraction_value <= positive_exponential;
				subtraction_one <= reciprocal_exponential;
				subtraction_exponent <= binary_exponent;
				subtraction_shift_count <= 2 * exponent_integer;
				subtraction_sticky <= prior_sticky;
				intermediate_sign <= source_sign_latched;
				state <= ALIGN_HYPERBOLIC;
			end if;
		end procedure;

		procedure complete_exponential(
			constant exponential_significand : in unsigned(CORDIC_WIDTH downto 0);
			constant exponential_exponent : in signed(16 downto 0);
			constant minus_one : in std_logic) is
			variable normalized_value : unsigned(CORDIC_WIDTH downto 0);
			variable normalized_exponent : signed(16 downto 0);
			variable one_value : unsigned(CORDIC_WIDTH downto 0);
			variable difference_value : unsigned(CORDIC_WIDTH downto 0);
			variable final_significand : fpu_significand_grs_t;
			variable exponent_integer : integer range -65536 to 65535;
		begin
			normalized_value := exponential_significand;
			normalized_exponent := exponential_exponent;
			if normalized_value(FRACTION_BITS + 1) = '1' then
				normalized_value := shift_right(normalized_value, 1);
				normalized_exponent := exponential_exponent + 1;
			elsif normalized_value(FRACTION_BITS) = '0' then
				normalized_value := shift_left(normalized_value, 1);
				normalized_exponent := exponential_exponent - 1;
			end if;

			if minus_one = '0' then
				final_significand := (others => '0');
				final_significand(66 downto 3) := normalized_value(
					FRACTION_BITS downto FRACTION_BITS - 63);
				final_significand(2) := normalized_value(FRACTION_BITS - 64);
				final_significand(1) := normalized_value(FRACTION_BITS - 65);
				final_significand(0) := or_reduce(normalized_value(
					FRACTION_BITS - 66 downto 0));
				intermediate_class <= FPU_CLASS_NORMAL;
				intermediate_sign <= '0';
				intermediate_exponent <= normalized_exponent;
				intermediate_significand <= final_significand;
				state <= COMPLETE;
				return;
			end if;

			one_value := (others => '0');
			one_value(FRACTION_BITS) := '1';
			exponent_integer := to_integer(normalized_exponent);
			if exponent_integer < 0 then
				intermediate_sign <= '1';
				if -exponent_integer > FRACTION_BITS then
					pending_sign <= '1';
					pending_exponent <= to_signed(-1, 17);
					pending_significand <= (others => '1');
					state <= WRITE_PENDING_RESULT;
				else
					subtraction_value <= normalized_value;
					subtraction_one <= one_value;
					subtraction_exponent <= (others => '0');
					subtraction_shift_count <= -exponent_integer;
					subtraction_sticky <= '0';
					state <= ALIGN_SUBTRACTION;
				end if;
			else
				intermediate_sign <= '0';
				if exponent_integer > FRACTION_BITS then
					complete_subtraction(normalized_value,
						normalized_exponent, '0', '1');
				elsif exponent_integer = 0 then
					difference_value := normalized_value - one_value;
					if difference_value(FRACTION_BITS) = '1' then
						complete_subtraction(difference_value,
							normalized_exponent, '0', '0');
					else
						subtraction_value <= difference_value;
						subtraction_exponent <= normalized_exponent;
						subtraction_sticky <= '0';
						state <= NORMALIZE_SUBTRACTION;
					end if;
				else
					subtraction_value <= normalized_value;
					subtraction_one <= one_value;
					subtraction_exponent <= normalized_exponent;
					subtraction_shift_count <= exponent_integer;
					subtraction_sticky <= '0';
					state <= ALIGN_SUBTRACTION;
				end if;
			end if;
		end procedure;

		procedure begin_reduced_exponential(
			constant magnitude : in unsigned(FIXED_WIDTH - 1 downto 0);
			constant sign_value : in std_logic;
			constant minus_one : in std_logic) is
			variable integer_magnitude : natural range 0 to 65535;
			variable fraction_value : unsigned(FRACTION_BITS - 1 downto 0);
			variable exponent_value : integer range -65536 to 65535;
			variable unit_value : unsigned(CORDIC_WIDTH downto 0);
		begin
			integer_magnitude := to_integer(magnitude(
				FIXED_WIDTH - 1 downto FRACTION_BITS));
			fraction_value := magnitude(FRACTION_BITS - 1 downto 0);
			if sign_value = '0' then
				exponent_value := integer_magnitude;
			else
				if fraction_value = 0 then
					exponent_value := -integer_magnitude;
				else
					exponent_value := -(integer_magnitude + 1);
					fraction_value := (not fraction_value) + 1;
				end if;
			end if;
			result_exponent <= to_signed(exponent_value, 17);
			base_status(1) <= '1';
			if fraction_value = 0 then
				unit_value := (others => '0');
				unit_value(FRACTION_BITS) := '1';
				if hyperbolic_sine_latched = '1' then
					complete_hyperbolic_sine(unit_value, unit_value,
						to_signed(exponent_value, 17), '0');
				elsif hyperbolic_cosine_latched = '1' then
					complete_hyperbolic_cosine(unit_value, unit_value,
						to_signed(exponent_value, 17), '0');
				elsif hyperbolic_tangent_latched = '1' then
					complete_hyperbolic_tangent(unit_value, unit_value,
						to_signed(exponent_value, 17), '0');
				else
					complete_exponential(unit_value,
						to_signed(exponent_value, 17), minus_one);
				end if;
			else
				fraction_register <= fraction_value;
				product_accumulator <= (others => '0');
				multiply_index <= 0;
				state <= MULTIPLY_LOG2;
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
		variable shift_amount : integer range -65536 to 65535;
		variable magnitude_fixed : unsigned(FIXED_WIDTH - 1 downto 0);
		variable exponent_value : integer range -65536 to 65535;
		variable selected_nan : fpu_extended_t;
		variable next_accumulator : unsigned(FRACTION_BITS downto 0);
		variable next_scale : unsigned(FIXED_WIDTH + 2 downto 0);
		variable next_angle : cordic_value_t;
		variable cordic_sum : signed(CORDIC_WIDTH downto 0);
		variable cordic_difference : signed(CORDIC_WIDTH downto 0);
		variable unit_result : unsigned(CORDIC_WIDTH downto 0);
		variable next_square : unsigned(127 downto 0);
		variable next_cube : unsigned(79 downto 0);
		variable next_cube_quotient : unsigned(79 downto 0);
		variable division_trial : natural range 0 to 11;
		variable cube_divisor : natural range 3 to 6;
		variable next_subtraction : unsigned(CORDIC_WIDTH downto 0);
		variable next_subtraction_one : unsigned(CORDIC_WIDTH downto 0);
		variable subtraction_difference : unsigned(CORDIC_WIDTH downto 0);
		variable next_subtraction_sticky : std_logic;
		variable next_subtraction_exponent : signed(16 downto 0);
		variable tangent_shifted_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable tangent_next_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable tangent_next_quotient : unsigned(65 downto 0);
		variable series_base : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_correction : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_cube_correction : unsigned(SERIES_WIDTH - 1 downto 0);
		variable series_value : unsigned(SERIES_WIDTH - 1 downto 0);
		variable tiny_significand : fpu_significand_grs_t;
		variable cosh_increment : fpu_significand_grs_t;
		variable series_shift : natural range 1 to 42;
		variable cube_alignment_shift : natural range 54 to 66;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				fraction_register <= (others => '0');
				product_accumulator <= (others => '0');
				multiply_index <= 0;
				scale_magnitude_register <= (others => '0');
				scale_accumulator <= (others => '0');
				scale_index <= 0;
				source_sign_latched <= '0';
				subtract_one_latched <= '0';
				hyperbolic_sine_latched <= '0';
				hyperbolic_cosine_latched <= '0';
				hyperbolic_tangent_latched <= '0';
				series_source_significand <= (others => '0');
				series_exponent <= (others => '0');
				series_multiplier <= (others => '0');
				series_multiplicand <= (others => '0');
				series_product <= (others => '0');
				series_index <= 0;
				cube_accumulator <= (others => '0');
				cube_remainder <= 0;
				subtraction_value <= (others => '0');
				subtraction_one <= (others => '0');
				subtraction_exponent <= (others => '0');
				subtraction_shift_count <= 0;
				subtraction_sticky <= '0';
				tangent_quotient <= (others => '0');
				tangent_iteration <= 0;
				pending_sign <= '0';
				pending_exponent <= (others => '0');
				pending_significand <= (others => '0');
				result_exponent <= (others => '0');
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
							selected_nan := source;
							selected_nan(62) := '1';
							fraction_register <= (others => '0');
							product_accumulator <= (others => '0');
							multiply_index <= 0;
							scale_magnitude_register <= (others => '0');
							scale_accumulator <= (others => '0');
							scale_index <= 0;
							source_sign_latched <= source(79);
							subtract_one_latched <= subtract_one;
							hyperbolic_sine_latched <= hyperbolic_sine;
							hyperbolic_cosine_latched <= hyperbolic_cosine;
							hyperbolic_tangent_latched <= hyperbolic_tangent;
							series_source_significand <= (others => '0');
							series_exponent <= (others => '0');
							series_multiplier <= (others => '0');
							series_multiplicand <= (others => '0');
							series_product <= (others => '0');
							series_index <= 0;
							cube_accumulator <= (others => '0');
							cube_remainder <= 0;
							subtraction_value <= (others => '0');
							subtraction_one <= (others => '0');
							subtraction_exponent <= (others => '0');
							subtraction_shift_count <= 0;
							subtraction_sticky <= '0';
							tangent_quotient <= (others => '0');
							tangent_iteration <= 0;
							pending_sign <= '0';
							pending_exponent <= (others => '0');
							pending_significand <= (others => '0');
							result_exponent <= (others => '0');
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
								if subtract_one = '1' or hyperbolic_sine = '1' or
										hyperbolic_tangent = '1' then
									intermediate_class <= FPU_CLASS_ZERO;
									intermediate_sign <= source(79);
								else
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_significand(66) <= '1';
								end if;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								if hyperbolic_tangent = '1' then
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_sign <= source(79);
									intermediate_significand(66) <= '1';
								elsif hyperbolic_cosine = '1' then
									intermediate_class <= FPU_CLASS_INFINITY;
								elsif hyperbolic_sine = '1' then
									intermediate_class <= FPU_CLASS_INFINITY;
									intermediate_sign <= source(79);
								elsif subtract_one = '1' and source(79) = '1' then
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_sign <= '1';
									intermediate_significand(66) <= '1';
								elsif source(79) = '1' then
									intermediate_class <= FPU_CLASS_ZERO;
								else
									intermediate_class <= FPU_CLASS_INFINITY;
								end if;
								state <= COMPLETE;
							else
								source_exponent := fpu_unbiased_exponent(source);
								normalization_shift :=
									63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									normalization_shift);
								source_exponent := source_exponent -
									normalization_shift;
								if hyperbolic_tangent = '1' and
										source_exponent <= SERIES_CUBIC_MAX_EXPONENT then
									base_status(1) <= '1';
									if source_exponent <= TANH_TINY_MAX_EXPONENT then
										tiny_significand := shift_left(resize(
											source_significand, 67), 3) - 1;
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
										series_multiplicand <= resize(source_significand, 128);
										series_product <= (others => '0');
										series_index <= 0;
										state <= SQUARE_SMALL_ARGUMENT;
									end if;
								elsif hyperbolic_cosine = '1' and
										source_exponent <= SERIES_CUBIC_MAX_EXPONENT then
									base_status(1) <= '1';
									if source_exponent <= COSH_TINY_MAX_EXPONENT then
										intermediate_class <= FPU_CLASS_NORMAL;
										intermediate_significand(66) <= '1';
										intermediate_significand(0) <= '1';
										state <= COMPLETE;
									else
										series_source_significand <= source_significand;
										series_exponent <= to_signed(source_exponent, 17);
										series_multiplier <= source_significand;
										series_multiplicand <= resize(source_significand, 128);
										series_product <= (others => '0');
										series_index <= 0;
										state <= SQUARE_SMALL_ARGUMENT;
									end if;
								elsif (subtract_one = '1' or hyperbolic_sine = '1') and
										source_exponent <= SERIES_CUBIC_MAX_EXPONENT then
									base_status(1) <= '1';
									if hyperbolic_sine = '1' and
											source_exponent <= SINH_TINY_MAX_EXPONENT then
										tiny_significand := shift_left(resize(
											source_significand, 67), 3) + 1;
										intermediate_class <= FPU_CLASS_NORMAL;
										intermediate_sign <= source(79);
										intermediate_exponent <= to_signed(
											source_exponent, 17);
										intermediate_significand <= tiny_significand;
										state <= COMPLETE;
									elsif hyperbolic_sine = '0' and source_exponent < -67 then
										tiny_significand := shift_left(resize(
											source_significand, 67), 3);
										if source(79) = '0' then
											tiny_significand := tiny_significand + 1;
										else
											tiny_significand := tiny_significand - 1;
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
										series_multiplicand <= resize(source_significand, 128);
										series_product <= (others => '0');
										series_index <= 0;
										state <= SQUARE_SMALL_ARGUMENT;
									end if;
								else
									magnitude_fixed := (others => '0');
									shift_amount := source_exponent + FRACTION_BITS - 63;
									if (exponential_base = FPU_EXP_BASE_TWO and
											source_exponent > 15) or
											(exponential_base = FPU_EXP_BASE_E and
											source_exponent > 13) or
											(exponential_base = FPU_EXP_BASE_TEN and
											source_exponent > 12) then
										intermediate_class <= FPU_CLASS_NORMAL;
										base_status(1) <= '1';
										if hyperbolic_tangent = '1' then
											intermediate_sign <= source(79);
											intermediate_exponent <= to_signed(-1, 17);
											intermediate_significand <= (others => '1');
										elsif hyperbolic_sine = '1' then
											intermediate_sign <= source(79);
											exponent_value := 65535;
											intermediate_exponent <= to_signed(
												exponent_value, 17);
											intermediate_significand(66) <= '1';
										elsif hyperbolic_cosine = '1' then
											exponent_value := 65535;
											intermediate_exponent <= to_signed(
												exponent_value, 17);
											intermediate_significand(66) <= '1';
										elsif subtract_one = '1' and source(79) = '1' then
											intermediate_sign <= '1';
											intermediate_exponent <= to_signed(-1, 17);
											intermediate_significand <= (others => '1');
										else
											if source(79) = '1' then
												exponent_value := -65536;
											else
												exponent_value := 65535;
											end if;
											intermediate_exponent <= to_signed(
												exponent_value, 17);
											intermediate_significand(66) <= '1';
										end if;
										state <= COMPLETE;
									else
										if shift_amount >= 0 then
											magnitude_fixed := shift_left(resize(
												source_significand, FIXED_WIDTH), shift_amount);
										elsif -shift_amount < FIXED_WIDTH then
											magnitude_fixed := shift_right(resize(
												source_significand, FIXED_WIDTH), -shift_amount);
										end if;
										if magnitude_fixed = 0 then
											intermediate_class <= FPU_CLASS_NORMAL;
											base_status(1) <= '1';
											if hyperbolic_cosine = '1' then
												intermediate_significand(66) <= '1';
												intermediate_significand(0) <= '1';
											elsif source(79) = '0' then
												intermediate_significand(66) <= '1';
												intermediate_significand(0) <= '1';
											else
												intermediate_exponent <= to_signed(-1, 17);
												intermediate_significand <= (others => '1');
											end if;
											state <= COMPLETE;
										else
											if hyperbolic_sine = '1' or
													hyperbolic_cosine = '1' or
													hyperbolic_tangent = '1' or
													exponential_base = FPU_EXP_BASE_E then
												scale_magnitude_register <= magnitude_fixed;
												scale_accumulator <= (others => '0');
												scale_index <= 0;
												state <= SCALE_E_TO_BASE_TWO;
											elsif exponential_base = FPU_EXP_BASE_TEN then
												scale_magnitude_register <= magnitude_fixed;
												scale_accumulator <= (others => '0');
												scale_index <= 0;
												state <= SCALE_TEN_TO_BASE_TWO;
											else
												begin_reduced_exponential(
													magnitude_fixed, source(79), subtract_one);
											end if;
										end if;
									end if;
								end if;
							end if;
						end if;

					when SQUARE_SMALL_ARGUMENT =>
						next_square := arithmetic_result_a(127 downto 0);
						if series_index = 63 then
							series_product <= next_square;
							if hyperbolic_cosine_latched = '1' then
								cosh_increment := (others => '0');
								-- Align x^2/2 to GRS bit 66. Higher-order terms are
								-- positive and below sticky throughout this range.
								case to_integer(series_exponent) is
									when -26 =>
										cosh_increment(14 downto 0) :=
											next_square(127 downto 113);
									when -27 =>
										cosh_increment(12 downto 0) :=
											next_square(127 downto 115);
									when -28 =>
										cosh_increment(10 downto 0) :=
											next_square(127 downto 117);
									when -29 =>
										cosh_increment(8 downto 0) :=
											next_square(127 downto 119);
									when -30 =>
										cosh_increment(6 downto 0) :=
											next_square(127 downto 121);
									when -31 =>
										cosh_increment(4 downto 0) :=
											next_square(127 downto 123);
									when -32 =>
										cosh_increment(2 downto 0) :=
											next_square(127 downto 125);
									when -33 =>
										cosh_increment(0) := next_square(127);
									when others =>
										null;
								end case;
								cosh_increment(0) := '1';
								cosh_increment(66) := '1';
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_significand <= cosh_increment;
								state <= COMPLETE;
							else
								series_base := shift_left(resize(
									series_source_significand, SERIES_WIDTH),
									SERIES_NORMAL_BIT - 63);
								series_shift := to_integer(series_exponent) + 68;
								series_correction := shift_left(resize(
									next_square, SERIES_WIDTH), series_shift);
								if to_integer(series_exponent) <
										SERIES_CUBIC_MIN_EXPONENT then
									if source_sign_latched = '0' then
										series_value := series_base + series_correction;
									else
										series_value := series_base - series_correction;
									end if;
									complete_small_series(series_value);
								else
									series_multiplier <= series_source_significand;
									-- The discarded square bits are below sticky throughout
									-- the bounded cubic range.
									series_multiplicand <= resize(next_square(
										127 downto CUBE_SQUARE_LOW_BIT), 128);
									cube_accumulator <= (others => '0');
									series_index <= 0;
									state <= CUBE_SMALL_ARGUMENT;
								end if;
							end if;
						else
							series_product <= next_square;
							series_multiplier <= shift_right(series_multiplier, 1);
							series_multiplicand <= shift_left(
								series_multiplicand, 1);
							series_index <= series_index + 1;
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
						if hyperbolic_tangent_latched = '1' then
							cube_divisor := 3;
						else
							cube_divisor := 6;
						end if;
						division_trial := cube_remainder * 2;
						if series_multiplicand(79 - series_index) = '1' then
							division_trial := division_trial + 1;
						end if;
						next_cube_quotient := cube_accumulator;
						if division_trial >= cube_divisor then
							next_cube_quotient(79 - series_index) := '1';
							division_trial := division_trial - cube_divisor;
						end if;
						if series_index = 79 then
							series_base := shift_left(resize(
								series_source_significand, SERIES_WIDTH),
								SERIES_NORMAL_BIT - 63);
							series_shift := to_integer(series_exponent) + 68;
							series_correction := shift_left(resize(
								series_product, SERIES_WIDTH), series_shift);
							cube_alignment_shift := 2 *
								to_integer(series_exponent) + CUBE_ALIGNMENT_BASE;
							series_cube_correction := shift_left(resize(
								next_cube_quotient, SERIES_WIDTH),
								cube_alignment_shift);
							if hyperbolic_tangent_latched = '1' then
								if division_trial = 0 then
									series_value := series_base -
										series_cube_correction + 1;
								else
									series_value := series_base -
										series_cube_correction - 1;
								end if;
							elsif hyperbolic_sine_latched = '1' then
								series_value := series_base + series_cube_correction;
							elsif source_sign_latched = '0' then
								series_value := series_base + series_correction +
									series_cube_correction;
							else
								-- Bias below the alternating fourth-order remainder;
								-- sticky then represents the exact negative magnitude.
								series_value := series_base - series_correction +
									series_cube_correction -
									shift_left(to_unsigned(1, SERIES_WIDTH),
										NEGATIVE_REMAINDER_BOUND_BIT);
							end if;
							complete_small_series(series_value);
						else
							cube_accumulator <= next_cube_quotient;
							cube_remainder <= division_trial;
							series_index <= series_index + 1;
						end if;

					when SCALE_E_TO_BASE_TWO | SCALE_TEN_TO_BASE_TWO =>
						next_scale := shift_right(arithmetic_result_a(
							FIXED_WIDTH + 2 downto 0), 1);
						scale_accumulator <= next_scale;
						if scale_index = FIXED_WIDTH - 1 then
							if hyperbolic_sine_latched = '1' or
									hyperbolic_cosine_latched = '1' or
									hyperbolic_tangent_latched = '1' then
								begin_reduced_exponential(next_scale(
									FIXED_WIDTH - 1 downto 0), '0', '0');
							else
								begin_reduced_exponential(next_scale(
									FIXED_WIDTH - 1 downto 0), source_sign_latched,
									subtract_one_latched);
							end if;
						else
							scale_index <= scale_index + 1;
						end if;

					when MULTIPLY_LOG2 =>
						next_accumulator := shift_right(arithmetic_result_a(
							FRACTION_BITS downto 0), 1);
						product_accumulator <= next_accumulator;
						if multiply_index = FRACTION_BITS - 1 then
							if next_accumulator = 0 then
								unit_result := (others => '0');
								unit_result(FRACTION_BITS) := '1';
								if hyperbolic_sine_latched = '1' then
									complete_hyperbolic_sine(unit_result, unit_result,
										result_exponent, '1');
								elsif hyperbolic_cosine_latched = '1' then
									complete_hyperbolic_cosine(unit_result, unit_result,
										result_exponent, '1');
								elsif hyperbolic_tangent_latched = '1' then
									complete_hyperbolic_tangent(unit_result, unit_result,
										result_exponent, '1');
								else
									if subtract_one_latched = '0' then
										unit_result(0) := '1';
									end if;
									complete_exponential(unit_result, result_exponent,
										subtract_one_latched);
								end if;
							else
								cordic_x <= CORDIC_INVERSE_GAIN;
								cordic_y <= (others => '0');
								cordic_z <= signed(resize(next_accumulator,
									CORDIC_WIDTH));
								cordic_iteration <= 1;
								repeat_iteration <= '0';
								cordic_angle_address <= 1;
								state <= ROTATE_CORDIC_XY;
							end if;
						else
							multiply_index <= multiply_index + 1;
						end if;

					when ROTATE_CORDIC_XY =>
						if cordic_iteration <= 31 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						cordic_z_previous <= cordic_z;
						cordic_angle_previous <= next_angle;
						if cordic_z >= 0 then
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
							CORDIC_WIDTH - 1 downto 0));
						-- Hyperbolic CORDIC repeats these iterations to converge.
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
						cordic_sum := resize(cordic_x, CORDIC_WIDTH + 1) +
							resize(cordic_y, CORDIC_WIDTH + 1);
						if hyperbolic_sine_latched = '1' then
							cordic_difference := resize(cordic_x, CORDIC_WIDTH + 1) -
								resize(cordic_y, CORDIC_WIDTH + 1);
							complete_hyperbolic_sine(unsigned(cordic_sum),
								unsigned(cordic_difference), result_exponent, '0');
						elsif hyperbolic_cosine_latched = '1' then
							cordic_difference := resize(cordic_x, CORDIC_WIDTH + 1) -
								resize(cordic_y, CORDIC_WIDTH + 1);
							complete_hyperbolic_cosine(unsigned(cordic_sum),
								unsigned(cordic_difference), result_exponent, '0');
						elsif hyperbolic_tangent_latched = '1' then
							cordic_difference := resize(cordic_x, CORDIC_WIDTH + 1) -
								resize(cordic_y, CORDIC_WIDTH + 1);
							complete_hyperbolic_tangent(unsigned(cordic_sum),
								unsigned(cordic_difference), result_exponent, '0');
						else
							complete_exponential(unsigned(cordic_sum), result_exponent,
								subtract_one_latched);
						end if;

					when ALIGN_HYPERBOLIC =>
						next_subtraction_one := shift_right(subtraction_one, 1);
						next_subtraction_sticky := subtraction_sticky or
							subtraction_one(0);
						if subtraction_shift_count = 1 then
							if (hyperbolic_sine_latched = '1' or
									hyperbolic_tangent_latched = '1') and
									next_subtraction_sticky = '1' then
								next_subtraction_one := next_subtraction_one + 1;
							end if;
							if hyperbolic_cosine_latched = '1' then
								subtraction_difference := subtraction_value +
									next_subtraction_one;
								complete_hyperbolic_sum(subtraction_difference,
									subtraction_exponent, next_subtraction_sticky);
							elsif hyperbolic_tangent_latched = '1' then
								subtraction_difference := subtraction_value -
									next_subtraction_one;
								next_subtraction := subtraction_value +
									next_subtraction_one;
								begin_hyperbolic_tangent_division(
									subtraction_difference, next_subtraction,
									next_subtraction_sticky);
							else
								subtraction_difference := subtraction_value -
									next_subtraction_one;
								if subtraction_difference(FRACTION_BITS) = '1' then
									complete_subtraction(subtraction_difference,
										subtraction_exponent, intermediate_sign,
										next_subtraction_sticky);
								else
									subtraction_value <= subtraction_difference;
									subtraction_sticky <= next_subtraction_sticky;
									state <= NORMALIZE_SUBTRACTION;
								end if;
							end if;
						else
							subtraction_one <= next_subtraction_one;
							subtraction_shift_count <= subtraction_shift_count - 1;
							subtraction_sticky <= next_subtraction_sticky;
						end if;

					when NORMALIZE_HYPERBOLIC_TANGENT =>
						if subtraction_value >= subtraction_one then
							subtraction_value <= arithmetic_result_a(
								CORDIC_WIDTH downto 0);
							tangent_quotient <= (0 => '1', others => '0');
							tangent_iteration <= 0;
							intermediate_class <= FPU_CLASS_NORMAL;
							intermediate_exponent <= subtraction_exponent;
							state <= DIVIDE_HYPERBOLIC_TANGENT;
						else
							subtraction_value <= shift_left(subtraction_value, 1);
							subtraction_exponent <= subtraction_exponent - 1;
						end if;

					when DIVIDE_HYPERBOLIC_TANGENT =>
						tangent_shifted_remainder := shift_left(
							subtraction_value, 1);
						tangent_next_remainder := arithmetic_result_a(
							CORDIC_WIDTH downto 0);
						tangent_next_quotient := shift_left(tangent_quotient, 1);
						if tangent_shifted_remainder >= subtraction_one then
							tangent_next_quotient(0) := '1';
						else
							tangent_next_quotient(0) := '0';
						end if;
						subtraction_value <= tangent_next_remainder;
						tangent_quotient <= tangent_next_quotient;
						if tangent_iteration = 64 then
							intermediate_significand(66 downto 3) <=
								tangent_next_quotient(65 downto 2);
							intermediate_significand(2) <=
								tangent_next_quotient(1);
							intermediate_significand(1) <=
								tangent_next_quotient(0);
							if tangent_next_remainder /= 0 or
									subtraction_sticky = '1' then
								intermediate_significand(0) <= '1';
							else
								intermediate_significand(0) <= '0';
							end if;
							state <= COMPLETE;
						else
							tangent_iteration <= tangent_iteration + 1;
						end if;

					when ALIGN_SUBTRACTION =>
						next_subtraction := subtraction_value;
						next_subtraction_one := subtraction_one;
						next_subtraction_sticky := subtraction_sticky;
						if intermediate_sign = '1' then
							next_subtraction_sticky := subtraction_sticky or
								subtraction_value(0);
							next_subtraction := shift_right(subtraction_value, 1);
						else
							next_subtraction_one := shift_right(subtraction_one, 1);
						end if;
						if subtraction_shift_count = 1 then
							if intermediate_sign = '1' then
								if next_subtraction_sticky = '1' then
									subtraction_difference := subtraction_one -
										next_subtraction - 1;
								else
									subtraction_difference := subtraction_one -
										next_subtraction;
								end if;
							else
								subtraction_difference := subtraction_value -
									next_subtraction_one;
							end if;
							subtraction_value <= subtraction_difference;
							subtraction_sticky <= next_subtraction_sticky;
							subtraction_shift_count <= 0;
							if subtraction_difference(FRACTION_BITS) = '1' then
								complete_subtraction(subtraction_difference,
									subtraction_exponent, intermediate_sign,
									next_subtraction_sticky);
							else
								state <= NORMALIZE_SUBTRACTION;
							end if;
						else
							subtraction_value <= next_subtraction;
							subtraction_one <= next_subtraction_one;
							subtraction_sticky <= next_subtraction_sticky;
							subtraction_shift_count <= subtraction_shift_count - 1;
						end if;

					when NORMALIZE_SUBTRACTION =>
						next_subtraction := shift_left(subtraction_value, 1);
						next_subtraction_exponent := subtraction_exponent - 1;
						subtraction_value <= next_subtraction;
						subtraction_exponent <= next_subtraction_exponent;
						if next_subtraction(FRACTION_BITS) = '1' then
							complete_subtraction(next_subtraction,
								next_subtraction_exponent, intermediate_sign,
								subtraction_sticky);
						end if;

					when FORMAT_NORMALIZED_RESULT =>
						intermediate_class <= FPU_CLASS_NORMAL;
						intermediate_exponent <= subtraction_exponent;
						intermediate_significand <= (others => '0');
						intermediate_significand(66 downto 3) <=
							subtraction_value(FRACTION_BITS downto
								FRACTION_BITS - 63);
						intermediate_significand(2) <=
							subtraction_value(FRACTION_BITS - 64);
						intermediate_significand(1) <=
							subtraction_value(FRACTION_BITS - 65);
						intermediate_significand(0) <= subtraction_sticky or
							or_reduce(subtraction_value(
								FRACTION_BITS - 66 downto 0));
						state <= COMPLETE;

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
