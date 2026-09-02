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

entity TG68K_FPU_Sine_Cosine is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		cosine : in std_logic;
		tangent : in std_logic;
		simultaneous : in std_logic;
		source : in fpu_extended_t;
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		cordic_start : out std_logic;
		cordic_x_input : out signed(147 downto 0);
		cordic_y_input : out signed(147 downto 0);
		cordic_z_input : out signed(147 downto 0);
		cordic_x_result : in signed(147 downto 0);
		cordic_y_result : in signed(147 downto 0);
		cordic_done : in std_logic;

		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		secondary_round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Sine_Cosine is
	constant FRACTION_BITS : natural := 144;
	constant CORDIC_WIDTH : natural := FRACTION_BITS + 4;
	constant RECIPROCAL_BITS : natural := 192;
	constant PRODUCT_WIDTH : natural := 64 + RECIPROCAL_BITS;
	constant SHARED_WIDTH : natural := RECIPROCAL_BITS + 1;
	constant RANGE_SHIFT_CHUNK : natural := 8;
	constant RANGE_SHIFT_TAIL_CHUNK : natural := 4;
	constant NORMALIZATION_SHIFT_CHUNK : natural := 48;
	constant SINE_TINY_EXPONENT : integer := -40;
	constant COSINE_TINY_EXPONENT : integer := -33;
	type sine_cosine_state_t is (IDLE, MULTIPLY_RECIPROCAL, ALIGN_RANGE,
		ALIGN_RANGE_TAIL, REDUCE_RANGE,
		START_CORDIC, WAIT_CORDIC,
		CONVERT_PRIMARY, CONVERT_SECONDARY, NORMALIZE_VALUE,
		LOAD_TANGENT_NUMERATOR, LOAD_TANGENT_DENOMINATOR,
		START_TANGENT_DIVIDE, DIVIDE_TANGENT, COMPLETE);
	type normalization_target_t is
		(NORMALIZE_PRIMARY, NORMALIZE_SECONDARY,
			NORMALIZE_TANGENT_NUMERATOR, NORMALIZE_TANGENT_DENOMINATOR);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);

	-- Q192 is sufficient for extended-precision reduction throughout the
	-- Motorola-documented useful FSIN argument range.
	constant TWO_BY_PI : unsigned(RECIPROCAL_BITS - 1 downto 0) :=
		unsigned'(x"A2F9836E4E441529FC2757D1F534DDC0DB6295993C439042");
	constant CORDIC_GAIN_INVERSE : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		unsigned'(x"09B74EDA8435E5A67F5F9092BD7FD40E9C289");
	constant UNIT_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		shift_left(to_unsigned(1, CORDIC_WIDTH), FRACTION_BITS);
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

	function leading_zero_count(value : unsigned) return natural is
		variable count : natural := 0;
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return count;
			end if;
			count := count + 1;
		end loop;
		return count;
	end function;

	signal state : sine_cosine_state_t := IDLE;
	signal cosine_latched : std_logic := '0';
	signal tangent_latched : std_logic := '0';
	signal simultaneous_latched : std_logic := '0';
	signal source_sign_latched : std_logic := '0';
	signal source_exponent_latched : integer range -16446 to 16383 := 0;
	-- The combined accumulator|multiplier shifts right around the stationary
	-- reciprocal, avoiding a second 256-bit range-reduction shifter.
	signal reciprocal_product : unsigned(PRODUCT_WIDTH downto 0) :=
		(others => '0');
	signal reciprocal_iteration : natural range 0 to 63 := 0;
	signal range_shift_chunks : natural range 0 to
		(PRODUCT_WIDTH - 1) / RANGE_SHIFT_CHUNK := 0;
	signal range_shift_tail : natural range 0 to RANGE_SHIFT_CHUNK - 1 := 0;
	signal range_shift_left : std_logic := '0';
	signal quadrant : unsigned(1 downto 0) := (others => '0');
	signal cordic_source_z : cordic_value_t := (others => '0');
	signal tangent_divisor : unsigned(CORDIC_WIDTH downto 0) := (others => '0');
	signal tangent_remainder : unsigned(CORDIC_WIDTH downto 0) := (others => '0');
	signal tangent_quotient : unsigned(65 downto 0) := (others => '0');
	signal tangent_iteration : natural range 0 to 64 := 0;
	signal tangent_denominator_latched : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalized_tangent_numerator : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalized_tangent_denominator : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal tangent_numerator_highest : natural range 0 to CORDIC_WIDTH - 1 := 0;
	signal tangent_quotient_exponent : integer range -65536 to 65535 := 0;
	signal primary_fixed_value : cordic_value_t := (others => '0');
	signal secondary_fixed_value : cordic_value_t := (others => '0');
	signal normalization_value : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalization_shift_count : natural range 0 to FRACTION_BITS := 0;
	signal normalization_target : normalization_target_t := NORMALIZE_PRIMARY;
	signal normalization_sign : std_logic := '0';
	signal shared_left_a : unsigned(SHARED_WIDTH - 1 downto 0);
	signal shared_right_a : unsigned(SHARED_WIDTH - 1 downto 0);
	signal shared_subtract_a : std_logic;
	signal shared_result_a : unsigned(SHARED_WIDTH - 1 downto 0);

	signal intermediate_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal intermediate_sign : std_logic := '0';
	signal intermediate_exponent : signed(16 downto 0) := (others => '0');
	signal intermediate_significand : fpu_significand_grs_t := (others => '0');
	signal intermediate_special : fpu_extended_t := (others => '0');
	signal secondary_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal secondary_sign : std_logic := '0';
	signal secondary_exponent : signed(16 downto 0) := (others => '0');
	signal secondary_significand : fpu_significand_grs_t := (others => '0');
	signal secondary_special : fpu_extended_t := (others => '0');
	signal base_status : std_logic_vector(7 downto 0) := (others => '0');
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
begin
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	cordic_start <= '1' when state = START_CORDIC else '0';
	cordic_x_input <= signed(CORDIC_GAIN_INVERSE);
	cordic_y_input <= (others => '0');
	cordic_z_input <= cordic_source_z;
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	secondary_round_input.data_class <= secondary_class;
	secondary_round_input.sign <= secondary_sign;
	secondary_round_input.exponent <= secondary_exponent;
	secondary_round_input.significand <= secondary_significand;
	secondary_round_input.special <= secondary_special;
	base_exception_status <= base_status;

	shared_operands : process(state, reciprocal_product,
		normalized_tangent_numerator, normalized_tangent_denominator,
		tangent_remainder, tangent_divisor)
		variable shifted_remainder : unsigned(CORDIC_WIDTH downto 0);
	begin
		shared_left_a <= (others => '0');
		shared_right_a <= (others => '0');
		shared_subtract_a <= '0';
		case state is
			when MULTIPLY_RECIPROCAL =>
				shared_left_a <= resize(reciprocal_product(
					PRODUCT_WIDTH downto 64), SHARED_WIDTH);
				if reciprocal_product(0) = '1' then
					shared_right_a <= resize(TWO_BY_PI,
						SHARED_WIDTH);
				end if;
			when START_TANGENT_DIVIDE =>
				if normalized_tangent_numerator <
						normalized_tangent_denominator then
					shared_left_a <= shift_left(resize(
						normalized_tangent_numerator, SHARED_WIDTH), 1);
				else
					shared_left_a <= resize(normalized_tangent_numerator,
						SHARED_WIDTH);
				end if;
				shared_right_a <= resize(normalized_tangent_denominator,
					SHARED_WIDTH);
				shared_subtract_a <= '1';
			when DIVIDE_TANGENT =>
				shifted_remainder := shift_left(tangent_remainder, 1);
				shared_left_a <= resize(shifted_remainder, SHARED_WIDTH);
				if shifted_remainder >= tangent_divisor then
					shared_right_a <= resize(tangent_divisor, SHARED_WIDTH);
					shared_subtract_a <= '1';
				end if;
			when others => null;
		end case;
	end process;

	shared_add_subtract : process(shared_subtract_a, shared_left_a,
		shared_right_a)
	begin
		if shared_subtract_a = '1' then
			shared_result_a <= shared_left_a - shared_right_a;
		else
			shared_result_a <= shared_left_a + shared_right_a;
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

	sine_cosine_sequence : process(clk)
		procedure begin_normalization(
				constant value : in unsigned(CORDIC_WIDTH - 1 downto 0);
				constant target : in normalization_target_t;
				constant sign_value : in std_logic := '0') is
		begin
			normalization_value <= value;
			normalization_shift_count <= 0;
			normalization_target <= target;
			normalization_sign <= sign_value;
			state <= NORMALIZE_VALUE;
		end procedure;

		procedure finish_normalization(
				constant value : in unsigned(CORDIC_WIDTH - 1 downto 0);
				constant shift_count : in natural) is
			variable significand : fpu_significand_grs_t;
		begin
			case normalization_target is
				when NORMALIZE_PRIMARY | NORMALIZE_SECONDARY =>
					significand := (others => '0');
					significand(66 downto 3) := value(
						FRACTION_BITS downto FRACTION_BITS - 63);
					significand(2) := value(FRACTION_BITS - 64);
					significand(1) := value(FRACTION_BITS - 65);
					significand(0) := or_reduce(value(
						FRACTION_BITS - 66 downto 0));
					if normalization_target = NORMALIZE_PRIMARY then
						intermediate_class <= FPU_CLASS_NORMAL;
						intermediate_sign <= normalization_sign;
						intermediate_exponent <= to_signed(-integer(shift_count), 17);
						intermediate_significand <= significand;
						if simultaneous_latched = '1' then
							state <= CONVERT_SECONDARY;
						else
							state <= COMPLETE;
						end if;
					else
						secondary_class <= FPU_CLASS_NORMAL;
						secondary_sign <= normalization_sign;
						secondary_exponent <= to_signed(-integer(shift_count), 17);
						secondary_significand <= significand;
						state <= COMPLETE;
					end if;
				when NORMALIZE_TANGENT_NUMERATOR =>
					normalized_tangent_numerator <= value;
					tangent_numerator_highest <= FRACTION_BITS - shift_count;
					state <= LOAD_TANGENT_DENOMINATOR;
				when NORMALIZE_TANGENT_DENOMINATOR =>
					normalized_tangent_denominator <= value;
					tangent_quotient_exponent <=
						integer(tangent_numerator_highest) -
						integer(FRACTION_BITS - shift_count);
					state <= START_TANGENT_DIVIDE;
			end case;
		end procedure;

		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable selected_nan : fpu_extended_t;
		variable tiny_significand : fpu_significand_grs_t;
		variable next_reciprocal_product : unsigned(PRODUCT_WIDTH downto 0);
		variable aligned_product : unsigned(PRODUCT_WIDTH - 1 downto 0);
		variable shift_position : integer range -16128 to 294;
		variable fraction_value : unsigned(FRACTION_BITS - 1 downto 0);
		variable reduced_angle : cordic_value_t;
		variable quadrant_sum : unsigned(2 downto 0);
		variable selected_value : cordic_value_t;
		variable magnitude : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable final_sign : std_logic;
		variable cosine_value : cordic_value_t;
		variable tangent_numerator : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable tangent_denominator : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable quotient_exponent : integer range -65536 to 65535;
		variable shifted_tangent_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable next_tangent_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable next_tangent_quotient : unsigned(65 downto 0);
		variable range_shift_amount : natural range 0 to PRODUCT_WIDTH - 1;
		variable next_normalization_value : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable next_normalization_shift : natural range 0 to FRACTION_BITS;
		variable normalization_chunk : natural range 1 to
			NORMALIZATION_SHIFT_CHUNK;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				cosine_latched <= '0';
				tangent_latched <= '0';
				simultaneous_latched <= '0';
				source_sign_latched <= '0';
				source_exponent_latched <= 0;
				reciprocal_product <= (others => '0');
				reciprocal_iteration <= 0;
				range_shift_chunks <= 0;
				range_shift_tail <= 0;
				range_shift_left <= '0';
				quadrant <= (others => '0');
				cordic_source_z <= (others => '0');
				tangent_divisor <= (others => '0');
				tangent_remainder <= (others => '0');
				tangent_quotient <= (others => '0');
				tangent_iteration <= 0;
				tangent_denominator_latched <= (others => '0');
				normalized_tangent_numerator <= (others => '0');
				normalized_tangent_denominator <= (others => '0');
				tangent_numerator_highest <= 0;
				tangent_quotient_exponent <= 0;
				primary_fixed_value <= (others => '0');
				secondary_fixed_value <= (others => '0');
				normalization_value <= (others => '0');
				normalization_shift_count <= 0;
				normalization_target <= NORMALIZE_PRIMARY;
				normalization_sign <= '0';
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				intermediate_exponent <= (others => '0');
				intermediate_significand <= (others => '0');
				intermediate_special <= (others => '0');
				secondary_class <= FPU_CLASS_ZERO;
				secondary_sign <= '0';
				secondary_exponent <= (others => '0');
				secondary_significand <= (others => '0');
				secondary_special <= (others => '0');
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
							cosine_latched <= cosine;
							tangent_latched <= tangent;
							simultaneous_latched <= simultaneous;
							source_sign_latched <= source(79);
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= source(79);
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							secondary_class <= FPU_CLASS_ZERO;
							secondary_sign <= '0';
							secondary_exponent <= (others => '0');
							secondary_significand <= (others => '0');
							secondary_special <= (others => '0');
							base_status <= (others => '0');

							if source_class = FPU_CLASS_QUIET_NAN or
									source_class = FPU_CLASS_SIGNALING_NAN then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_special <= selected_nan;
								if simultaneous = '1' then
									secondary_class <= FPU_CLASS_QUIET_NAN;
									secondary_special <= selected_nan;
								end if;
								if source_class = FPU_CLASS_SIGNALING_NAN then
									base_status(6) <= '1';
								end if;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_special <= FPU_RESET_NAN;
								if simultaneous = '1' then
									secondary_class <= FPU_CLASS_QUIET_NAN;
									secondary_special <= FPU_RESET_NAN;
								end if;
								base_status(5) <= '1';
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_ZERO or
									source_significand = 0 then
								if cosine = '1' then
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_sign <= '0';
									intermediate_significand <=
										(66 => '1', others => '0');
								else
									intermediate_class <= FPU_CLASS_ZERO;
								end if;
								if simultaneous = '1' then
									secondary_class <= FPU_CLASS_NORMAL;
									secondary_significand <=
										(66 => '1', others => '0');
								end if;
								state <= COMPLETE;
							else
								normalization_shift :=
									63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									normalization_shift);
								source_exponent := source_exponent - normalization_shift;
								base_status(1) <= '1';
								if cosine = '1' and
										source_exponent <= COSINE_TINY_EXPONENT then
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_sign <= '0';
									intermediate_exponent <= to_signed(-1, 17);
									intermediate_significand <= (others => '1');
									state <= COMPLETE;
								elsif tangent = '1' and
										source_exponent <= SINE_TINY_EXPONENT then
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_exponent <= to_signed(source_exponent, 17);
									intermediate_significand <= shift_left(resize(
										source_significand, 67), 3) + 1;
									state <= COMPLETE;
								elsif source_exponent <= SINE_TINY_EXPONENT then
									if source_significand = x"8000000000000000" then
										tiny_significand := (others => '1');
										source_exponent := source_exponent - 1;
									else
										tiny_significand := shift_left(resize(
											source_significand, 67), 3) - 1;
									end if;
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_exponent <= to_signed(source_exponent, 17);
									intermediate_significand <= tiny_significand;
									if simultaneous = '1' then
										secondary_class <= FPU_CLASS_NORMAL;
										secondary_exponent <= to_signed(-1, 17);
										secondary_significand <= (others => '1');
									end if;
									state <= COMPLETE;
								else
									source_exponent_latched <= source_exponent;
									reciprocal_product <= resize(source_significand,
										PRODUCT_WIDTH + 1);
									reciprocal_iteration <= 0;
									state <= MULTIPLY_RECIPROCAL;
								end if;
							end if;
						end if;

					when MULTIPLY_RECIPROCAL =>
						next_reciprocal_product := shift_right(
							shared_result_a(RECIPROCAL_BITS downto 0) &
							reciprocal_product(63 downto 0), 1);
						reciprocal_product <= next_reciprocal_product;
						if reciprocal_iteration = 63 then
							shift_position := 255 - source_exponent_latched;
							if shift_position >= FRACTION_BITS then
								range_shift_amount := shift_position - FRACTION_BITS;
								range_shift_left <= '0';
							elsif FRACTION_BITS - shift_position < PRODUCT_WIDTH then
								range_shift_amount := FRACTION_BITS - shift_position;
								range_shift_left <= '1';
							else
								range_shift_amount := 0;
								reciprocal_product <= (others => '0');
							end if;
							range_shift_chunks <=
								range_shift_amount / RANGE_SHIFT_CHUNK;
							range_shift_tail <=
								range_shift_amount mod RANGE_SHIFT_CHUNK;
							if range_shift_amount = 0 then
								state <= REDUCE_RANGE;
							elsif range_shift_amount < RANGE_SHIFT_CHUNK then
								state <= ALIGN_RANGE_TAIL;
							else
								state <= ALIGN_RANGE;
							end if;
						else
							reciprocal_iteration <= reciprocal_iteration + 1;
						end if;

					when ALIGN_RANGE =>
						if range_shift_left = '1' then
							aligned_product := shift_left(reciprocal_product(
								PRODUCT_WIDTH - 1 downto 0), RANGE_SHIFT_CHUNK);
						else
							aligned_product := shift_right(reciprocal_product(
								PRODUCT_WIDTH - 1 downto 0), RANGE_SHIFT_CHUNK);
						end if;
						reciprocal_product <= resize(aligned_product,
							PRODUCT_WIDTH + 1);
						if range_shift_chunks = 1 then
							range_shift_chunks <= 0;
							if range_shift_tail = 0 then
								state <= REDUCE_RANGE;
							else
								state <= ALIGN_RANGE_TAIL;
							end if;
						else
							range_shift_chunks <= range_shift_chunks - 1;
						end if;

					when ALIGN_RANGE_TAIL =>
						if range_shift_tail >= RANGE_SHIFT_TAIL_CHUNK then
							if range_shift_left = '1' then
								aligned_product := shift_left(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0),
									RANGE_SHIFT_TAIL_CHUNK);
							else
								aligned_product := shift_right(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0),
									RANGE_SHIFT_TAIL_CHUNK);
							end if;
						elsif range_shift_tail = 3 then
							if range_shift_left = '1' then
								aligned_product := shift_left(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0), 3);
							else
								aligned_product := shift_right(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0), 3);
							end if;
						elsif range_shift_tail = 2 then
							if range_shift_left = '1' then
								aligned_product := shift_left(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0), 2);
							else
								aligned_product := shift_right(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0), 2);
							end if;
						else
							if range_shift_left = '1' then
								aligned_product := shift_left(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0), 1);
							else
								aligned_product := shift_right(reciprocal_product(
									PRODUCT_WIDTH - 1 downto 0), 1);
							end if;
						end if;
						reciprocal_product <= resize(aligned_product,
							PRODUCT_WIDTH + 1);
						if range_shift_tail <= RANGE_SHIFT_TAIL_CHUNK then
							range_shift_tail <= 0;
							state <= REDUCE_RANGE;
						else
							range_shift_tail <= range_shift_tail -
								RANGE_SHIFT_TAIL_CHUNK;
						end if;

					when REDUCE_RANGE =>
						-- The aligned product is x*(2/pi) in Q144.  Rounding it to
						-- the nearest integer selects both the quadrant and residual.
						aligned_product := reciprocal_product(
							PRODUCT_WIDTH - 1 downto 0);
						fraction_value := aligned_product(FRACTION_BITS - 1 downto 0);
						quadrant_sum := resize(aligned_product(
							FRACTION_BITS + 1 downto FRACTION_BITS), 3);
						reduced_angle := (others => '0');
						reduced_angle(FRACTION_BITS - 1 downto 0) :=
							signed(fraction_value);
						if fraction_value(FRACTION_BITS - 1) = '1' then
							quadrant_sum := quadrant_sum + 1;
							reduced_angle := reduced_angle - shift_left(
								to_signed(1, CORDIC_WIDTH), FRACTION_BITS);
						end if;
						if cosine_latched = '1' then
							quadrant_sum := quadrant_sum + 1;
						end if;
						quadrant <= quadrant_sum(1 downto 0);
						cordic_source_z <= reduced_angle;
						state <= START_CORDIC;

					when START_CORDIC =>
						state <= WAIT_CORDIC;

					when WAIT_CORDIC =>
						if cordic_done = '1' then
							if tangent_latched = '1' then
								if cordic_y_result < 0 then
									final_sign := '1';
									magnitude := unsigned(-cordic_y_result);
								else
									final_sign := '0';
									magnitude := unsigned(cordic_y_result);
								end if;
								if quadrant(0) = '0' then
									tangent_numerator := magnitude;
									tangent_denominator := unsigned(cordic_x_result);
								else
									tangent_numerator := unsigned(cordic_x_result);
									tangent_denominator := magnitude;
									final_sign := not final_sign;
								end if;
								if source_sign_latched = '1' then
									final_sign := not final_sign;
								end if;
								intermediate_sign <= final_sign;
								normalization_value <= tangent_numerator;
								tangent_denominator_latched <= tangent_denominator;
								if tangent_denominator = 0 then
									intermediate_class <= FPU_CLASS_INFINITY;
									state <= COMPLETE;
								elsif tangent_numerator = 0 then
									intermediate_class <= FPU_CLASS_ZERO;
									state <= COMPLETE;
								else
									state <= LOAD_TANGENT_NUMERATOR;
								end if;
							else
								case quadrant is
									when "00" => selected_value := cordic_y_result;
									when "01" => selected_value := cordic_x_result;
									when "10" => selected_value := -cordic_y_result;
									when others => selected_value := -cordic_x_result;
								end case;
								if cosine_latched = '0' and
										source_sign_latched = '1' then
									selected_value := -selected_value;
								end if;
								primary_fixed_value <= selected_value;
								if simultaneous_latched = '1' then
									case quadrant is
										when "00" => cosine_value := cordic_x_result;
										when "01" => cosine_value := -cordic_y_result;
										when "10" => cosine_value := -cordic_x_result;
										when others => cosine_value := cordic_y_result;
									end case;
									secondary_fixed_value <= cosine_value;
								end if;
								state <= CONVERT_PRIMARY;
							end if;
						end if;

					when CONVERT_PRIMARY =>
						if primary_fixed_value < 0 then
							final_sign := '1';
							magnitude := unsigned(-primary_fixed_value);
						else
							final_sign := '0';
							magnitude := unsigned(primary_fixed_value);
						end if;
						if magnitude > UNIT_FIXED then
							magnitude := UNIT_FIXED;
						end if;
						if magnitude = 0 then
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= '0';
							if simultaneous_latched = '1' then
								state <= CONVERT_SECONDARY;
							else
								state <= COMPLETE;
							end if;
						else
							begin_normalization(magnitude, NORMALIZE_PRIMARY,
								final_sign);
						end if;

					when CONVERT_SECONDARY =>
						if secondary_fixed_value < 0 then
							final_sign := '1';
							magnitude := unsigned(-secondary_fixed_value);
						else
							final_sign := '0';
							magnitude := unsigned(secondary_fixed_value);
						end if;
						if magnitude > UNIT_FIXED then
							magnitude := UNIT_FIXED;
						end if;
						if magnitude = 0 then
							secondary_class <= FPU_CLASS_ZERO;
							secondary_sign <= '0';
							state <= COMPLETE;
						else
							begin_normalization(magnitude, NORMALIZE_SECONDARY,
								final_sign);
						end if;

					when LOAD_TANGENT_NUMERATOR =>
						normalization_shift_count <= 0;
						normalization_target <= NORMALIZE_TANGENT_NUMERATOR;
						normalization_sign <= '0';
						state <= NORMALIZE_VALUE;

					when LOAD_TANGENT_DENOMINATOR =>
						begin_normalization(tangent_denominator_latched,
							NORMALIZE_TANGENT_DENOMINATOR);

					when NORMALIZE_VALUE =>
						if normalization_value(FRACTION_BITS) = '1' then
							finish_normalization(normalization_value,
								normalization_shift_count);
						else
							normalization_chunk := leading_zero_count(
								normalization_value(FRACTION_BITS downto
									FRACTION_BITS - NORMALIZATION_SHIFT_CHUNK + 1));
							next_normalization_value := shift_left(
								normalization_value, normalization_chunk);
							next_normalization_shift :=
								normalization_shift_count + normalization_chunk;
							normalization_value <= next_normalization_value;
							normalization_shift_count <= next_normalization_shift;
							if next_normalization_value(FRACTION_BITS) = '1' then
								finish_normalization(next_normalization_value,
									next_normalization_shift);
							end if;
						end if;

					when START_TANGENT_DIVIDE =>
						tangent_divisor <= resize(normalized_tangent_denominator,
							CORDIC_WIDTH + 1);
						tangent_remainder <= shared_result_a(
							CORDIC_WIDTH downto 0);
						tangent_quotient <= (0 => '1', others => '0');
						tangent_iteration <= 0;
						intermediate_class <= FPU_CLASS_NORMAL;
						quotient_exponent := tangent_quotient_exponent;
						if normalized_tangent_numerator <
								normalized_tangent_denominator then
							quotient_exponent := quotient_exponent - 1;
						end if;
						intermediate_exponent <= to_signed(quotient_exponent, 17);
						state <= DIVIDE_TANGENT;

					when DIVIDE_TANGENT =>
						shifted_tangent_remainder := shift_left(tangent_remainder, 1);
						next_tangent_remainder := shared_result_a(
							CORDIC_WIDTH downto 0);
						next_tangent_quotient := shift_left(tangent_quotient, 1);
						if shifted_tangent_remainder >= tangent_divisor then
							next_tangent_quotient(0) := '1';
						else
							next_tangent_quotient(0) := '0';
						end if;
						tangent_remainder <= next_tangent_remainder;
						tangent_quotient <= next_tangent_quotient;
						if tangent_iteration = 64 then
							intermediate_significand(66 downto 3) <=
								next_tangent_quotient(65 downto 2);
							intermediate_significand(2) <= next_tangent_quotient(1);
							intermediate_significand(1) <= next_tangent_quotient(0);
							if next_tangent_remainder /= 0 then
								intermediate_significand(0) <= '1';
							else
								intermediate_significand(0) <= '0';
							end if;
							state <= COMPLETE;
						else
							tangent_iteration <= tangent_iteration + 1;
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
