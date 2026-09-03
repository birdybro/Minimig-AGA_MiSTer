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

entity TG68K_FPU_Extended_To_Packed is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		k_factor : in std_logic_vector(6 downto 0);
		rounding_mode : in fpu_rounding_mode_t;

		result : out std_logic_vector(95 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Extended_To_Packed is
	-- Segmented 192-bit powers retain over 100 guard bits beyond the
	-- maximum 17-digit packed result.
	constant POWER_PRECISION : natural := 192;
	constant LOG10_TWO_SCALED : integer := 1292913986;
	constant TEN_TO_17 : unsigned(63 downto 0) :=
		unsigned'(x"016345785D8A0000");
	constant TEN_TO_18 : unsigned(63 downto 0) :=
		unsigned'(x"0DE0B6B3A7640000");

	type converter_state_t is (IDLE, START_POWER, READ_CHUNK,
		CAPTURE_CHUNK, CAPTURE_RESIDUAL, MULTIPLY_POWER, MULTIPLY_SOURCE,
		ALIGN_PRODUCT, WAIT_FOR_FACTORS, EVALUATE_SCALE, CONVERT_TO_BCD,
		ROUND_AND_PACK, CONVERT_EXPONENT_TO_BCD, PACK_EXPONENT, COMPLETE);
	subtype bcd_digit_t is unsigned(3 downto 0);
	function highest_set_bit(value : unsigned(63 downto 0)) return natural is
	begin
		for index in 63 downto 0 loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	function trailing_zero_count(value : unsigned(63 downto 0)) return natural is
	begin
		for index in 0 to 63 loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 64;
	end function;

	function bcd_digit(
		value : unsigned(71 downto 0);
		index : natural) return bcd_digit_t is
	begin
		case index is
			when 0 => return value(3 downto 0);
			when 1 => return value(7 downto 4);
			when 2 => return value(11 downto 8);
			when 3 => return value(15 downto 12);
			when 4 => return value(19 downto 16);
			when 5 => return value(23 downto 20);
			when 6 => return value(27 downto 24);
			when 7 => return value(31 downto 28);
			when 8 => return value(35 downto 32);
			when 9 => return value(39 downto 36);
			when 10 => return value(43 downto 40);
			when 11 => return value(47 downto 44);
			when 12 => return value(51 downto 48);
			when 13 => return value(55 downto 52);
			when 14 => return value(59 downto 56);
			when 15 => return value(63 downto 60);
			when 16 => return value(67 downto 64);
			when others => return value(71 downto 68);
		end case;
	end function;

	function set_bcd_digit(
		value : unsigned(71 downto 0);
		index : natural;
		digit : unsigned(3 downto 0)) return unsigned is
		variable updated : unsigned(71 downto 0) := value;
	begin
		case index is
			when 0 => updated(3 downto 0) := digit;
			when 1 => updated(7 downto 4) := digit;
			when 2 => updated(11 downto 8) := digit;
			when 3 => updated(15 downto 12) := digit;
			when 4 => updated(19 downto 16) := digit;
			when 5 => updated(23 downto 20) := digit;
			when 6 => updated(27 downto 24) := digit;
			when 7 => updated(31 downto 28) := digit;
			when 8 => updated(35 downto 32) := digit;
			when 9 => updated(39 downto 36) := digit;
			when 10 => updated(43 downto 40) := digit;
			when 11 => updated(47 downto 44) := digit;
			when 12 => updated(51 downto 48) := digit;
			when 13 => updated(55 downto 52) := digit;
			when 14 => updated(59 downto 56) := digit;
			when 15 => updated(63 downto 60) := digit;
			when 16 => updated(67 downto 64) := digit;
			when others => updated(71 downto 68) := digit;
		end case;
		return updated;
	end function;

	signal state : converter_state_t := IDLE;
	signal source_latched : fpu_extended_t := (others => '0');
	signal k_factor_latched : signed(6 downto 0) := (others => '0');
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal binary_power : integer range -16446 to 16320 := 0;
	signal scale_exponent : integer range -5000 to 5000 := 0;
	signal decimal_exponent : integer range -5000 to 5000 := 0;
	signal displayed_digits : natural range 1 to 17 := 17;
	signal finding_exponent : std_logic := '1';

	signal decimal_power : integer range -4983 to 5017;
	signal absolute_decimal_power : natural range 0 to 5017;
	signal power_inverse : std_logic;
	signal power_chunk_index : unsigned(6 downto 0);
	signal power_residual_index : unsigned(6 downto 0);
	signal rom_chunk : std_logic;
	signal rom_index : unsigned(6 downto 0);
	signal rom_multiplier : unsigned(191 downto 0);
	signal rom_power_bits : unsigned(13 downto 0);
	signal chunk_multiplier : unsigned(191 downto 0) := (others => '0');
	signal chunk_power_bits : unsigned(13 downto 0) := (others => '0');
	signal power_bit_sum : natural range 0 to 23200 := 0;

	-- Each product register holds accumulator|multiplier and shifts right;
	-- keeping the multiplicand stationary avoids a second wide shifter.
	signal power_multiplicand : unsigned(191 downto 0) := (others => '0');
	signal power_product : unsigned(384 downto 0) := (others => '0');
	signal power_iteration : natural range 0 to 191 := 0;
	signal source_product : unsigned(448 downto 0) := (others => '0');
	signal source_iteration : natural range 0 to 63 := 0;
	-- Keep the wide product stationary while serially extracting the scaled
	-- low word and sticky bit; a bidirectional 448-bit shift mux is larger.
	signal scaled_integer_register : unsigned(63 downto 0) := (others => '0');
	signal alignment_sticky : std_logic := '0';
	signal alignment_shift : integer range -448 to 448 := 0;
	signal alignment_iteration : natural range 0 to 447 := 0;
	signal alignment_limit : natural range 63 to 447 := 63;
	signal factor_value : unsigned(63 downto 0) := (others => '0');
	signal factor_remainder : unsigned(2 downto 0) := (others => '0');
	signal factor_bit_index : natural range 7 to 63 := 63;
	signal factor_five_count : natural range 0 to 27 := 0;
	signal factor_two_count : natural range 0 to 64 := 0;
	signal factor_active : std_logic := '0';
	signal factor_done : std_logic := '0';
	signal factor_start_seen : std_logic := '0';

	signal binary_to_bcd : unsigned(63 downto 0) := (others => '0');
	signal bcd_value : unsigned(71 downto 0) := (others => '0');
	signal bcd_iteration : natural range 0 to 63 := 0;
	signal exponent_binary : unsigned(12 downto 0) := (others => '0');
	signal exponent_bcd : unsigned(15 downto 0) := (others => '0');
	signal exponent_bcd_iteration : natural range 0 to 12 := 0;
	signal result_latched : std_logic_vector(95 downto 0) := (others => '0');
	signal status_latched : std_logic_vector(7 downto 0) := (others => '0');
begin
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	result <= result_latched;
	exception_status <= status_latched;

	decimal_power <= 17 - scale_exponent;
	absolute_decimal_power <= natural(-decimal_power) when decimal_power < 0 else
		natural(decimal_power);
	power_inverse <= '1' when decimal_power < 0 else '0';
	power_chunk_index <= to_unsigned(absolute_decimal_power / 128, 7);
	power_residual_index <= to_unsigned(absolute_decimal_power mod 128, 7);
	rom_chunk <= '1' when state = READ_CHUNK else '0';
	rom_index <= power_chunk_index when rom_chunk = '1' else
		power_residual_index;

	power_table : entity work.TG68K_FPU_Packed_Output_Power_ROM
		port map(
			clk => clk,
			inverse => power_inverse,
			chunk => rom_chunk,
			index => rom_index,
			multiplier => rom_multiplier,
			power_bits => rom_power_bits
		);

	-- The power table is deliberately finite precision.  Track the factors
	-- needed to recognize mathematically exact decimal conversions so that
	-- approximation residue cannot spuriously set INEX2.
	factor_five_sequence : process(clk)
		variable next_factor : unsigned(63 downto 0);
		variable next_remainder : unsigned(3 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				factor_value <= (others => '0');
				factor_remainder <= (others => '0');
				factor_bit_index <= 63;
				factor_five_count <= 0;
				factor_two_count <= 0;
				factor_active <= '0';
				factor_done <= '0';
				factor_start_seen <= '0';
			else
				if start = '0' then
					factor_start_seen <= '0';
				end if;
				if start = '1' and factor_start_seen = '0' then
					factor_start_seen <= '1';
					factor_value <= unsigned(source(63 downto 0));
					factor_remainder <= (others => '0');
					factor_bit_index <= 63;
					factor_five_count <= 0;
					factor_two_count <= trailing_zero_count(
						unsigned(source(63 downto 0)));
					factor_done <= '0';
					if unsigned(source(63 downto 0)) = 0 then
						factor_active <= '0';
						factor_done <= '1';
					else
						factor_active <= '1';
					end if;
				elsif factor_active = '1' then
					next_factor := factor_value;
					next_remainder := resize(factor_remainder, 4);
					for offset in 0 to 7 loop
						next_remainder := shift_left(next_remainder, 1);
						next_remainder(0) := factor_value(factor_bit_index - offset);
						if next_remainder >= 5 then
							next_remainder := next_remainder - 5;
							next_factor(factor_bit_index - offset) := '1';
						else
							next_factor(factor_bit_index - offset) := '0';
						end if;
					end loop;
					if factor_bit_index = 7 then
						if next_remainder = 0 and factor_five_count < 27 then
							factor_value <= next_factor;
							factor_remainder <= (others => '0');
							factor_bit_index <= 63;
							factor_five_count <= factor_five_count + 1;
						else
							factor_active <= '0';
							factor_done <= '1';
						end if;
					else
						factor_value <= next_factor;
						factor_remainder <= next_remainder(2 downto 0);
						factor_bit_index <= factor_bit_index - 8;
					end if;
				end if;
			end if;
		end if;
	end process;

	conversion_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable significand : unsigned(63 downto 0);
		variable exponent_field : natural range 0 to 32767;
		variable binary_logarithm : integer range -16446 to 16383;
		variable log_product : signed(49 downto 0);
		variable estimate : integer range -5000 to 5000;
		variable power_accumulator_sum : unsigned(192 downto 0);
		variable next_power_product : unsigned(384 downto 0);
		variable source_accumulator_sum : unsigned(384 downto 0);
		variable next_source_product : unsigned(448 downto 0);
		variable shift_value : integer range -32768 to 32767;
		variable next_scaled_integer : unsigned(63 downto 0);
		variable next_sticky : std_logic;
		variable source_index : integer range -448 to 895;
		variable scaled_integer : unsigned(63 downto 0);
		variable scale_lsb_exponent : integer range -5017 to 4983;
		variable scale_is_exact : boolean;
		variable selected_k : integer range -64 to 63;
		variable selected_length : integer range -10000 to 10000;
		variable selected_exponent : integer range -5000 to 5000;
		variable adjusted_bcd : unsigned(71 downto 0);
		variable next_bcd : unsigned(71 downto 0);
		variable adjusted_exponent_bcd : unsigned(15 downto 0);
		variable next_exponent_bcd : unsigned(15 downto 0);
		variable digit : unsigned(3 downto 0);
		variable guard_position : natural range 0 to 16;
		variable guard_digit : unsigned(3 downto 0);
		variable retained_lsb : unsigned(3 downto 0);
		variable lower_nonzero : std_logic;
		variable discarded : std_logic;
		variable increment : boolean;
		variable carry : boolean;
		variable rounded_bcd : unsigned(71 downto 0);
		variable result_exponent : integer range -5000 to 5000;
		variable exponent_magnitude : natural range 0 to 5000;
		variable output_data : std_logic_vector(95 downto 0);
		variable output_status : std_logic_vector(7 downto 0);
		variable mantissa_zero : boolean;
		variable selected_nan : std_logic_vector(63 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				source_latched <= (others => '0');
				k_factor_latched <= (others => '0');
				mode_latched <= FPU_ROUND_NEAREST;
				binary_power <= 0;
				scale_exponent <= 0;
				decimal_exponent <= 0;
				displayed_digits <= 17;
				finding_exponent <= '1';
				chunk_multiplier <= (others => '0');
				chunk_power_bits <= (others => '0');
				power_bit_sum <= 0;
				power_multiplicand <= (others => '0');
				power_product <= (others => '0');
				power_iteration <= 0;
				source_product <= (others => '0');
				source_iteration <= 0;
				scaled_integer_register <= (others => '0');
				alignment_sticky <= '0';
				alignment_shift <= 0;
				alignment_iteration <= 0;
				alignment_limit <= 63;
				binary_to_bcd <= (others => '0');
				bcd_value <= (others => '0');
				bcd_iteration <= 0;
				exponent_binary <= (others => '0');
				exponent_bcd <= (others => '0');
				exponent_bcd_iteration <= 0;
				result_latched <= (others => '0');
				status_latched <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							source_latched <= source;
							k_factor_latched <= signed(k_factor);
							mode_latched <= rounding_mode;
							result_latched <= (others => '0');
							status_latched <= (others => '0');
							if signed(k_factor) > 17 then
								status_latched(5) <= '1';
							end if;
							source_class := fpu_classify(source);
							if source_class = FPU_CLASS_ZERO then
								result_latched(95) <= source(79);
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								result_latched <= source(79) & "111111111111111" &
									x"00000000000000000000";
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_QUIET_NAN or
									source_class = FPU_CLASS_SIGNALING_NAN then
								selected_nan := source(63 downto 0);
								selected_nan(62) := '1';
								result_latched <= source(79) & "111111111111111" &
									x"0000" & selected_nan;
								if source_class = FPU_CLASS_SIGNALING_NAN then
									status_latched(6) <= '1';
								end if;
								state <= COMPLETE;
							else
								significand := unsigned(source(63 downto 0));
								exponent_field := to_integer(unsigned(
									source(78 downto 64)));
								if exponent_field = 0 then
									binary_power <= -16446;
									binary_logarithm := -16446 +
										integer(highest_set_bit(significand));
								else
									binary_power <= integer(exponent_field) -
										FPU_EXTENDED_EXPONENT_BIAS - 63;
									binary_logarithm := integer(exponent_field) -
										FPU_EXTENDED_EXPONENT_BIAS - 63 +
										integer(highest_set_bit(significand));
								end if;
								log_product := to_signed(binary_logarithm, 18) *
									to_signed(LOG10_TWO_SCALED, 32);
								estimate := to_integer(shift_right(log_product, 32));
								scale_exponent <= estimate;
								finding_exponent <= '1';
								state <= START_POWER;
							end if;
						end if;

					when START_POWER => state <= READ_CHUNK;

					when READ_CHUNK => state <= CAPTURE_CHUNK;

					when CAPTURE_CHUNK =>
						chunk_multiplier <= rom_multiplier;
						chunk_power_bits <= rom_power_bits;
						state <= CAPTURE_RESIDUAL;

					when CAPTURE_RESIDUAL =>
						power_multiplicand <= chunk_multiplier;
						power_product <= resize(rom_multiplier, 385);
						power_iteration <= 0;
						power_bit_sum <= to_integer(chunk_power_bits) +
							to_integer(rom_power_bits);
						state <= MULTIPLY_POWER;

					when MULTIPLY_POWER =>
						power_accumulator_sum := power_product(384 downto 192);
						if power_product(0) = '1' then
							power_accumulator_sum := power_accumulator_sum +
								resize(power_multiplicand, 193);
						end if;
						next_power_product := shift_right(power_accumulator_sum &
							power_product(191 downto 0), 1);
						power_product <= next_power_product;
						if power_iteration = 191 then
							source_product <= resize(
								unsigned(source_latched(63 downto 0)), 449);
							source_iteration <= 0;
							state <= MULTIPLY_SOURCE;
						else
							power_iteration <= power_iteration + 1;
						end if;

					when MULTIPLY_SOURCE =>
						source_accumulator_sum := source_product(448 downto 64);
						if source_product(0) = '1' then
							source_accumulator_sum := source_accumulator_sum +
								power_product;
						end if;
						next_source_product := shift_right(source_accumulator_sum &
							source_product(63 downto 0), 1);
						source_product <= next_source_product;
						if source_iteration = 63 then
							if decimal_power >= 0 then
								shift_value := binary_power + decimal_power +
									integer(power_bit_sum) - 2 * POWER_PRECISION;
							else
								shift_value := binary_power + decimal_power -
									integer(power_bit_sum) + 4 -
									2 * POWER_PRECISION;
							end if;
							scaled_integer_register <= (others => '0');
							alignment_sticky <= '0';
							alignment_iteration <= 0;
							if shift_value <= -448 then
								alignment_shift <= -448;
								alignment_limit <= 447;
							elsif shift_value < -64 then
								alignment_shift <= shift_value;
								alignment_limit <= natural(-shift_value) - 1;
							elsif shift_value > 448 then
								alignment_shift <= 448;
								alignment_limit <= 63;
							else
								alignment_shift <= shift_value;
								alignment_limit <= 63;
							end if;
							state <= ALIGN_PRODUCT;
						else
							source_iteration <= source_iteration + 1;
						end if;

					when ALIGN_PRODUCT =>
						next_scaled_integer := scaled_integer_register;
						if alignment_iteration <= 63 then
							source_index := integer(alignment_iteration) -
								alignment_shift;
							if source_index >= 0 and source_index <= 447 then
								next_scaled_integer(alignment_iteration) :=
									source_product(source_index);
							else
								next_scaled_integer(alignment_iteration) := '0';
							end if;
						end if;
						next_sticky := alignment_sticky;
						if alignment_shift < 0 and integer(alignment_iteration) <
								-alignment_shift then
							next_sticky := next_sticky or
								source_product(alignment_iteration);
						end if;
						scaled_integer_register <= next_scaled_integer;
						alignment_sticky <= next_sticky;
						if alignment_iteration = alignment_limit then
							state <= EVALUATE_SCALE;
						else
							alignment_iteration <= alignment_iteration + 1;
						end if;

					when WAIT_FOR_FACTORS =>
						if factor_done = '1' then
							state <= EVALUATE_SCALE;
						end if;

					when EVALUATE_SCALE =>
						if factor_done = '0' then
							state <= WAIT_FOR_FACTORS;
						else
							scaled_integer := scaled_integer_register;
							scale_lsb_exponent := scale_exponent - 17;
							scale_is_exact := false;
							if scale_lsb_exponent >= 0 then
								scale_is_exact := factor_five_count >=
									natural(scale_lsb_exponent) and
									integer(factor_two_count) + binary_power >=
									scale_lsb_exponent;
							else
								scale_is_exact := integer(factor_two_count) +
									binary_power - scale_lsb_exponent >= 0;
							end if;
							if scale_is_exact then
								if decimal_power >= 0 and alignment_sticky = '1' then
									scaled_integer := scaled_integer + 1;
								end if;
								alignment_sticky <= '0';
							else
								alignment_sticky <= '1';
							end if;
							if finding_exponent = '1' and scaled_integer < TEN_TO_17 then
								scale_exponent <= scale_exponent - 1;
								state <= START_POWER;
							elsif finding_exponent = '1' and
									scaled_integer >= TEN_TO_18 then
								scale_exponent <= scale_exponent + 1;
								state <= START_POWER;
							elsif finding_exponent = '1' then
								decimal_exponent <= scale_exponent;
								selected_k := to_integer(k_factor_latched);
								if selected_k > 17 then
									selected_k := 17;
									status_latched(5) <= '1';
								end if;
								if selected_k > 0 then
									selected_length := selected_k;
								else
									-- Nonpositive K selects digits to the right of the
									-- decimal point rather than significant digits.
									selected_length := scale_exponent + 1 - selected_k;
								end if;
								if selected_length < 1 then
									selected_length := 1;
								elsif selected_length > 17 then
									selected_length := 17;
								end if;
								displayed_digits <= natural(selected_length);
								selected_exponent := scale_exponent;
								if selected_k <= 0 and scale_exponent < selected_k then
									selected_exponent := selected_k;
								end if;
								decimal_exponent <= selected_exponent;
								if selected_exponent /= scale_exponent then
									scale_exponent <= selected_exponent;
									finding_exponent <= '0';
									state <= START_POWER;
								else
									binary_to_bcd <= scaled_integer;
									bcd_value <= (others => '0');
									bcd_iteration <= 0;
									state <= CONVERT_TO_BCD;
								end if;
							else
								binary_to_bcd <= scaled_integer;
								bcd_value <= (others => '0');
								bcd_iteration <= 0;
								state <= CONVERT_TO_BCD;
							end if;
						end if;

					when CONVERT_TO_BCD =>
						adjusted_bcd := bcd_value;
						for index in 0 to 17 loop
							digit := bcd_digit(adjusted_bcd, index);
							if digit >= 5 then
								adjusted_bcd := set_bcd_digit(adjusted_bcd, index,
									digit + 3);
							end if;
						end loop;
						next_bcd := adjusted_bcd(70 downto 0) & binary_to_bcd(63);
						bcd_value <= next_bcd;
						binary_to_bcd <= binary_to_bcd(62 downto 0) & '0';
						if bcd_iteration = 63 then
							state <= ROUND_AND_PACK;
						else
							bcd_iteration <= bcd_iteration + 1;
						end if;

					when ROUND_AND_PACK =>
						guard_position := 17 - displayed_digits;
						guard_digit := bcd_digit(bcd_value, guard_position);
						retained_lsb := bcd_digit(bcd_value, guard_position + 1);
						lower_nonzero := alignment_sticky;
						for index in 0 to 15 loop
							if index < guard_position and
									bcd_digit(bcd_value, index) /= 0 then
								lower_nonzero := '1';
							end if;
						end loop;
						discarded := lower_nonzero;
						if guard_digit /= 0 then
							discarded := '1';
						end if;
						case mode_latched is
							when FPU_ROUND_NEAREST =>
								increment := guard_digit > 5 or
									(guard_digit = 5 and
									(lower_nonzero = '1' or retained_lsb(0) = '1'));
							when FPU_ROUND_ZERO => increment := false;
							when FPU_ROUND_MINUS_INFINITY =>
								increment := source_latched(79) = '1' and discarded = '1';
							when FPU_ROUND_PLUS_INFINITY =>
								increment := source_latched(79) = '0' and discarded = '1';
						end case;

						rounded_bcd := bcd_value;
						for index in 0 to 16 loop
							if index <= guard_position then
								rounded_bcd := set_bcd_digit(rounded_bcd, index,
									to_unsigned(0, 4));
							end if;
						end loop;
						carry := increment;
						for index in 1 to 17 loop
							if index >= guard_position + 1 and carry then
								digit := bcd_digit(rounded_bcd, index);
								if digit = 9 then
									rounded_bcd := set_bcd_digit(rounded_bcd, index,
										to_unsigned(0, 4));
								else
									rounded_bcd := set_bcd_digit(rounded_bcd, index,
										digit + 1);
									carry := false;
								end if;
							end if;
						end loop;

						result_exponent := decimal_exponent;
						if carry then
							rounded_bcd := (others => '0');
							rounded_bcd := set_bcd_digit(rounded_bcd, 17,
								to_unsigned(1, 4));
							result_exponent := result_exponent + 1;
						end if;
						mantissa_zero := true;
						for index in 1 to 17 loop
							if bcd_digit(rounded_bcd, index) /= 0 then
								mantissa_zero := false;
							end if;
						end loop;
						if mantissa_zero then
							result_exponent := 0;
						end if;

						output_data := (others => '0');
						output_data(95) := source_latched(79);
						if result_exponent < 0 then
							output_data(94) := '1';
							exponent_magnitude := natural(-result_exponent);
						else
							exponent_magnitude := natural(result_exponent);
						end if;
						output_data(67 downto 64) := std_logic_vector(
							bcd_digit(rounded_bcd, 17));
						output_data(63 downto 0) := std_logic_vector(
							rounded_bcd(67 downto 4));
						output_status := status_latched;
						if discarded = '1' then
							output_status(1) := '1';
						end if;
						if exponent_magnitude > 999 then
							output_status(5) := '1';
						end if;
						result_latched <= output_data;
						status_latched <= output_status;
						exponent_binary <= to_unsigned(exponent_magnitude, 13);
						exponent_bcd <= (others => '0');
						exponent_bcd_iteration <= 0;
						state <= CONVERT_EXPONENT_TO_BCD;

					when CONVERT_EXPONENT_TO_BCD =>
						adjusted_exponent_bcd := exponent_bcd;
						for index in 0 to 3 loop
							digit := adjusted_exponent_bcd(
								index * 4 + 3 downto index * 4);
							if digit >= 5 then
								adjusted_exponent_bcd(
									index * 4 + 3 downto index * 4) := digit + 3;
							end if;
						end loop;
						next_exponent_bcd := adjusted_exponent_bcd(14 downto 0) &
							exponent_binary(12);
						exponent_bcd <= next_exponent_bcd;
						exponent_binary <= exponent_binary(11 downto 0) & '0';
						if exponent_bcd_iteration = 12 then
							state <= PACK_EXPONENT;
						else
							exponent_bcd_iteration <= exponent_bcd_iteration + 1;
						end if;

					when PACK_EXPONENT =>
						result_latched(91 downto 80) <= std_logic_vector(
							exponent_bcd(11 downto 0));
						result_latched(79 downto 76) <= std_logic_vector(
							exponent_bcd(15 downto 12));
						state <= COMPLETE;

					when COMPLETE =>
						if start = '0' then
							state <= IDLE;
						end if;
				end case;
			end if;
		end if;
	end process;
end architecture;
