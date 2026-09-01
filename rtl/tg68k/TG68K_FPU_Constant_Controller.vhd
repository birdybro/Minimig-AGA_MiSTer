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

entity TG68K_FPU_Constant_Controller is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		rom_offset : in std_logic_vector(5 downto 0);
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;

		fp_register_write : out std_logic;
		fp_register_write_data : out fpu_extended_t;
		operation_status_write : out std_logic;
		condition_codes_write : out std_logic;
		operation_condition_codes : out std_logic_vector(3 downto 0);
		operation_exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Constant_Controller is
	type controller_state_t is (IDLE, COMMIT, COMPLETE);
	type constant_tail_t is (TAIL_EXACT, TAIL_BELOW_LSB, TAIL_ABOVE_LSB);
	type constant_entry_t is record
		value : fpu_extended_t;
		tail : constant_tail_t;
	end record;

	function constant_rom(offset : std_logic_vector(5 downto 0))
		return constant_entry_t is
		variable entry : constant_entry_t := (
			value => x"00000000000000000000", tail => TAIL_EXACT);
	begin
		case to_integer(unsigned(offset)) is
			when 16#00# => entry := (x"4000C90FDAA22168C235", TAIL_BELOW_LSB);
			when 16#0B# => entry := (x"3FFD9A209A84FBCFF798", TAIL_ABOVE_LSB);
			when 16#0C# => entry := (x"4000ADF85458A2BB4A9A", TAIL_ABOVE_LSB);
			when 16#0D# => entry := (x"3FFFB8AA3B295C17F0BC", TAIL_BELOW_LSB);
			when 16#0E# => entry := (x"3FFDDE5BD8A937287195", TAIL_EXACT);
			when 16#0F# => entry := (x"00000000000000000000", TAIL_EXACT);
			when 16#30# => entry := (x"3FFEB17217F7D1CF79AC", TAIL_BELOW_LSB);
			when 16#31# => entry := (x"4000935D8DDDAAA8AC17", TAIL_BELOW_LSB);
			when 16#32# => entry := (x"3FFF8000000000000000", TAIL_EXACT);
			when 16#33# => entry := (x"4002A000000000000000", TAIL_EXACT);
			when 16#34# => entry := (x"4005C800000000000000", TAIL_EXACT);
			when 16#35# => entry := (x"400C9C40000000000000", TAIL_EXACT);
			when 16#36# => entry := (x"4019BEBC200000000000", TAIL_EXACT);
			when 16#37# => entry := (x"40348E1BC9BF04000000", TAIL_EXACT);
			when 16#38# => entry := (x"40699DC5ADA82B70B59E", TAIL_BELOW_LSB);
			when 16#39# => entry := (x"40D3C2781F49FFCFA6D5", TAIL_ABOVE_LSB);
			when 16#3A# => entry := (x"41A893BA47C980E98CE0", TAIL_BELOW_LSB);
			when 16#3B# => entry := (x"4351AA7EEBFB9DF9DE8E", TAIL_BELOW_LSB);
			when 16#3C# => entry := (x"46A3E319A0AEA60E91C7", TAIL_BELOW_LSB);
			when 16#3D# => entry := (x"4D48C976758681750C17", TAIL_ABOVE_LSB);
			when 16#3E# => entry := (x"5A929E8B3B5DC53D5DE5", TAIL_BELOW_LSB);
			when 16#3F# => entry := (x"7525C46052028A20979B", TAIL_BELOW_LSB);
			-- Motorola reserves the remaining offsets for internal microcode.
			when others => null;
		end case;
		return entry;
	end function;

	function or_reduce(value : unsigned) return std_logic is
		variable reduced : std_logic := '0';
	begin
		for index in value'range loop
			reduced := reduced or value(index);
		end loop;
		return reduced;
	end function;

	signal state : controller_state_t := IDLE;
	signal offset_latched : std_logic_vector(5 downto 0) := (others => '0');
	signal precision_latched : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal rom_entry : constant_entry_t;
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
begin
	rom_entry <= constant_rom(offset_latched);

	round_constant : process(rom_entry, precision_latched, mode_latched)
		variable exact_significand : unsigned(66 downto 0);
		variable retained_significand : unsigned(63 downto 0);
		variable rounded_sum : unsigned(64 downto 0);
		variable result_value : fpu_extended_t;
		variable discarded : std_logic;
		variable guard : std_logic;
		variable lower_discarded : std_logic;
		variable retained_lsb : std_logic;
		variable increment : boolean;
	begin
		exact_significand := shift_left(resize(unsigned(
			rom_entry.value(63 downto 0)), 67), 3);
		case rom_entry.tail is
			when TAIL_BELOW_LSB =>
				exact_significand := shift_left(resize(unsigned(
					rom_entry.value(63 downto 0)) - 1, 67), 3);
				exact_significand(2 downto 0) := "101";
			when TAIL_ABOVE_LSB => exact_significand(0) := '1';
			when others => null;
		end case;

		retained_significand := exact_significand(66 downto 3);
		case precision_latched is
			when FPU_PRECISION_SINGLE =>
				discarded := or_reduce(exact_significand(42 downto 0));
				guard := exact_significand(42);
				lower_discarded := or_reduce(exact_significand(41 downto 0));
				retained_lsb := exact_significand(43);
				retained_significand(39 downto 0) := (others => '0');
			when FPU_PRECISION_DOUBLE =>
				discarded := or_reduce(exact_significand(13 downto 0));
				guard := exact_significand(13);
				lower_discarded := or_reduce(exact_significand(12 downto 0));
				retained_lsb := exact_significand(14);
				retained_significand(10 downto 0) := (others => '0');
			when others =>
				discarded := or_reduce(exact_significand(2 downto 0));
				guard := exact_significand(2);
				lower_discarded := or_reduce(exact_significand(1 downto 0));
				retained_lsb := exact_significand(3);
		end case;

		case mode_latched is
			when FPU_ROUND_NEAREST =>
				increment := guard = '1' and (lower_discarded = '1' or
					retained_lsb = '1');
			when FPU_ROUND_PLUS_INFINITY => increment := discarded = '1';
			when others => increment := false;
		end case;

		rounded_sum := resize(retained_significand, 65);
		if increment then
			case precision_latched is
				when FPU_PRECISION_SINGLE =>
					rounded_sum := rounded_sum + shift_left(to_unsigned(1, 65), 40);
				when FPU_PRECISION_DOUBLE =>
					rounded_sum := rounded_sum + shift_left(to_unsigned(1, 65), 11);
				when others => rounded_sum := rounded_sum + 1;
			end case;
		end if;

		result_value := rom_entry.value;
		if rom_entry.value(78 downto 0) = (78 downto 0 => '0') then
			result_value := (others => '0');
			discarded := '0';
		elsif rounded_sum(64) = '1' then
			result_value(78 downto 64) := std_logic_vector(
				unsigned(rom_entry.value(78 downto 64)) + 1);
			result_value(63 downto 0) := std_logic_vector(rounded_sum(64 downto 1));
		else
			result_value(63 downto 0) := std_logic_vector(rounded_sum(63 downto 0));
		end if;
		rounded_result <= result_value;
		rounded_inexact <= discarded;
	end process;

	outputs : process(state, rounded_result, rounded_inexact)
		variable status : std_logic_vector(7 downto 0);
	begin
		status := (others => '0');
		status(1) := rounded_inexact;
		fp_register_write <= '0';
		fp_register_write_data <= rounded_result;
		operation_status_write <= '0';
		condition_codes_write <= '0';
		operation_condition_codes <= fpu_condition_codes(rounded_result);
		operation_exception_status <= status;
		busy <= '0';
		done <= '0';
		case state is
			when IDLE => null;
			when COMMIT =>
				busy <= '1';
				fp_register_write <= '1';
				operation_status_write <= '1';
				condition_codes_write <= '1';
			when COMPLETE =>
				busy <= '1';
				done <= '1';
		end case;
	end process;

	sequencer : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				offset_latched <= (others => '0');
				precision_latched <= FPU_PRECISION_EXTENDED;
				mode_latched <= FPU_ROUND_NEAREST;
			else
				case state is
					when IDLE =>
						if start = '1' then
							offset_latched <= rom_offset;
							precision_latched <= rounding_precision;
							mode_latched <= rounding_mode;
							state <= COMMIT;
						end if;
					when COMMIT => state <= COMPLETE;
					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
