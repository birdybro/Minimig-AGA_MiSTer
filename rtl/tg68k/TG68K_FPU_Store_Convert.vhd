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

entity TG68K_FPU_Store_Convert is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		source : in fpu_extended_t;
		destination_format : in fpu_operand_format_t;
		rounding_mode : in fpu_rounding_mode_t;
		external_rounded_result : in fpu_extended_t := (others => '0');
		external_rounded_inexact : in std_logic := '0';
		external_rounded_overflow : in std_logic := '0';
		external_rounded_underflow : in std_logic := '0';
		external_rounded_signaling_nan : in std_logic := '0';

		destination_data : out std_logic_vector(95 downto 0);
		conversion_valid : out std_logic;
		exception_status : out std_logic_vector(7 downto 0);
		round_input : out fpu_round_input_t;
		rounding_precision_out : out fpu_rounding_precision_t
	);
end entity;

architecture rtl of TG68K_FPU_Store_Convert is
	function highest_set_bit(value : unsigned(63 downto 0)) return natural is
	begin
		for index in 63 downto 0 loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	signal source_class : fpu_data_class_t;
	signal prepared_sign : std_logic;
	signal prepared_exponent : signed(16 downto 0);
	signal prepared_significand : fpu_significand_grs_t;
	signal destination_precision : fpu_rounding_precision_t;
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	signal rounded_overflow : std_logic;
	signal rounded_underflow : std_logic;
	signal rounded_signaling_nan : std_logic;
