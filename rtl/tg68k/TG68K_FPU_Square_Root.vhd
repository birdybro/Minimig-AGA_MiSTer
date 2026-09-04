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
		root_start : out std_logic;
		root_radicand : out unsigned(65 downto 0);
		root_result : in unsigned(65 downto 0);
		root_remainder_nonzero : in std_logic;
		root_done : in std_logic;

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
	type square_root_state_t is (IDLE, WAIT_ROOT, COMPLETE);

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
	signal prepared_radicand : unsigned(65 downto 0) := (others => '0');
	signal prepared_exponent : signed(16 downto 0) := (others => '0');
	signal root_operand_valid : std_logic := '0';

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
	root_start <= '1' when state = IDLE and start = '1' and
		root_operand_valid = '1' else '0';
	root_radicand <= prepared_radicand;
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

	prepare_root : process(source)
		variable source_class : fpu_data_class_t;
		variable source_exponent : integer range -65536 to 65535;
		variable result_exponent : integer range -65536 to 65535;
		variable source_significand : unsigned(63 downto 0);
		variable normalization_shift : natural range 0 to 63;
		variable initial_radicand : unsigned(65 downto 0);
	begin
		source_class := fpu_classify(source);
		source_exponent := fpu_unbiased_exponent(source);
		source_significand := unsigned(source(63 downto 0));
		normalization_shift := 0;
		initial_radicand := (others => '0');
		result_exponent := 0;
		root_operand_valid <= '0';
		if source_class /= FPU_CLASS_QUIET_NAN and
				source_class /= FPU_CLASS_SIGNALING_NAN and
				source_class /= FPU_CLASS_ZERO and
				source_class /= FPU_CLASS_INFINITY and
				source_significand /= 0 and source(79) = '0' then
			normalization_shift := 63 - highest_set_bit(source_significand);
			source_significand := shift_left(source_significand,
				normalization_shift);
			source_exponent := source_exponent - normalization_shift;
			if source_exponent mod 2 = 0 then
				initial_radicand := '0' & source_significand & '0';
				result_exponent := source_exponent / 2;
			else
				initial_radicand := source_significand & "00";
				result_exponent := (source_exponent - 1) / 2;
			end if;
			root_operand_valid <= '1';
		end if;
		prepared_radicand <= initial_radicand;
		prepared_exponent <= to_signed(result_exponent, 17);
	end process;

	square_root_sequence : process(clk)
		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable selected_nan : fpu_extended_t;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
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
							source_significand := unsigned(source(63 downto 0));
							selected_nan := source;
							selected_nan(62) := '1';

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
								intermediate_class <= FPU_CLASS_NORMAL;
								intermediate_exponent <= prepared_exponent;
								state <= WAIT_ROOT;
							end if;
						end if;

					when WAIT_ROOT =>
						if root_done = '1' then
							intermediate_significand(66 downto 3) <=
								root_result(65 downto 2);
							intermediate_significand(2) <= root_result(1);
							intermediate_significand(1) <= root_result(0);
							intermediate_significand(0) <=
								root_remainder_nonzero;
							state <= COMPLETE;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
