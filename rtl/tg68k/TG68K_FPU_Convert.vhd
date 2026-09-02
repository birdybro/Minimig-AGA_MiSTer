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

entity TG68K_FPU_Convert is
	port(
		source_format : in fpu_operand_format_t;
		source_data : in std_logic_vector(95 downto 0);
		extended_data : out fpu_extended_t;
		conversion_valid : out std_logic;

		extended_source : in fpu_extended_t;
		external_extended_data : out std_logic_vector(95 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Convert is
	function highest_set_bit(value : unsigned(63 downto 0)) return natural is
	begin
		for index in 63 downto 0 loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;
begin
	external_extended_data <= extended_source(79 downto 64) &
		x"0000" & extended_source(63 downto 0);

	unpack : process(source_format, source_data)
		variable result : fpu_extended_t;
		variable valid : std_logic;
		variable signed_integer : signed(31 downto 0);
		variable magnitude : unsigned(31 downto 0);
		variable significand : unsigned(63 downto 0);
		variable fraction_single : unsigned(22 downto 0);
		variable fraction_double : unsigned(51 downto 0);
		variable exponent_value : natural range 0 to FPU_EXTENDED_EXPONENT_MAX;
		variable source_exponent : natural range 0 to FPU_EXTENDED_EXPONENT_MAX;
		variable leading_position : natural range 0 to 63;
		variable shift_count : natural range 0 to 63;
		variable normalize_significand : boolean;
	begin
		result := FPU_RESET_NAN;
		valid := '1';
		signed_integer := (others => '0');
		magnitude := (others => '0');
		significand := (others => '0');
		fraction_single := (others => '0');
		fraction_double := (others => '0');
		exponent_value := 0;
		source_exponent := 0;
		leading_position := 0;
		shift_count := 0;
		normalize_significand := false;

		case source_format is
			when FPU_FORMAT_BYTE_INTEGER | FPU_FORMAT_WORD_INTEGER |
					FPU_FORMAT_LONG_INTEGER =>
				case source_format is
					when FPU_FORMAT_BYTE_INTEGER =>
						signed_integer := resize(signed(source_data(7 downto 0)), 32);
					when FPU_FORMAT_WORD_INTEGER =>
						signed_integer := resize(signed(source_data(15 downto 0)), 32);
					when others =>
						signed_integer := signed(source_data(31 downto 0));
				end case;
				if signed_integer = 0 then
					result := (others => '0');
				else
					result := (others => '0');
					result(79) := signed_integer(31);
					if signed_integer(31) = '1' then
						magnitude := unsigned(-signed_integer);
					else
						magnitude := unsigned(signed_integer);
					end if;
					significand := resize(magnitude, 64);
					leading_position := highest_set_bit(significand);
					shift_count := 63 - leading_position;
					normalize_significand := true;
					exponent_value := FPU_EXTENDED_EXPONENT_BIAS +
						leading_position;
					result(78 downto 64) := std_logic_vector(
						to_unsigned(exponent_value, 15));
				end if;

			when FPU_FORMAT_SINGLE =>
				result := (others => '0');
				result(79) := source_data(31);
				fraction_single := unsigned(source_data(22 downto 0));
				source_exponent := to_integer(unsigned(source_data(30 downto 23)));
				if source_exponent = 0 then
					if fraction_single /= 0 then
						significand := resize(fraction_single, 64);
						leading_position := highest_set_bit(significand);
						shift_count := 63 - leading_position;
						normalize_significand := true;
						exponent_value := FPU_EXTENDED_EXPONENT_BIAS +
							leading_position - 149;
						result(78 downto 64) := std_logic_vector(
							to_unsigned(exponent_value, 15));
					end if;
				elsif source_exponent = 255 then
					result(78 downto 64) := (others => '1');
					result(63) := '1';
					result(62 downto 40) := std_logic_vector(fraction_single);
				else
					exponent_value := source_exponent - 127 +
						FPU_EXTENDED_EXPONENT_BIAS;
					result(78 downto 64) := std_logic_vector(
						to_unsigned(exponent_value, 15));
					result(63) := '1';
					result(62 downto 40) := std_logic_vector(fraction_single);
				end if;

			when FPU_FORMAT_DOUBLE =>
				result := (others => '0');
				result(79) := source_data(63);
				fraction_double := unsigned(source_data(51 downto 0));
				source_exponent := to_integer(unsigned(source_data(62 downto 52)));
				if source_exponent = 0 then
					if fraction_double /= 0 then
						significand := resize(fraction_double, 64);
						leading_position := highest_set_bit(significand);
						shift_count := 63 - leading_position;
						normalize_significand := true;
						exponent_value := FPU_EXTENDED_EXPONENT_BIAS +
							leading_position - 1074;
						result(78 downto 64) := std_logic_vector(
							to_unsigned(exponent_value, 15));
					end if;
				elsif source_exponent = 2047 then
					result(78 downto 64) := (others => '1');
					result(63) := '1';
					result(62 downto 11) := std_logic_vector(fraction_double);
				else
					exponent_value := source_exponent - 1023 +
						FPU_EXTENDED_EXPONENT_BIAS;
					result(78 downto 64) := std_logic_vector(
						to_unsigned(exponent_value, 15));
					result(63) := '1';
					result(62 downto 11) := std_logic_vector(fraction_double);
				end if;

			when FPU_FORMAT_EXTENDED =>
				result := source_data(95 downto 80) & source_data(63 downto 0);
				source_exponent := to_integer(unsigned(source_data(94 downto 80)));
				significand := unsigned(source_data(63 downto 0));
				if source_exponent > 0 and
						source_exponent < FPU_EXTENDED_EXPONENT_MAX and
						significand(63) = '0' then
					if significand = 0 then
						result(78 downto 0) := (others => '0');
					else
						leading_position := highest_set_bit(significand);
						shift_count := 63 - leading_position;
						if source_exponent >= shift_count then
							exponent_value := source_exponent - shift_count;
						else
							shift_count := source_exponent;
							exponent_value := 0;
						end if;
						normalize_significand := true;
						result(78 downto 64) := std_logic_vector(
							to_unsigned(exponent_value, 15));
					end if;
				end if;

			when FPU_FORMAT_PACKED | FPU_FORMAT_DYNAMIC_PACKED =>
				valid := '0';
		end case;
		if normalize_significand then
			result(63 downto 0) := std_logic_vector(
				shift_left(significand, shift_count));
		end if;

		extended_data <= result;
		conversion_valid <= valid;
	end process;
end architecture;
