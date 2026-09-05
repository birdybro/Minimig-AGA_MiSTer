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
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		rom_offset : in std_logic_vector(5 downto 0);
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		external_rounded_result : in fpu_extended_t := (others => '0');
		external_rounded_inexact : in std_logic := '0';
		round_input : out fpu_round_input_t;
		rounding_precision_out : out fpu_rounding_precision_t;
		rounding_mode_out : out fpu_rounding_mode_t;

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
	subtype constant_word_t is std_logic_vector(81 downto 0);
	type constant_rom_t is array(0 to 63) of constant_word_t;
	constant TAIL_EXACT_BITS : std_logic_vector(1 downto 0) := "00";
	constant TAIL_BELOW_LSB_BITS : std_logic_vector(1 downto 0) := "01";
	constant TAIL_ABOVE_LSB_BITS : std_logic_vector(1 downto 0) := "10";
	signal constant_rom : constant_rom_t := (
		16#00# => TAIL_BELOW_LSB_BITS & x"4000C90FDAA22168C235",
		16#0B# => TAIL_ABOVE_LSB_BITS & x"3FFD9A209A84FBCFF798",
		16#0C# => TAIL_ABOVE_LSB_BITS & x"4000ADF85458A2BB4A9A",
		16#0D# => TAIL_BELOW_LSB_BITS & x"3FFFB8AA3B295C17F0BC",
		16#0E# => TAIL_EXACT_BITS & x"3FFDDE5BD8A937287195",
		16#0F# => TAIL_EXACT_BITS & x"00000000000000000000",
		16#30# => TAIL_BELOW_LSB_BITS & x"3FFEB17217F7D1CF79AC",
		16#31# => TAIL_BELOW_LSB_BITS & x"4000935D8DDDAAA8AC17",
		16#32# => TAIL_EXACT_BITS & x"3FFF8000000000000000",
		16#33# => TAIL_EXACT_BITS & x"4002A000000000000000",
		16#34# => TAIL_EXACT_BITS & x"4005C800000000000000",
		16#35# => TAIL_EXACT_BITS & x"400C9C40000000000000",
		16#36# => TAIL_EXACT_BITS & x"4019BEBC200000000000",
		16#37# => TAIL_EXACT_BITS & x"40348E1BC9BF04000000",
		16#38# => TAIL_BELOW_LSB_BITS & x"40699DC5ADA82B70B59E",
		16#39# => TAIL_ABOVE_LSB_BITS & x"40D3C2781F49FFCFA6D5",
		16#3A# => TAIL_BELOW_LSB_BITS & x"41A893BA47C980E98CE0",
		16#3B# => TAIL_BELOW_LSB_BITS & x"4351AA7EEBFB9DF9DE8E",
		16#3C# => TAIL_BELOW_LSB_BITS & x"46A3E319A0AEA60E91C7",
		16#3D# => TAIL_ABOVE_LSB_BITS & x"4D48C976758681750C17",
		16#3E# => TAIL_BELOW_LSB_BITS & x"5A929E8B3B5DC53D5DE5",
		16#3F# => TAIL_BELOW_LSB_BITS & x"7525C46052028A20979B",
		-- Motorola reserves the remaining offsets for internal microcode.
		others => (others => '0')
	);

	signal state : controller_state_t := IDLE;
	signal precision_latched : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
	signal mode_latched : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
	signal rom_word : constant_word_t := (others => '0');
	signal rom_value : fpu_extended_t;
	signal rom_tail : constant_tail_t;
	signal constant_class : fpu_data_class_t;
	signal constant_exponent : signed(16 downto 0);
	signal exact_significand : unsigned(66 downto 0);
	signal rounded_result : fpu_extended_t;
	signal rounded_inexact : std_logic;
	attribute ramstyle : string;
	attribute ramstyle of constant_rom : signal is "M10K";
begin
	rom_value <= rom_word(79 downto 0);
	with rom_word(81 downto 80) select rom_tail <=
		TAIL_BELOW_LSB when TAIL_BELOW_LSB_BITS,
		TAIL_ABOVE_LSB when TAIL_ABOVE_LSB_BITS,
		TAIL_EXACT when others;
	constant_class <= fpu_classify(rom_value);
	round_input.data_class <= constant_class;
	round_input.sign <= rom_value(79);
	round_input.exponent <= constant_exponent;
	round_input.significand <= exact_significand;
	round_input.special <= rom_value;
	rounding_precision_out <= precision_latched;
	rounding_mode_out <= mode_latched;
	read_constant : process(clk)
	begin
		if rising_edge(clk) then
			rom_word <= constant_rom(to_integer(unsigned(rom_offset)));
		end if;
	end process;

	prepare_constant : process(rom_value, rom_tail, constant_class)
		variable prepared_significand : unsigned(66 downto 0);
		variable exponent_value : integer range -16383 to 16383;
	begin
		prepared_significand := shift_left(resize(unsigned(
			rom_value(63 downto 0)), 67), 3);
		case rom_tail is
			when TAIL_BELOW_LSB =>
				prepared_significand := shift_left(resize(unsigned(
					rom_value(63 downto 0)) - 1, 67), 3);
				prepared_significand(2 downto 0) := "101";
			when TAIL_ABOVE_LSB => prepared_significand(0) := '1';
			when others => null;
		end case;
		exact_significand <= prepared_significand;
		if constant_class = FPU_CLASS_NORMAL then
			exponent_value := to_integer(unsigned(rom_value(78 downto 64))) -
				FPU_EXTENDED_EXPONENT_BIAS;
		else
			exponent_value := 0;
		end if;
		constant_exponent <= to_signed(exponent_value, 17);
	end process;

	with_rounding : if INCLUDE_ROUNDING_STAGE generate
		rounder : entity work.TG68K_FPU_Round
			port map(
				input_class => constant_class,
				input_sign => rom_value(79),
				input_exponent => constant_exponent,
				input_significand => exact_significand,
				special_value => rom_value,
				rounding_precision => precision_latched,
				rounding_mode => mode_latched,
				extended_exponent_range => '1',
				result => rounded_result,
				inexact => rounded_inexact,
				overflow => open,
				underflow => open,
				signaling_nan => open
			);
	end generate;

	without_rounding : if not INCLUDE_ROUNDING_STAGE generate
		rounded_result <= external_rounded_result;
		rounded_inexact <= external_rounded_inexact;
	end generate;

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
				precision_latched <= FPU_PRECISION_EXTENDED;
				mode_latched <= FPU_ROUND_NEAREST;
			else
				case state is
					when IDLE =>
						if start = '1' then
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