begin
	source_class <= fpu_classify(source);
	round_input.data_class <= source_class;
	round_input.sign <= prepared_sign;
	round_input.exponent <= prepared_exponent;
	round_input.significand <= prepared_significand;
	round_input.special <= source;
	rounding_precision_out <= destination_precision;

	prepare : process(source, source_class)
		variable significand : unsigned(63 downto 0);
		variable exponent_value : integer range -65536 to 65535;
		variable shift_count : natural range 0 to 63;
	begin
		prepared_sign <= source(79);
		prepared_exponent <= (others => '0');
		prepared_significand <= (others => '0');
		significand := unsigned(source(63 downto 0));
		exponent_value := 0;
		shift_count := 0;

		if source_class = FPU_CLASS_NORMAL and significand /= 0 then
			if source(78 downto 64) = "000000000000000" then
				shift_count := 63 - highest_set_bit(significand);
				exponent_value := -16383 - shift_count;
			else
				exponent_value := to_integer(unsigned(source(78 downto 64))) -
					FPU_EXTENDED_EXPONENT_BIAS;
				if significand(63) = '0' then
					shift_count := 63 - highest_set_bit(significand);
					exponent_value := exponent_value - shift_count;
				end if;
			end if;
			significand := shift_left(significand, shift_count);
			prepared_exponent <= to_signed(exponent_value, 17);
			prepared_significand <= significand & "000";
		end if;
	end process;

	with destination_format select destination_precision <=
		FPU_PRECISION_SINGLE when FPU_FORMAT_SINGLE,
		FPU_PRECISION_DOUBLE when FPU_FORMAT_DOUBLE,
		FPU_PRECISION_EXTENDED when others;

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		rounder : entity work.TG68K_FPU_Round
			port map(
				input_class => source_class,
				input_sign => prepared_sign,
				input_exponent => prepared_exponent,
				input_significand => prepared_significand,
				special_value => source,
				rounding_precision => destination_precision,
				rounding_mode => rounding_mode,
				result => rounded_result,
				inexact => rounded_inexact,
				overflow => rounded_overflow,
				underflow => rounded_underflow,
				signaling_nan => rounded_signaling_nan
			);
	end generate;

	without_rounding : if not INCLUDE_ROUNDING_STAGE generate
		rounded_result <= external_rounded_result;
		rounded_inexact <= external_rounded_inexact;
		rounded_overflow <= external_rounded_overflow;
		rounded_underflow <= external_rounded_underflow;
		rounded_signaling_nan <= external_rounded_signaling_nan;
	end generate;

	pack : process(source, source_class, destination_format, rounding_mode,
		prepared_exponent, prepared_significand, rounded_result,
		rounded_inexact, rounded_overflow, rounded_underflow,
		rounded_signaling_nan)
		variable output_data : std_logic_vector(95 downto 0);
		variable status : std_logic_vector(7 downto 0);
		variable valid : std_logic;
		variable result_class : fpu_data_class_t;
		variable result_significand : unsigned(63 downto 0);
		variable shifted_significand : unsigned(63 downto 0);
		variable result_exponent : integer range -65536 to 65535;
		variable shift_count : natural range 0 to 63;
		variable integer_magnitude : unsigned(64 downto 0);
		variable integer_limit : unsigned(64 downto 0);
		variable integer_bits : unsigned(31 downto 0);
		variable source_significand : unsigned(63 downto 0);
		variable shift_operand : unsigned(63 downto 0);
		variable shared_shift_result : unsigned(63 downto 0);
		variable nan_significand : unsigned(63 downto 0);
		variable discarded : std_logic;
		variable guard : std_logic;
		variable lower_discarded : std_logic;
		variable increment : boolean;
		variable integer_overflow : boolean;
	begin
		output_data := (others => '0');
		status := (others => '0');
		valid := '1';
		result_class := fpu_classify(rounded_result);
		result_significand := unsigned(rounded_result(63 downto 0));
		shifted_significand := (others => '0');
		result_exponent := 0;
		shift_count := 0;
		integer_magnitude := (others => '0');
		integer_limit := (others => '0');
		integer_bits := (others => '0');
		source_significand := prepared_significand(66 downto 3);
		shift_operand := (others => '0');
		nan_significand := unsigned(source(63 downto 0));
		discarded := '0';
		guard := '0';
		lower_discarded := '0';
		increment := false;
		integer_overflow := false;

		if (destination_format = FPU_FORMAT_SINGLE or
				destination_format = FPU_FORMAT_DOUBLE) and
				result_class = FPU_CLASS_NORMAL then
			shift_operand := result_significand;
			result_exponent := to_integer(unsigned(
				rounded_result(78 downto 64))) - FPU_EXTENDED_EXPONENT_BIAS;
			if destination_format = FPU_FORMAT_SINGLE and
					result_exponent < -126 then
				if result_exponent <= -189 then
					shift_count := 63;
				else
					shift_count := -126 - result_exponent;
				end if;
			elsif destination_format = FPU_FORMAT_DOUBLE and
					result_exponent < -1022 then
				if result_exponent <= -1085 then
					shift_count := 63;
				else
					shift_count := -1022 - result_exponent;
				end if;
			end if;
		elsif (destination_format = FPU_FORMAT_BYTE_INTEGER or
				destination_format = FPU_FORMAT_WORD_INTEGER or
				destination_format = FPU_FORMAT_LONG_INTEGER) and
				source_class = FPU_CLASS_NORMAL then
			shift_operand := source_significand;
			result_exponent := to_integer(prepared_exponent);
			if result_exponent >= 0 and result_exponent < 63 then
				shift_count := 63 - result_exponent;
			end if;
		end if;
		shared_shift_result := shift_right(shift_operand, shift_count);

		case destination_format is
			when FPU_FORMAT_SINGLE | FPU_FORMAT_DOUBLE |
					FPU_FORMAT_EXTENDED =>
				if rounded_signaling_nan = '1' then
					status(FPU_FPSR_SNAN_BIT - 8) := '1';
				end if;
				if rounded_overflow = '1' then
					status(FPU_FPSR_OVFL_BIT - 8) := '1';
				end if;
				if rounded_underflow = '1' then
					status(FPU_FPSR_UNFL_BIT - 8) := '1';
				end if;
				if rounded_inexact = '1' then
					status(FPU_FPSR_INEX2_BIT - 8) := '1';
				end if;

				case destination_format is
					when FPU_FORMAT_EXTENDED =>
						output_data := rounded_result(79 downto 64) &
							x"0000" & rounded_result(63 downto 0);
					when FPU_FORMAT_SINGLE =>
						output_data(31) := rounded_result(79);
						case result_class is
							when FPU_CLASS_ZERO => null;
							when FPU_CLASS_INFINITY =>
								output_data(30 downto 23) := (others => '1');
							when FPU_CLASS_QUIET_NAN | FPU_CLASS_SIGNALING_NAN =>
								output_data(30 downto 23) := (others => '1');
								output_data(22 downto 0) := std_logic_vector(
									result_significand(62 downto 40));
							when FPU_CLASS_NORMAL =>
								if result_exponent >= -126 then
									output_data(30 downto 23) := std_logic_vector(
										to_unsigned(result_exponent + 127, 8));
									output_data(22 downto 0) := std_logic_vector(
										result_significand(62 downto 40));
								else
									shifted_significand := shared_shift_result;
									output_data(22 downto 0) := std_logic_vector(
										shifted_significand(62 downto 40));
								end if;
						end case;
					when FPU_FORMAT_DOUBLE =>
						output_data(63) := rounded_result(79);
						case result_class is
							when FPU_CLASS_ZERO => null;
							when FPU_CLASS_INFINITY =>
								output_data(62 downto 52) := (others => '1');
							when FPU_CLASS_QUIET_NAN | FPU_CLASS_SIGNALING_NAN =>
								output_data(62 downto 52) := (others => '1');
								output_data(51 downto 0) := std_logic_vector(
									result_significand(62 downto 11));
							when FPU_CLASS_NORMAL =>
								if result_exponent >= -1022 then
									output_data(62 downto 52) := std_logic_vector(
										to_unsigned(result_exponent + 1023, 11));
									output_data(51 downto 0) := std_logic_vector(
										result_significand(62 downto 11));
								else
									shifted_significand := shared_shift_result;
									output_data(51 downto 0) := std_logic_vector(
										shifted_significand(62 downto 11));
								end if;
						end case;
					when others => null;
				end case;

			when FPU_FORMAT_BYTE_INTEGER | FPU_FORMAT_WORD_INTEGER |
					FPU_FORMAT_LONG_INTEGER =>
				if source_class = FPU_CLASS_INFINITY then
					integer_overflow := true;
					status(FPU_FPSR_OPERR_BIT - 8) := '1';
				elsif source_class = FPU_CLASS_QUIET_NAN or
						source_class = FPU_CLASS_SIGNALING_NAN then
					nan_significand(62) := '1';
					case destination_format is
						when FPU_FORMAT_BYTE_INTEGER =>
							output_data(7 downto 0) := std_logic_vector(
								nan_significand(63 downto 56));
						when FPU_FORMAT_WORD_INTEGER =>
							output_data(15 downto 0) := std_logic_vector(
								nan_significand(63 downto 48));
						when others =>
							output_data(31 downto 0) := std_logic_vector(
								nan_significand(63 downto 32));
					end case;
					if source_class = FPU_CLASS_SIGNALING_NAN then
						status(FPU_FPSR_SNAN_BIT - 8) := '1';
					else
						status(FPU_FPSR_OPERR_BIT - 8) := '1';
					end if;
				elsif source_class = FPU_CLASS_NORMAL then
					if result_exponent >= 63 then
						integer_overflow := true;
					elsif result_exponent >= 0 then
						integer_magnitude := resize(shared_shift_result, 65);
						for index in 0 to 62 loop
							if index < shift_count then
								discarded := discarded or
									source_significand(index);
							end if;
						end loop;
						guard := source_significand(shift_count - 1);
						for index in 0 to 61 loop
							if index < shift_count - 1 then
								lower_discarded := lower_discarded or
									source_significand(index);
							end if;
						end loop;
					else
						discarded := '1';
						if result_exponent = -1 then
							guard := source_significand(63);
							for index in 0 to 62 loop
								lower_discarded := lower_discarded or
									source_significand(index);
							end loop;
						end if;
					end if;

					case rounding_mode is
						when FPU_ROUND_NEAREST =>
							increment := guard = '1' and
								(lower_discarded = '1' or integer_magnitude(0) = '1');
						when FPU_ROUND_ZERO => increment := false;
						when FPU_ROUND_MINUS_INFINITY =>
							increment := source(79) = '1' and discarded = '1';
						when FPU_ROUND_PLUS_INFINITY =>
							increment := source(79) = '0' and discarded = '1';
					end case;
					if increment then
						integer_magnitude := integer_magnitude + 1;
					end if;
					if discarded = '1' then
						status(FPU_FPSR_INEX2_BIT - 8) := '1';
					end if;
				end if;

				if source_class = FPU_CLASS_ZERO then
					integer_magnitude := (others => '0');
				end if;
				if source_class /= FPU_CLASS_QUIET_NAN and
						source_class /= FPU_CLASS_SIGNALING_NAN then
					case destination_format is
						when FPU_FORMAT_BYTE_INTEGER =>
							if source(79) = '1' then
								integer_limit := to_unsigned(128, 65);
							else
								integer_limit := to_unsigned(127, 65);
							end if;
						when FPU_FORMAT_WORD_INTEGER =>
							if source(79) = '1' then
								integer_limit := to_unsigned(32768, 65);
							else
								integer_limit := to_unsigned(32767, 65);
							end if;
						when others =>
							if source(79) = '1' then
								integer_limit := shift_left(to_unsigned(1, 65), 31);
							else
								integer_limit := shift_left(to_unsigned(1, 65), 31) - 1;
							end if;
					end case;

					if integer_magnitude > integer_limit then
						integer_overflow := true;
					end if;
					if integer_overflow then
						status(FPU_FPSR_OPERR_BIT - 8) := '1';
						integer_magnitude := integer_limit;
					end if;
					integer_bits := integer_magnitude(31 downto 0);
					if source(79) = '1' then
						integer_bits := not integer_bits + 1;
					end if;
					case destination_format is
						when FPU_FORMAT_BYTE_INTEGER =>
							output_data(7 downto 0) := std_logic_vector(
								integer_bits(7 downto 0));
						when FPU_FORMAT_WORD_INTEGER =>
							output_data(15 downto 0) := std_logic_vector(
								integer_bits(15 downto 0));
						when others =>
							output_data(31 downto 0) := std_logic_vector(integer_bits);
					end case;
				end if;

			when FPU_FORMAT_PACKED | FPU_FORMAT_DYNAMIC_PACKED =>
				valid := '0';
		end case;

		destination_data <= output_data;
		conversion_valid <= valid;
		exception_status <= status;
	end process;
end architecture;
