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

entity TG68K_FPU_Packed_To_Extended is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in std_logic_vector(95 downto 0);
		rounding_mode : in fpu_rounding_mode_t;

		result : out fpu_extended_t;
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Packed_To_Extended is
	constant PRODUCT_WIDTH : natural := 186;
	type converter_state_t is (IDLE, PARSE_MANTISSA, MULTIPLY_POWER,
		PREPARE_RESULT, COMPLETE);
	subtype packed_digit_t is unsigned(3 downto 0);
	subtype converter_word_t is unsigned(63 downto 0);

	function highest_set_bit(value : unsigned(63 downto 0)) return natural is
	begin
		for index in 63 downto 0 loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	function mantissa_digit(
		value : std_logic_vector(95 downto 0);
		index : natural) return packed_digit_t is
	begin
		case index is
			when 16 => return unsigned(value(67 downto 64));
			when 15 => return unsigned(value(63 downto 60));
			when 14 => return unsigned(value(59 downto 56));
			when 13 => return unsigned(value(55 downto 52));
			when 12 => return unsigned(value(51 downto 48));
			when 11 => return unsigned(value(47 downto 44));
			when 10 => return unsigned(value(43 downto 40));
			when 9 => return unsigned(value(39 downto 36));
			when 8 => return unsigned(value(35 downto 32));
			when 7 => return unsigned(value(31 downto 28));
			when 6 => return unsigned(value(27 downto 24));
			when 5 => return unsigned(value(23 downto 20));
			when 4 => return unsigned(value(19 downto 16));
			when 3 => return unsigned(value(15 downto 12));
			when 2 => return unsigned(value(11 downto 8));
			when 1 => return unsigned(value(7 downto 4));
			when others => return unsigned(value(3 downto 0));
		end case;
	end function;

	function divisible_by_power_of_two(
		value : unsigned(63 downto 0);
		power : natural) return boolean is
	begin
		for index in 0 to 63 loop
			if index < power and value(index) = '1' then
				return false;
			end if;
		end loop;
		return true;
	end function;

	-- For odd d, n is divisible by d exactly when
	-- (n * d^-1 mod 2^64) <= floor((2^64 - 1) / d).
	function power_of_five_inverse(power : natural) return converter_word_t is
	begin
		case power is
			when 0 => return unsigned'(x"0000000000000001");
			when 1 => return unsigned'(x"CCCCCCCCCCCCCCCD");
			when 2 => return unsigned'(x"8F5C28F5C28F5C29");
			when 3 => return unsigned'(x"1CAC083126E978D5");
			when 4 => return unsigned'(x"D288CE703AFB7E91");
			when 5 => return unsigned'(x"5D4E8FB00BCBE61D");
			when 6 => return unsigned'(x"790FB65668C26139");
			when 7 => return unsigned'(x"E5032477AE8D46A5");
			when 8 => return unsigned'(x"C767074B22E90E21");
			when 9 => return unsigned'(x"8E47CE423A2E9C6D");
			when 10 => return unsigned'(x"4FA7F60D3ED61F49");
			when 11 => return unsigned'(x"0FEE64690C913975");
			when 12 => return unsigned'(x"3662E0E1CF503EB1");
			when 13 => return unsigned'(x"A47A2CF9F6433FBD");
			when 14 => return unsigned'(x"54186F653140A659");
			when 15 => return unsigned'(x"7738164770402145");
			when 16 => return unsigned'(x"E4A4D1417CD9A041");
			when 17 => return unsigned'(x"C75429D9E5C5200D");
			when 18 => return unsigned'(x"C1773B91FAC10669");
			when 19 => return unsigned'(x"26B172506559CE15");
			when 20 => return unsigned'(x"D489E3A9ADDEC2D1");
			when 21 => return unsigned'(x"90E860BB892C8D5D");
			when 22 => return unsigned'(x"502E79BF1B6F4F79");
			when 23 => return unsigned'(x"DCD618596BE30FE5");
			when others => return unsigned'(x"2C2AD1AB7BFA3661");
		end case;
	end function;

	function power_of_five_threshold(power : natural) return converter_word_t is
	begin
		case power is
			when 0 => return unsigned'(x"FFFFFFFFFFFFFFFF");
			when 1 => return unsigned'(x"3333333333333333");
			when 2 => return unsigned'(x"0A3D70A3D70A3D70");
			when 3 => return unsigned'(x"020C49BA5E353F7C");
			when 4 => return unsigned'(x"0068DB8BAC710CB2");
			when 5 => return unsigned'(x"0014F8B588E368F0");
			when 6 => return unsigned'(x"000431BDE82D7B63");
			when 7 => return unsigned'(x"0000D6BF94D5E57A");
			when 8 => return unsigned'(x"00002AF31DC46118");
			when 9 => return unsigned'(x"0000089705F4136B");
			when 10 => return unsigned'(x"000001B7CDFD9D7B");
			when 11 => return unsigned'(x"00000057F5FF85E5");
			when 12 => return unsigned'(x"000000119799812D");
			when 13 => return unsigned'(x"0000000384B84D09");
			when 14 => return unsigned'(x"00000000B424DC35");
			when 15 => return unsigned'(x"0000000024075F3D");
			when 16 => return unsigned'(x"000000000734ACA5");
			when 17 => return unsigned'(x"000000000170EF54");
			when 18 => return unsigned'(x"000000000049C977");
			when 19 => return unsigned'(x"00000000000EC1E4");
			when 20 => return unsigned'(x"000000000002F394");
			when 21 => return unsigned'(x"000000000000971D");
			when 22 => return unsigned'(x"0000000000001E39");
			when 23 => return unsigned'(x"000000000000060B");
			when others => return unsigned'(x"0000000000000135");
		end case;
	end function;

	signal state : converter_state_t := IDLE;
	signal source_latched : std_logic_vector(95 downto 0) := (others => '0');
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal sign_latched : std_logic := '0';
	signal decimal_scale : integer range -1681 to 1649 := 0;
	signal mantissa_accumulator : unsigned(63 downto 0) := (others => '0');
	signal digit_index : natural range 0 to 16 := 0;

	signal power_inverse : std_logic;
	signal power_exponent : unsigned(10 downto 0);
	signal power_multiplier : unsigned(127 downto 0);
	signal power_bits : unsigned(11 downto 0);

	-- A 125-bit normalized power bounds the table approximation below the
	-- retained 65-bit quotient for every 58-bit packed mantissa.
	signal multiplicand : unsigned(PRODUCT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal multiplier : unsigned(57 downto 0) := (others => '0');
	signal product : unsigned(PRODUCT_WIDTH - 1 downto 0) :=
		(others => '0');
	signal multiply_iteration : natural range 0 to 57 := 0;
	signal binary_exponent : integer range -8192 to 8191 := 0;

	signal trailing_exact : std_logic := '0';
	signal divisibility_multiplicand : converter_word_t := (others => '0');
	signal divisibility_multiplier : unsigned(57 downto 0) := (others => '0');
	signal divisibility_product : converter_word_t := (others => '0');

	signal result_latched : fpu_extended_t := (others => '0');
	signal status_latched : std_logic_vector(7 downto 0) := (others => '0');
begin
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	result <= result_latched;
	exception_status <= status_latched;

	power_inverse <= '1' when decimal_scale < 0 else '0';
	power_exponent <= to_unsigned(-decimal_scale, power_exponent'length)
		when decimal_scale < 0 else
		to_unsigned(decimal_scale, power_exponent'length);

	power_table : entity work.TG68K_FPU_Packed_Power_ROM
		port map(
			clk => clk,
			inverse => power_inverse,
			exponent => power_exponent,
			multiplier => power_multiplier,
			power_bits => power_bits
		);

	conversion_sequence : process(clk)
		variable exponent_magnitude : natural range 0 to 1665;
		variable scale_value : integer range -1681 to 1649;
		variable next_mantissa : unsigned(63 downto 0);
		variable high_position : natural range 0 to 57;
		variable aligned_mantissa : unsigned(63 downto 0);
		variable exact_power : integer range -8192 to 8191;
		variable next_product : unsigned(PRODUCT_WIDTH - 1 downto 0);
		variable next_divisibility_product : converter_word_t;
		variable binary_mantissa : unsigned(65 downto 0);
		variable retained_mantissa : unsigned(63 downto 0);
		variable rounded_mantissa : unsigned(64 downto 0);
		variable result_significand : unsigned(63 downto 0);
		variable result_exponent : integer range -8192 to 8191;
		variable guard_bit : std_logic;
		variable below_guard : std_logic;
		variable inexact_result : std_logic;
		variable conversion_exact : std_logic;
		variable increment_result : boolean;
		variable selected_nan : fpu_extended_t;
		variable selected_status : std_logic_vector(7 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				source_latched <= (others => '0');
				mode_latched <= FPU_ROUND_NEAREST;
				sign_latched <= '0';
				decimal_scale <= 0;
				mantissa_accumulator <= (others => '0');
				digit_index <= 0;
				multiplicand <= (others => '0');
				multiplier <= (others => '0');
				product <= (others => '0');
				multiply_iteration <= 0;
				binary_exponent <= 0;
				trailing_exact <= '0';
				divisibility_multiplicand <= (others => '0');
				divisibility_multiplier <= (others => '0');
				divisibility_product <= (others => '0');
				result_latched <= (others => '0');
				status_latched <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							exponent_magnitude :=
								to_integer(unsigned(source(91 downto 88))) * 100 +
								to_integer(unsigned(source(87 downto 84))) * 10 +
								to_integer(unsigned(source(83 downto 80)));
							if source(94) = '1' then
								scale_value := -integer(exponent_magnitude) - 16;
							else
								scale_value := integer(exponent_magnitude) - 16;
							end if;
							source_latched <= source;
							mode_latched <= rounding_mode;
							sign_latched <= source(95);
							decimal_scale <= scale_value;
							mantissa_accumulator <= (others => '0');
							digit_index <= 16;
							result_latched <= (others => '0');
							status_latched <= (others => '0');

							if source(94) = '1' and source(93 downto 92) = "11" and
									source(91 downto 80) = x"FFF" then
								if source(63 downto 0) = x"0000000000000000" then
									result_latched <= source(95) & "111111111111111" &
										x"8000000000000000";
								else
									selected_nan := source(95) & "111111111111111" &
										source(63 downto 0);
									selected_nan(62) := '1';
									result_latched <= selected_nan;
									if source(62) = '0' then
										status_latched(6) <= '1';
									end if;
								end if;
								state <= COMPLETE;
							elsif source(67 downto 64) = "0000" and
									source(63 downto 0) = x"0000000000000000" then
								result_latched(79) <= source(95);
								state <= COMPLETE;
							else
								state <= PARSE_MANTISSA;
							end if;
						end if;

					when PARSE_MANTISSA =>
						next_mantissa := shift_left(mantissa_accumulator, 3) +
							shift_left(mantissa_accumulator, 1) +
							resize(mantissa_digit(source_latched, digit_index), 64);
						mantissa_accumulator <= next_mantissa;
						if digit_index = 0 then
							high_position := highest_set_bit(next_mantissa);
							aligned_mantissa := shift_left(next_mantissa,
								63 - high_position);
							multiplier <= aligned_mantissa(63 downto 6);
							multiplicand <= resize(power_multiplier, PRODUCT_WIDTH);
							product <= (others => '0');
							multiply_iteration <= 0;
							divisibility_product <= (others => '0');
							if decimal_scale >= 0 then
								binary_exponent <= integer(high_position) +
									decimal_scale + to_integer(power_bits) - 65;
								exact_power := integer(high_position) +
									to_integer(power_bits) - 65;
								if exact_power <= 0 then
									trailing_exact <= '1';
								elsif exact_power < 64 and
										divisible_by_power_of_two(next_mantissa,
											natural(exact_power)) then
									trailing_exact <= '1';
								else
									trailing_exact <= '0';
								end if;
								divisibility_multiplicand <= (others => '0');
								divisibility_multiplier <= (others => '0');
							else
								binary_exponent <= integer(high_position) +
									decimal_scale - to_integer(power_bits) - 64;
								if -decimal_scale <= 24 then
									divisibility_multiplicand <=
										power_of_five_inverse(natural(-decimal_scale));
									divisibility_multiplier <= next_mantissa(57 downto 0);
								else
									divisibility_multiplicand <= (others => '0');
									divisibility_multiplier <= (others => '0');
								end if;
								trailing_exact <= '0';
							end if;
							state <= MULTIPLY_POWER;
						else
							digit_index <= digit_index - 1;
						end if;

					when MULTIPLY_POWER =>
						next_product := product;
						if multiplier(0) = '1' then
							next_product := next_product + multiplicand;
						end if;
						product <= next_product;
						multiplicand <= shift_left(multiplicand, 1);
						multiplier <= shift_right(multiplier, 1);

						next_divisibility_product := divisibility_product;
						if divisibility_multiplier(0) = '1' then
							next_divisibility_product := next_divisibility_product +
								divisibility_multiplicand;
						end if;
						divisibility_product <= next_divisibility_product;
						divisibility_multiplicand <=
							shift_left(divisibility_multiplicand, 1);
						divisibility_multiplier <=
							shift_right(divisibility_multiplier, 1);

						if multiply_iteration = 57 then
							state <= PREPARE_RESULT;
						else
							multiply_iteration <= multiply_iteration + 1;
						end if;

					when PREPARE_RESULT =>
						binary_mantissa := product(182 downto 117);
						conversion_exact := trailing_exact;
						if decimal_scale < 0 and -decimal_scale <= 24 and
								divisibility_product <= power_of_five_threshold(
									natural(-decimal_scale)) then
							conversion_exact := '1';
						end if;
						if binary_mantissa(65) = '1' then
							retained_mantissa := binary_mantissa(65 downto 2);
							guard_bit := binary_mantissa(1);
							below_guard := binary_mantissa(0) or not conversion_exact;
							result_exponent := binary_exponent + 65;
						else
							retained_mantissa := binary_mantissa(64 downto 1);
							guard_bit := binary_mantissa(0);
							below_guard := not conversion_exact;
							result_exponent := binary_exponent + 64;
						end if;
						inexact_result := guard_bit or below_guard;
						case mode_latched is
							when FPU_ROUND_NEAREST =>
								increment_result := guard_bit = '1' and
									(below_guard = '1' or retained_mantissa(0) = '1');
							when FPU_ROUND_ZERO =>
								increment_result := false;
							when FPU_ROUND_MINUS_INFINITY =>
								increment_result := sign_latched = '1' and
									inexact_result = '1';
							when FPU_ROUND_PLUS_INFINITY =>
								increment_result := sign_latched = '0' and
									inexact_result = '1';
						end case;

						rounded_mantissa := resize(retained_mantissa, 65);
						if increment_result then
							rounded_mantissa := rounded_mantissa + 1;
						end if;
						if rounded_mantissa(64) = '1' then
							result_significand := x"8000000000000000";
							result_exponent := result_exponent + 1;
						else
							result_significand := rounded_mantissa(63 downto 0);
						end if;

						result_latched <= sign_latched &
							std_logic_vector(to_unsigned(result_exponent + 16383, 15)) &
							std_logic_vector(result_significand);
						selected_status := (others => '0');
						selected_status(0) := inexact_result;
						status_latched <= selected_status;
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
