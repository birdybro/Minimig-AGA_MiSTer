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

entity TG68K_FPU_Extract is
	port(
		source : in fpu_extended_t;
		get_exponent : in std_logic;
		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU_Extract is
	function highest_set_bit(value : unsigned) return natural is
	begin
		for index in value'high downto value'low loop
			if value(index) = '1' then
				return index;
			end if;
		end loop;
		return 0;
	end function;

	function encode_integer(value : integer) return fpu_extended_t is
		variable encoded : fpu_extended_t := (others => '0');
		variable magnitude : unsigned(15 downto 0) := (others => '0');
		variable leading_position : natural range 0 to 15 := 0;
		variable significand : unsigned(63 downto 0) := (others => '0');
	begin
		if value /= 0 then
			if value < 0 then
				encoded(79) := '1';
				magnitude := to_unsigned(-value, 16);
			else
				magnitude := to_unsigned(value, 16);
			end if;
			leading_position := highest_set_bit(magnitude);
			significand := shift_left(resize(magnitude, 64),
				63 - leading_position);
			encoded(78 downto 64) := std_logic_vector(to_unsigned(
				FPU_EXTENDED_EXPONENT_BIAS + leading_position, 15));
			encoded(63 downto 0) := std_logic_vector(significand);
		end if;
		return encoded;
	end function;

begin
	extract : process(source, get_exponent)
		variable source_class : fpu_data_class_t;
		variable source_significand : unsigned(63 downto 0);
		variable normalized_significand : unsigned(63 downto 0);
		variable source_exponent : integer range -65536 to 65535;
		variable normalization_shift : natural range 0 to 63;
		variable extracted : fpu_extended_t;
		variable status : std_logic_vector(7 downto 0);
	begin
		source_class := fpu_classify(source);
		source_significand := unsigned(source(63 downto 0));
		normalized_significand := source_significand;
		source_exponent := fpu_unbiased_exponent(source);
		normalization_shift := 0;
		extracted := (others => '0');
		status := (others => '0');

		if source_class = FPU_CLASS_QUIET_NAN or
				source_class = FPU_CLASS_SIGNALING_NAN then
			extracted := source;
			extracted(62) := '1';
			if source_class = FPU_CLASS_SIGNALING_NAN then
				status(6) := '1';
			end if;
		elsif source_class = FPU_CLASS_INFINITY then
			extracted := FPU_RESET_NAN;
			status(5) := '1';
		elsif source_class = FPU_CLASS_ZERO or source_significand = 0 then
			extracted(79) := source(79);
		else
			normalization_shift := 63 - highest_set_bit(source_significand);
			normalized_significand := shift_left(source_significand,
				normalization_shift);
			if get_exponent = '1' then
				extracted := encode_integer(source_exponent -
					normalization_shift);
			else
				extracted(79) := source(79);
				extracted(78 downto 64) := std_logic_vector(to_unsigned(
					FPU_EXTENDED_EXPONENT_BIAS, 15));
				extracted(63 downto 0) :=
					std_logic_vector(normalized_significand);
			end if;
		end if;

		result <= extracted;
		condition_codes <= fpu_condition_codes(extracted);
		exception_status <= status;
	end process;
end architecture;
