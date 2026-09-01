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
	constant SINE_TINY_EXPONENT : integer := -40;
	constant COSINE_TINY_EXPONENT : integer := -33;
	type sine_cosine_state_t is (IDLE, MULTIPLY_RECIPROCAL, REDUCE_RANGE,
		LOAD_CORDIC_ANGLE, ROTATE_CORDIC, DIVIDE_TANGENT, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 63) of cordic_value_t;

	-- Q192 is sufficient for extended-precision reduction throughout the
	-- Motorola-documented useful FSIN argument range.
	constant TWO_BY_PI : unsigned(RECIPROCAL_BITS - 1 downto 0) :=
		unsigned'(x"A2F9836E4E441529FC2757D1F534DDC0DB6295993C439042");
	constant CORDIC_GAIN_INVERSE : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		unsigned'(x"09B74EDA8435E5A67F5F9092BD7FD40E9C289");
	constant UNIT_FIXED : unsigned(CORDIC_WIDTH - 1 downto 0) :=
		shift_left(to_unsigned(1, CORDIC_WIDTH), FRACTION_BITS);
	constant CORDIC_TAIL_START : cordic_value_t :=
		signed'(x"0000000000000A2F9836E4E441529FC2757D2");
	signal cordic_angle_rom : cordic_angle_rom_t := (
		0 => signed'(x"0800000000000000000000000000000000000"),
		1 => signed'(x"04B90147677CC21995A23DB6B8D4656BF2816"),
		2 => signed'(x"027ECE16D7B8E7A377D0FCF2824878347837D"),
		3 => signed'(x"0144447507776686DFE49572C7C78A5A99849"),
		4 => signed'(x"00A2C350C39626BB303300048A6DA76F3C743"),
		5 => signed'(x"005175F85641189E15A72537A0B6BDCE8F2BC"),
		6 => signed'(x"0028BD87970A098A6135AFD62D2D16923D3FE"),
		7 => signed'(x"00145F15447510ABA8B0C1B2B7AAA6C7A4C3E"),
		8 => signed'(x"000A2F94D1B430CDBF245E9BAC7B0F2ADF9EA"),
		9 => signed'(x"000517CBAECC2ACDEE4D07CB50E3BA1098D82"),
		10 => signed'(x"00028BE600246E9ED9FD0EA488467200A23AA"),
		11 => signed'(x"000145F3052A032DC1E23C00E5D9AAF496522"),
		12 => signed'(x"0000A2F98337FB186652DD8577A994773CBB6"),
		13 => signed'(x"0000517CC1B05CBC91ABD2FE7F4921E75B03A"),
		14 => signed'(x"000028BE60DABA445614E76D187CE4F82DE6B"),
		15 => signed'(x"0000145F306DAE9EECBDC8FF826B712438A54"),
		16 => signed'(x"00000A2F9836E17F0E95AAD539E4055427C4D"),
		17 => signed'(x"00000517CC1B72057A51B112AED731E455262"),
		18 => signed'(x"0000028BE60DB92B7B89B41544BEBA46F7E97"),
		19 => signed'(x"00000145F306DC9AD590F57CD762752A02B35"),
		20 => signed'(x"000000A2F9836E4E0DC1FE2CB80C6334B29BF"),
		21 => signed'(x"000000517CC1B7271B402F8425BF6CDB467B9"),
		22 => signed'(x"00000028BE60DB93902BFDCFCC184C87289BB"),
		23 => signed'(x"000000145F306DC9C8677BA99D33447C50375"),
		24 => signed'(x"0000000A2F9836E4E43DED6D057E8660EBF2D"),
		25 => signed'(x"0000000517CC1B7272203CA9899BDFB7ABD71"),
		26 => signed'(x"000000028BE60DB93910471325A9836CD3926"),
		27 => signed'(x"0000000145F306DC9C8828A15EF034288A356"),
		28 => signed'(x"00000000A2F9836E4E4414F3A8FB8862892DF"),
		29 => signed'(x"00000000517CC1B727220A8E33AE31FB0D199"),
		30 => signed'(x"0000000028BE60DB93910549A5BD26B6BF9D2"),
		31 => signed'(x"00000000145F306DC9C882A5245B551286F0A"),
		32 => signed'(x"000000000A2F9836E4E441529C5D42C0285C9"),
		33 => signed'(x"000000000517CC1B727220A94F749466F0CAD"),
		34 => signed'(x"00000000028BE60DB9391054A7E3089453F90"),
		35 => signed'(x"000000000145F306DC9C882A53F69C16456EF"),
		36 => signed'(x"0000000000A2F9836E4E441529FBF104A625C"),
		37 => signed'(x"0000000000517CC1B727220A94FE0CE18380B"),
		38 => signed'(x"000000000028BE60DB9391054A7F08FCA7CE1"),
		39 => signed'(x"0000000000145F306DC9C882A53F84CFD0A8C"),
		40 => signed'(x"00000000000A2F9836E4E441529FC27217EC9"),
		41 => signed'(x"00000000000517CC1B727220A94FE13A51E95"),
		42 => signed'(x"0000000000028BE60DB9391054A7F09D51B31"),
		43 => signed'(x"00000000000145F306DC9C882A53F84EADF15"),
		44 => signed'(x"000000000000A2F9836E4E441529FC27579BA"),
		45 => signed'(x"000000000000517CC1B727220A94FE13ABE23"),
		46 => signed'(x"00000000000028BE60DB9391054A7F09D5F3A"),
		47 => signed'(x"000000000000145F306DC9C882A53F84EAFA2"),
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

	function fixed_round_input(value : cordic_value_t)
		return fpu_round_input_t is
		variable converted : fpu_round_input_t;
		variable magnitude : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable normalized : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable highest_bit : natural range 0 to CORDIC_WIDTH - 1;
	begin
		converted.data_class := FPU_CLASS_ZERO;
		converted.sign := '0';
		converted.exponent := (others => '0');
		converted.significand := (others => '0');
		converted.special := (others => '0');
		if value < 0 then
			converted.sign := '1';
			magnitude := unsigned(-value);
		else
			magnitude := unsigned(value);
		end if;
		if magnitude > UNIT_FIXED then
			magnitude := UNIT_FIXED;
		end if;
		if magnitude /= 0 then
			highest_bit := highest_set_bit(magnitude);
			normalized := shift_left(magnitude, FRACTION_BITS - highest_bit);
			converted.data_class := FPU_CLASS_NORMAL;
			converted.exponent := to_signed(
				integer(highest_bit) - FRACTION_BITS, 17);
			converted.significand(66 downto 3) := normalized(
				FRACTION_BITS downto FRACTION_BITS - 63);
			converted.significand(2) := normalized(FRACTION_BITS - 64);
			converted.significand(1) := normalized(FRACTION_BITS - 65);
			converted.significand(0) := or_reduce(normalized(
				FRACTION_BITS - 66 downto 0));
		end if;
		return converted;
	end function;

	signal state : sine_cosine_state_t := IDLE;
	signal cosine_latched : std_logic := '0';
	signal tangent_latched : std_logic := '0';
	signal simultaneous_latched : std_logic := '0';
	signal source_sign_latched : std_logic := '0';
	signal source_exponent_latched : integer range -16446 to 16383 := 0;
	signal reciprocal_multiplier : unsigned(63 downto 0) := (others => '0');
	signal reciprocal_multiplicand : unsigned(PRODUCT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal reciprocal_product : unsigned(PRODUCT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal reciprocal_iteration : natural range 0 to 63 := 0;
	signal quadrant : unsigned(1 downto 0) := (others => '0');
	signal cordic_x : cordic_value_t := (others => '0');
	signal cordic_y : cordic_value_t := (others => '0');
	signal cordic_z : cordic_value_t := (others => '0');
	signal cordic_iteration : natural range 0 to FRACTION_BITS := 0;
	signal cordic_angle_address : natural range 0 to 47 := 0;
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal tangent_divisor : unsigned(CORDIC_WIDTH downto 0) := (others => '0');
	signal tangent_remainder : unsigned(CORDIC_WIDTH downto 0) := (others => '0');
	signal tangent_quotient : unsigned(65 downto 0) := (others => '0');
	signal tangent_iteration : natural range 0 to 64 := 0;

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

	sine_cosine_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable selected_nan : fpu_extended_t;
		variable tiny_significand : fpu_significand_grs_t;
		variable next_product : unsigned(PRODUCT_WIDTH - 1 downto 0);
		variable aligned_product : unsigned(PRODUCT_WIDTH - 1 downto 0);
		variable shift_position : integer range -16128 to 294;
		variable fraction_value : unsigned(FRACTION_BITS - 1 downto 0);
		variable reduced_angle : cordic_value_t;
		variable quadrant_sum : unsigned(2 downto 0);
		variable next_angle : cordic_value_t;
		variable next_x : cordic_value_t;
		variable next_y : cordic_value_t;
		variable next_z : cordic_value_t;
		variable selected_value : cordic_value_t;
		variable magnitude : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable final_sign : std_logic;
		variable primary_input : fpu_round_input_t;
		variable secondary_input : fpu_round_input_t;
		variable cosine_value : cordic_value_t;
		variable tangent_numerator : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable tangent_denominator : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable normalized_numerator : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable normalized_denominator : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable numerator_highest : natural range 0 to CORDIC_WIDTH - 1;
		variable denominator_highest : natural range 0 to CORDIC_WIDTH - 1;
		variable numerator_shift : natural range 0 to CORDIC_WIDTH - 1;
		variable denominator_shift : natural range 0 to CORDIC_WIDTH - 1;
		variable quotient_exponent : integer range -65536 to 65535;
		variable shifted_tangent_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable next_tangent_remainder : unsigned(CORDIC_WIDTH downto 0);
		variable next_tangent_quotient : unsigned(65 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				cosine_latched <= '0';
				tangent_latched <= '0';
				simultaneous_latched <= '0';
				source_sign_latched <= '0';
				source_exponent_latched <= 0;
				reciprocal_multiplier <= (others => '0');
				reciprocal_multiplicand <= (others => '0');
				reciprocal_product <= (others => '0');
				reciprocal_iteration <= 0;
				quadrant <= (others => '0');
				cordic_x <= (others => '0');
				cordic_y <= (others => '0');
				cordic_z <= (others => '0');
				cordic_iteration <= 0;
				cordic_angle_address <= 0;
				cordic_shift_angle <= (others => '0');
				tangent_divisor <= (others => '0');
				tangent_remainder <= (others => '0');
				tangent_quotient <= (others => '0');
				tangent_iteration <= 0;
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
							source_exponent_latched <= 0;
							reciprocal_multiplier <= (others => '0');
							reciprocal_multiplicand <= (others => '0');
							reciprocal_product <= (others => '0');
							reciprocal_iteration <= 0;
							quadrant <= (others => '0');
							cordic_x <= (others => '0');
							cordic_y <= (others => '0');
							cordic_z <= (others => '0');
							cordic_iteration <= 0;
							cordic_angle_address <= 0;
							cordic_shift_angle <= (others => '0');
							tangent_divisor <= (others => '0');
							tangent_remainder <= (others => '0');
							tangent_quotient <= (others => '0');
							tangent_iteration <= 0;
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
									reciprocal_multiplier <= source_significand;
									reciprocal_multiplicand <= resize(TWO_BY_PI,
										PRODUCT_WIDTH);
									reciprocal_product <= (others => '0');
									reciprocal_iteration <= 0;
									state <= MULTIPLY_RECIPROCAL;
								end if;
							end if;
						end if;

					when MULTIPLY_RECIPROCAL =>
						next_product := reciprocal_product;
						if reciprocal_multiplier(0) = '1' then
							next_product := next_product + reciprocal_multiplicand;
						end if;
						reciprocal_product <= next_product;
						reciprocal_multiplier <= shift_right(
							reciprocal_multiplier, 1);
						reciprocal_multiplicand <= shift_left(
							reciprocal_multiplicand, 1);
						if reciprocal_iteration = 63 then
							state <= REDUCE_RANGE;
						else
							reciprocal_iteration <= reciprocal_iteration + 1;
						end if;

					when REDUCE_RANGE =>
						-- The aligned product is x*(2/pi) in Q144.  Rounding it to
						-- the nearest integer selects both the quadrant and residual.
						shift_position := 255 - source_exponent_latched;
						if shift_position >= FRACTION_BITS then
							aligned_product := shift_right(reciprocal_product,
								shift_position - FRACTION_BITS);
						elsif FRACTION_BITS - shift_position < PRODUCT_WIDTH then
							aligned_product := shift_left(reciprocal_product,
								FRACTION_BITS - shift_position);
						else
							aligned_product := (others => '0');
						end if;
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
						cordic_x <= signed(CORDIC_GAIN_INVERSE);
						cordic_y <= (others => '0');
						cordic_z <= reduced_angle;
						cordic_iteration <= 0;
						cordic_angle_address <= 0;
						state <= LOAD_CORDIC_ANGLE;

					when LOAD_CORDIC_ANGLE =>
						state <= ROTATE_CORDIC;

					when ROTATE_CORDIC =>
						if cordic_iteration <= 47 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						if cordic_z >= 0 then
							next_x := cordic_x - shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y + shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z - next_angle;
						else
							next_x := cordic_x + shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y - shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z + next_angle;
						end if;
						cordic_x <= next_x;
						cordic_y <= next_y;
						cordic_z <= next_z;
						if cordic_iteration = FRACTION_BITS then
							if tangent_latched = '1' then
								if next_y < 0 then
									final_sign := '1';
									magnitude := unsigned(-next_y);
								else
									final_sign := '0';
									magnitude := unsigned(next_y);
								end if;
								if quadrant(0) = '0' then
									tangent_numerator := magnitude;
									tangent_denominator := unsigned(next_x);
								else
									tangent_numerator := unsigned(next_x);
									tangent_denominator := magnitude;
									final_sign := not final_sign;
								end if;
								if source_sign_latched = '1' then
									final_sign := not final_sign;
								end if;
								intermediate_sign <= final_sign;
								if tangent_denominator = 0 then
									intermediate_class <= FPU_CLASS_INFINITY;
									state <= COMPLETE;
								elsif tangent_numerator = 0 then
									intermediate_class <= FPU_CLASS_ZERO;
									state <= COMPLETE;
								else
									numerator_highest := highest_set_bit(tangent_numerator);
									denominator_highest := highest_set_bit(tangent_denominator);
									numerator_shift := CORDIC_WIDTH - 1 - numerator_highest;
									denominator_shift := CORDIC_WIDTH - 1 - denominator_highest;
									normalized_numerator := shift_left(tangent_numerator,
										numerator_shift);
									normalized_denominator := shift_left(tangent_denominator,
										denominator_shift);
									quotient_exponent := integer(numerator_highest) -
										integer(denominator_highest);
									tangent_divisor <= resize(normalized_denominator,
										CORDIC_WIDTH + 1);
									if normalized_numerator < normalized_denominator then
										tangent_remainder <= shift_left(resize(
											normalized_numerator, CORDIC_WIDTH + 1), 1) -
											resize(normalized_denominator, CORDIC_WIDTH + 1);
										quotient_exponent := quotient_exponent - 1;
									else
										tangent_remainder <= resize(normalized_numerator,
											CORDIC_WIDTH + 1) - resize(normalized_denominator,
											CORDIC_WIDTH + 1);
									end if;
									tangent_quotient <= (0 => '1', others => '0');
									tangent_iteration <= 0;
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_exponent <= to_signed(quotient_exponent, 17);
									state <= DIVIDE_TANGENT;
								end if;
							else
								case quadrant is
									when "00" => selected_value := next_y;
									when "01" => selected_value := next_x;
									when "10" => selected_value := -next_y;
									when others => selected_value := -next_x;
								end case;
								if cosine_latched = '0' and
										source_sign_latched = '1' then
									selected_value := -selected_value;
								end if;
								primary_input := fixed_round_input(selected_value);
								intermediate_class <= primary_input.data_class;
								intermediate_sign <= primary_input.sign;
								intermediate_exponent <= primary_input.exponent;
								intermediate_significand <= primary_input.significand;
								intermediate_special <= primary_input.special;
								if simultaneous_latched = '1' then
									case quadrant is
										when "00" => cosine_value := next_x;
										when "01" => cosine_value := -next_y;
										when "10" => cosine_value := -next_x;
										when others => cosine_value := next_y;
									end case;
									secondary_input := fixed_round_input(cosine_value);
									secondary_class <= secondary_input.data_class;
									secondary_sign <= secondary_input.sign;
									secondary_exponent <= secondary_input.exponent;
									secondary_significand <=
										secondary_input.significand;
									secondary_special <= secondary_input.special;
								end if;
								state <= COMPLETE;
							end if;
						else
							cordic_iteration <= cordic_iteration + 1;
							if cordic_iteration < 47 then
								cordic_angle_address <= cordic_iteration + 1;
								state <= LOAD_CORDIC_ANGLE;
							elsif cordic_iteration = 47 then
								cordic_shift_angle <= CORDIC_TAIL_START;
							else
								cordic_shift_angle <= shift_right(
									cordic_shift_angle, 1);
							end if;
						end if;

					when DIVIDE_TANGENT =>
						shifted_tangent_remainder := shift_left(tangent_remainder, 1);
						next_tangent_quotient := shift_left(tangent_quotient, 1);
						if shifted_tangent_remainder >= tangent_divisor then
							next_tangent_remainder := shifted_tangent_remainder -
								tangent_divisor;
							next_tangent_quotient(0) := '1';
						else
							next_tangent_remainder := shifted_tangent_remainder;
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
