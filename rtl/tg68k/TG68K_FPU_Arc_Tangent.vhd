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
		SQUARE_ROOT_ARC_SINE_COMPLEMENT, LOAD_CORDIC_ANGLE, CORDIC,
		NORMALIZE_RESULT, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 31) of cordic_value_t;

	constant PI_BY_TWO_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		unsigned'(x"1921FB54442D18469898CC51701B8");
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
		31 => signed'(x"000000001FFFFFFFFFFFFFFFD5555")
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
	signal cordic_x : cordic_value_t := (others => '0');
	signal cordic_y : cordic_value_t := (others => '0');
	signal cordic_z : cordic_value_t := (others => '0');
	signal cordic_iteration : natural range 0 to FRACTION_BITS := 0;
	signal cordic_angle_address : natural range 0 to 31 := 0;
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal normalization_value : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		(others => '0');
	signal normalization_exponent : signed(16 downto 0) := (others => '0');
	signal arc_sine_magnitude : unsigned(FRACTION_BITS downto 0) :=
		(others => '0');
	signal square_multiplier : unsigned(FRACTION_BITS downto 0) :=
		(others => '0');
	signal square_multiplicand : unsigned(2 * FRACTION_BITS + 1 downto 0) :=
		(others => '0');
	signal square_accumulator : unsigned(2 * FRACTION_BITS + 1 downto 0) :=
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
			normalization_value <= angle;
			normalization_exponent <= to_signed(0, 17);
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
		variable next_square : unsigned(2 * FRACTION_BITS + 1 downto 0);
		variable unit_square : unsigned(2 * FRACTION_BITS + 1 downto 0);
		variable shifted_remainder : unsigned(FRACTION_BITS + 2 downto 0);
		variable trial_divisor : unsigned(FRACTION_BITS + 2 downto 0);
		variable next_remainder : unsigned(FRACTION_BITS + 2 downto 0);
		variable next_root : unsigned(FRACTION_BITS downto 0);
		variable next_x : cordic_value_t;
		variable next_y : cordic_value_t;
		variable next_z : cordic_value_t;
		variable next_angle : cordic_value_t;
		variable final_significand : fpu_significand_grs_t;
		variable next_normalization : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable next_exponent : signed(16 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				result_sign <= '0';
				cordic_x <= (others => '0');
				cordic_y <= (others => '0');
				cordic_z <= (others => '0');
				cordic_iteration <= 0;
				cordic_angle_address <= 0;
				cordic_shift_angle <= (others => '0');
				normalization_value <= (others => '0');
				normalization_exponent <= (others => '0');
				arc_sine_magnitude <= (others => '0');
				square_multiplier <= (others => '0');
				square_multiplicand <= (others => '0');
				square_accumulator <= (others => '0');
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
							cordic_x <= (others => '0');
							cordic_y <= (others => '0');
							cordic_z <= (others => '0');
							cordic_iteration <= 0;
							cordic_angle_address <= 0;
							cordic_shift_angle <= (others => '0');
							normalization_value <= (others => '0');
							normalization_exponent <= (others => '0');
							arc_sine_magnitude <= (others => '0');
							square_multiplier <= (others => '0');
							square_multiplicand <= (others => '0');
							square_accumulator <= (others => '0');
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
								if arc_sine = '1' then
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
								intermediate_class <= FPU_CLASS_ZERO;
								state <= COMPLETE;
							else
								normalization_shift :=
									63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									normalization_shift);
								source_exponent := source_exponent - normalization_shift;
								if arc_sine = '1' then
									if source_exponent > 0 or
											(source_exponent = 0 and
											source_significand > x"8000000000000000") then
										intermediate_class <= FPU_CLASS_QUIET_NAN;
										intermediate_special <= FPU_RESET_NAN;
										base_status(5) <= '1';
										state <= COMPLETE;
									elsif source_exponent = 0 then
										base_status(1) <= '1';
										begin_fixed_angle(PI_BY_TWO_FIXED, source(79));
									elsif source_exponent <= ARC_SINE_TINY_EXPONENT then
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
										square_multiplier <= arc_sine_fixed;
										square_multiplicand <= resize(arc_sine_fixed,
											2 * FRACTION_BITS + 2);
										square_accumulator <= (others => '0');
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
						next_square := square_accumulator;
						if square_multiplier(0) = '1' then
							next_square := next_square + square_multiplicand;
						end if;
						square_accumulator <= next_square;
						square_multiplier <= shift_right(square_multiplier, 1);
						square_multiplicand <= shift_left(square_multiplicand, 1);
						if square_iteration = FRACTION_BITS then
							unit_square := (others => '0');
							unit_square(2 * FRACTION_BITS) := '1';
							root_radicand <= unit_square - next_square;
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
						state <= CORDIC;

					when CORDIC =>
						if cordic_iteration <= 31 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						next_x := cordic_x;
						next_y := cordic_y;
						next_z := cordic_z;
						if cordic_y > 0 then
							next_x := cordic_x + shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y - shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z + next_angle;
						elsif cordic_y < 0 then
							next_x := cordic_x - shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y + shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z - next_angle;
						end if;
						cordic_x <= next_x;
						cordic_y <= next_y;
						cordic_z <= next_z;
						if cordic_iteration = FRACTION_BITS then
							begin_fixed_angle(unsigned(next_z), result_sign);
						else
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
