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

entity TG68K_FPU_Movem_Controller is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		memory_to_register : in std_logic;
		predecrement : in std_logic;
		dynamic_list : in std_logic;
		static_register_list : in std_logic_vector(7 downto 0);
		dynamic_register_data : in std_logic_vector(31 downto 0);
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);

		fp_register_read_data : in fpu_extended_t;
		fp_register_select : out std_logic_vector(2 downto 0);
		fp_register_write : out std_logic;
		fp_register_write_data : out fpu_extended_t;

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
		memory_read_data : in std_logic_vector(15 downto 0);
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_function_code : out std_logic_vector(2 downto 0);

		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Movem_Controller is
	type controller_state_t is (IDLE, SELECT_REGISTER, TRANSFER_WORD,
		REGISTER_COMMIT, BUS_ERROR_WAIT, COMPLETE);

	function register_selected(
		mask : std_logic_vector(7 downto 0);
		register_index : natural;
		decrementing : std_logic) return boolean is
	begin
		if decrementing = '1' then
			return mask(register_index) = '1';
		end if;
		return mask(7 - register_index) = '1';
	end function;

	function register_word(
		value : fpu_extended_t;
		word_index : natural) return std_logic_vector is
	begin
		case word_index is
			when 0 => return value(79 downto 64);
			when 1 => return x"0000";
			when 2 => return value(63 downto 48);
			when 3 => return value(47 downto 32);
			when 4 => return value(31 downto 16);
			when others => return value(15 downto 0);
		end case;
	end function;

	function replace_register_word(
		value : fpu_extended_t;
		word_index : natural;
		word_data : std_logic_vector(15 downto 0)) return fpu_extended_t is
		variable updated : fpu_extended_t := value;
	begin
		case word_index is
			when 0 => updated(79 downto 64) := word_data;
			when 1 => null;
			when 2 => updated(63 downto 48) := word_data;
			when 3 => updated(47 downto 32) := word_data;
			when 4 => updated(31 downto 16) := word_data;
			when others => updated(15 downto 0) := word_data;
		end case;
		return updated;
	end function;

	signal state : controller_state_t := IDLE;
	signal direction_latched : std_logic := '0';
	signal predecrement_latched : std_logic := '0';
	signal mask_latched : std_logic_vector(7 downto 0) := (others => '0');
	signal address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal register_index : natural range 0 to 7 := 7;
	signal word_index : natural range 0 to 5 := 0;
	signal load_data : fpu_extended_t := (others => '0');
begin
	fp_register_select <= std_logic_vector(to_unsigned(register_index, 3));

	outputs : process(state, direction_latched, address_latched,
		function_code_latched, register_index, word_index, load_data,
		fp_register_read_data)
	begin
		fp_register_write <= '0';
		fp_register_write_data <= load_data;
		memory_request <= '0';
		memory_write <= not direction_latched;
		memory_address <= std_logic_vector(unsigned(address_latched) +
			to_unsigned(word_index * 2, 32));
		memory_write_data <= register_word(fp_register_read_data, word_index);
		memory_function_code <= function_code_latched;
		done <= '0';
		bus_error_exception <= '0';
		if state = IDLE then
			busy <= '0';
		else
			busy <= '1';
		end if;

		case state is
			when TRANSFER_WORD => memory_request <= '1';
			when REGISTER_COMMIT => fp_register_write <= '1';
			when BUS_ERROR_WAIT => bus_error_exception <= '1';
			when COMPLETE => done <= '1';
			when others => null;
		end case;
	end process;

	sequencer : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				direction_latched <= '0';
				predecrement_latched <= '0';
				mask_latched <= (others => '0');
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				register_index <= 7;
				word_index <= 0;
				load_data <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							direction_latched <= memory_to_register;
							predecrement_latched <= predecrement;
							if dynamic_list = '1' then
								mask_latched <= dynamic_register_data(7 downto 0);
							else
								mask_latched <= static_register_list;
							end if;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							register_index <= 7;
							word_index <= 0;
							load_data <= (others => '0');
							state <= SELECT_REGISTER;
						end if;

					when SELECT_REGISTER =>
						if register_selected(mask_latched, register_index,
								predecrement_latched) then
							word_index <= 0;
							load_data <= (others => '0');
							if predecrement_latched = '1' then
								address_latched <= std_logic_vector(
									unsigned(address_latched) - 12);
							end if;
							state <= TRANSFER_WORD;
						elsif register_index = 0 then
							state <= COMPLETE;
						else
							register_index <= register_index - 1;
						end if;

					when TRANSFER_WORD =>
						if memory_error = '1' then
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							if direction_latched = '1' then
								load_data <= replace_register_word(load_data,
									word_index, memory_read_data);
							end if;
							if word_index = 5 then
								if direction_latched = '1' then
									state <= REGISTER_COMMIT;
								elsif register_index = 0 then
									state <= COMPLETE;
								else
									if predecrement_latched = '0' then
										address_latched <= std_logic_vector(
											unsigned(address_latched) + 12);
									end if;
									register_index <= register_index - 1;
									state <= SELECT_REGISTER;
								end if;
							else
								word_index <= word_index + 1;
							end if;
						end if;

					when REGISTER_COMMIT =>
						if register_index = 0 then
							state <= COMPLETE;
						else
							address_latched <= std_logic_vector(
								unsigned(address_latched) + 12);
							register_index <= register_index - 1;
							state <= SELECT_REGISTER;
						end if;

					when BUS_ERROR_WAIT =>
						if retry = '1' then
							state <= TRANSFER_WORD;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
