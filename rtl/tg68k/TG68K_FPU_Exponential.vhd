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
	type exponential_state_t is
		(IDLE, MULTIPLY_LOG2, LOAD_CORDIC_ANGLE, CORDIC, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type cordic_angle_rom_t is array(0 to 31) of cordic_value_t;

	constant LN2_FIXED : unsigned(FRACTION_BITS - 1 downto 0) :=
		x"B17217F7D1CF79ABC9E3B398";
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
	signal result_exponent : signed(16 downto 0) := (others => '0');
	signal cordic_x : cordic_value_t := (others => '0');
	signal cordic_y : cordic_value_t := (others => '0');
	signal cordic_z : cordic_value_t := (others => '0');
	signal cordic_iteration : natural range 1 to FRACTION_BITS := 1;
	signal repeat_iteration : std_logic := '0';
	signal cordic_angle_rom_data : cordic_value_t := (others => '0');
	signal cordic_shift_angle : cordic_value_t := (others => '0');
	signal cordic_angle_address : natural range 1 to 31 := 1;

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

	exponential_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable shift_amount : integer range -65536 to 65535;
		variable magnitude_fixed : unsigned(FIXED_WIDTH - 1 downto 0);
		variable integer_magnitude : natural range 0 to 65535;
		variable fraction_value : unsigned(FRACTION_BITS - 1 downto 0);
		variable exponent_value : integer range -65536 to 65535;
		variable selected_nan : fpu_extended_t;
		variable multiply_sum : unsigned(FRACTION_BITS downto 0);
		variable next_accumulator : unsigned(FRACTION_BITS downto 0);
		variable next_x : cordic_value_t;
		variable next_y : cordic_value_t;
		variable next_z : cordic_value_t;
		variable next_angle : cordic_value_t;
		variable cordic_sum : signed(CORDIC_WIDTH downto 0);
		variable normalized_sum : unsigned(CORDIC_WIDTH downto 0);
		variable final_exponent : signed(16 downto 0);
		variable final_significand : fpu_significand_grs_t;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				fraction_register <= (others => '0');
				product_accumulator <= (others => '0');
				multiply_index <= 0;
				result_exponent <= (others => '0');
				cordic_x <= (others => '0');
				cordic_y <= (others => '0');
				cordic_z <= (others => '0');
				cordic_iteration <= 1;
				repeat_iteration <= '0';
				cordic_shift_angle <= (others => '0');
				cordic_angle_address <= 1;
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
							result_exponent <= (others => '0');
							cordic_x <= (others => '0');
							cordic_y <= (others => '0');
							cordic_z <= (others => '0');
							cordic_iteration <= 1;
							repeat_iteration <= '0';
							cordic_shift_angle <= (others => '0');
							cordic_angle_address <= 1;
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
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_significand(66) <= '1';
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								if source(79) = '1' then
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
								magnitude_fixed := (others => '0');
								shift_amount := source_exponent + FRACTION_BITS - 63;
								if source_exponent > 15 then
									if source(79) = '1' then
										exponent_value := -65536;
									else
										exponent_value := 65535;
									end if;
									intermediate_class <= FPU_CLASS_NORMAL;
									intermediate_exponent <= to_signed(exponent_value, 17);
									intermediate_significand(66) <= '1';
									base_status(1) <= '1';
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
										if source(79) = '0' then
											intermediate_significand(66) <= '1';
											intermediate_significand(0) <= '1';
										else
											intermediate_exponent <= to_signed(-1, 17);
											intermediate_significand <= (others => '1');
										end if;
										state <= COMPLETE;
									else
										integer_magnitude := to_integer(magnitude_fixed(
											FIXED_WIDTH - 1 downto FRACTION_BITS));
										fraction_value := magnitude_fixed(
											FRACTION_BITS - 1 downto 0);
										if source(79) = '0' then
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
											intermediate_class <= FPU_CLASS_NORMAL;
											intermediate_exponent <=
												to_signed(exponent_value, 17);
											intermediate_significand(66) <= '1';
											state <= COMPLETE;
										else
											fraction_register <= fraction_value;
											state <= MULTIPLY_LOG2;
										end if;
									end if;
								end if;
							end if;
						end if;

					when MULTIPLY_LOG2 =>
						multiply_sum := product_accumulator;
						if fraction_register(multiply_index) = '1' then
							multiply_sum := multiply_sum + resize(LN2_FIXED,
								FRACTION_BITS + 1);
						end if;
						next_accumulator := shift_right(multiply_sum, 1);
						product_accumulator <= next_accumulator;
						if multiply_index = FRACTION_BITS - 1 then
							if next_accumulator = 0 then
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_exponent <= result_exponent;
								intermediate_significand(66) <= '1';
								intermediate_significand(0) <= '1';
								state <= COMPLETE;
							else
								cordic_x <= CORDIC_INVERSE_GAIN;
								cordic_y <= (others => '0');
								cordic_z <= signed(resize(next_accumulator,
									CORDIC_WIDTH));
								cordic_iteration <= 1;
								repeat_iteration <= '0';
								cordic_angle_address <= 1;
								state <= LOAD_CORDIC_ANGLE;
							end if;
						else
							multiply_index <= multiply_index + 1;
						end if;

					when LOAD_CORDIC_ANGLE =>
						state <= CORDIC;

					when CORDIC =>
						if cordic_iteration <= 31 then
							next_angle := cordic_angle_rom_data;
						else
							next_angle := cordic_shift_angle;
						end if;
						if cordic_z >= 0 then
							next_x := cordic_x + shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y + shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z - next_angle;
						else
							next_x := cordic_x - shift_right(cordic_y,
								cordic_iteration);
							next_y := cordic_y - shift_right(cordic_x,
								cordic_iteration);
							next_z := cordic_z + next_angle;
						end if;
						cordic_x <= next_x;
						cordic_y <= next_y;
						cordic_z <= next_z;
						-- Hyperbolic CORDIC repeats these iterations to converge.
						if (cordic_iteration = 4 or cordic_iteration = 13 or
								cordic_iteration = 40) and repeat_iteration = '0' then
							repeat_iteration <= '1';
						elsif cordic_iteration = FRACTION_BITS then
							cordic_sum := resize(next_x, CORDIC_WIDTH + 1) +
								resize(next_y, CORDIC_WIDTH + 1);
							normalized_sum := unsigned(cordic_sum);
							final_exponent := result_exponent;
							if normalized_sum(FRACTION_BITS + 1) = '1' then
								normalized_sum := shift_right(normalized_sum, 1);
								final_exponent := result_exponent + 1;
							elsif normalized_sum(FRACTION_BITS) = '0' then
								normalized_sum := shift_left(normalized_sum, 1);
								final_exponent := result_exponent - 1;
							end if;
							final_significand := (others => '0');
							final_significand(66 downto 3) := normalized_sum(
								FRACTION_BITS downto FRACTION_BITS - 63);
							final_significand(2) :=
								normalized_sum(FRACTION_BITS - 64);
							final_significand(1) :=
								normalized_sum(FRACTION_BITS - 65);
							final_significand(0) := or_reduce(normalized_sum(
								FRACTION_BITS - 66 downto 0));
							intermediate_class <= FPU_CLASS_NORMAL;
							intermediate_exponent <= final_exponent;
							intermediate_significand <= final_significand;
							state <= COMPLETE;
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
								cordic_shift_angle <=
									shift_right(cordic_shift_angle, 1);
							end if;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
