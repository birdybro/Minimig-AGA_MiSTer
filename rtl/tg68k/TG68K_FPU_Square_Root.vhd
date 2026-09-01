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

entity TG68K_FPU_Square_Root is
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

architecture rtl of TG68K_FPU_Square_Root is
	constant ROOT_BIT_COUNT : natural := 66;
	type square_root_state_t is (IDLE, CALCULATE, COMPLETE);

	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	signal state : square_root_state_t := IDLE;
	signal radicand_register : unsigned(131 downto 0) := (others => '0');
	signal remainder_register : unsigned(68 downto 0) := (others => '0');
	signal root_register : unsigned(65 downto 0) := (others => '0');
	signal iteration_count : natural range 0 to ROOT_BIT_COUNT - 1 := 0;

	signal intermediate_class : fpu_data_class_t := FPU_CLASS_ZERO;
	signal intermediate_sign : std_logic := '0';
	signal intermediate_exponent : signed(16 downto 0) := (others => '0');
	signal intermediate_significand : fpu_significand_grs_t := (others => '0');
	signal intermediate_special : fpu_extended_t := (others => '0');
	signal signaling_nan_detected : std_logic := '0';
	signal operand_error_detected : std_logic := '0';

	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
begin
	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	round_input.data_class <= intermediate_class;
	round_input.sign <= intermediate_sign;
	round_input.exponent <= intermediate_exponent;
	round_input.significand <= intermediate_significand;
	round_input.special <= intermediate_special;
	base_exception_status <= "0" & signaling_nan_detected &
		operand_error_detected & "00000";

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
				overflow => open,
				underflow => open,
				signaling_nan => open
			);
	end generate;

	without_rounding : if not INCLUDE_ROUNDING_STAGE generate
		rounded_result <= (others => '0');
		rounded_inexact <= '0';
	end generate;

	outputs : process(rounded_result, signaling_nan_detected,
			operand_error_detected, rounded_inexact)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(6) := signaling_nan_detected;
		status(5) := operand_error_detected;
		status(1) := rounded_inexact;
		result <= rounded_result;
		condition_codes <= fpu_condition_codes(rounded_result);
		exception_status <= status;
	end process;

	square_root_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable source_exponent : integer range -65536 to 65535;
		variable result_exponent : integer range -65536 to 65535;
		variable source_significand : unsigned(63 downto 0);
		variable normalization_shift : natural range 0 to 63;
		variable selected_nan : fpu_extended_t;
		variable initial_radicand : unsigned(131 downto 0);
		variable shifted_remainder : unsigned(68 downto 0);
		variable trial_divisor : unsigned(68 downto 0);
		variable next_remainder : unsigned(68 downto 0);
		variable next_root : unsigned(65 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				radicand_register <= (others => '0');
				remainder_register <= (others => '0');
				root_register <= (others => '0');
				iteration_count <= 0;
				intermediate_class <= FPU_CLASS_ZERO;
				intermediate_sign <= '0';
				intermediate_exponent <= (others => '0');
				intermediate_significand <= (others => '0');
				intermediate_special <= (others => '0');
				signaling_nan_detected <= '0';
				operand_error_detected <= '0';
			else
				case state is
					when IDLE =>
						if start = '1' then
							source_class := fpu_classify(source);
							source_exponent :=
								to_integer(unsigned(source(78 downto 64))) -
								FPU_EXTENDED_EXPONENT_BIAS;
							if source(78 downto 64) = "000000000000000" then
								source_exponent := 1 - FPU_EXTENDED_EXPONENT_BIAS;
							end if;
							source_significand := unsigned(source(63 downto 0));
							normalization_shift := 0;
							selected_nan := source;
							selected_nan(62) := '1';
							initial_radicand := (others => '0');

							radicand_register <= (others => '0');
							remainder_register <= (others => '0');
							root_register <= (others => '0');
							iteration_count <= 0;
							intermediate_class <= FPU_CLASS_ZERO;
							intermediate_sign <= '0';
							intermediate_exponent <= (others => '0');
							intermediate_significand <= (others => '0');
							intermediate_special <= (others => '0');
							signaling_nan_detected <= '0';
							operand_error_detected <= '0';

							if source_class = FPU_CLASS_QUIET_NAN or
									source_class = FPU_CLASS_SIGNALING_NAN then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_sign <= selected_nan(79);
								intermediate_special <= selected_nan;
								if source_class = FPU_CLASS_SIGNALING_NAN then
									signaling_nan_detected <= '1';
								end if;
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_ZERO or
									source_significand = 0 then
								intermediate_class <= FPU_CLASS_ZERO;
								intermediate_sign <= source(79);
								state <= COMPLETE;
							elsif source(79) = '1' then
								intermediate_class <= FPU_CLASS_QUIET_NAN;
								intermediate_special <= FPU_RESET_NAN;
								operand_error_detected <= '1';
								state <= COMPLETE;
							elsif source_class = FPU_CLASS_INFINITY then
								intermediate_class <= FPU_CLASS_INFINITY;
								state <= COMPLETE;
							else
								normalization_shift :=
									63 - highest_set_bit(source_significand);
								source_significand := shift_left(source_significand,
									normalization_shift);
								source_exponent := source_exponent -
									normalization_shift;
								if source_exponent mod 2 = 0 then
									initial_radicand(130 downto 67) :=
										source_significand;
									result_exponent := source_exponent / 2;
								else
									initial_radicand(131 downto 68) :=
										source_significand;
									result_exponent := (source_exponent - 1) / 2;
								end if;
								radicand_register <= initial_radicand;
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_exponent <=
									to_signed(result_exponent, 17);
								state <= CALCULATE;
							end if;
						end if;

					when CALCULATE =>
						shifted_remainder := shift_left(remainder_register, 2);
						shifted_remainder(1 downto 0) :=
							radicand_register(131 downto 130);
						trial_divisor := shift_left(resize(root_register, 69), 2);
						trial_divisor(0) := '1';
						next_root := shift_left(root_register, 1);
						if shifted_remainder >= trial_divisor then
							next_remainder := shifted_remainder - trial_divisor;
							next_root(0) := '1';
						else
							next_remainder := shifted_remainder;
							next_root(0) := '0';
						end if;
						radicand_register <= shift_left(radicand_register, 2);
						remainder_register <= next_remainder;
						root_register <= next_root;
						if iteration_count = ROOT_BIT_COUNT - 1 then
							intermediate_significand(66 downto 3) <=
								next_root(65 downto 2);
							intermediate_significand(2) <= next_root(1);
							intermediate_significand(1) <= next_root(0);
							if next_remainder /= 0 then
								intermediate_significand(0) <= '1';
							else
								intermediate_significand(0) <= '0';
							end if;
							state <= COMPLETE;
						else
							iteration_count <= iteration_count + 1;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
