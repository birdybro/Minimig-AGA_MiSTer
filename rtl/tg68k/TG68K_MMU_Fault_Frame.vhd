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

entity TG68K_MMU_Fault_Frame is
	port(
		long_format : in std_logic;
		word_index : in std_logic_vector(5 downto 0);
		status_register : in std_logic_vector(15 downto 0);
		program_counter : in std_logic_vector(31 downto 0);
		special_status_word : in std_logic_vector(15 downto 0);
		pipe_stage_c : in std_logic_vector(15 downto 0);
		pipe_stage_b : in std_logic_vector(15 downto 0);
		fault_address : in std_logic_vector(31 downto 0);
		data_output_buffer : in std_logic_vector(31 downto 0);
		stage_b_address : in std_logic_vector(31 downto 0);
		data_input_buffer : in std_logic_vector(31 downto 0);
		version : in std_logic_vector(3 downto 0);
		internal_word : in std_logic_vector(15 downto 0);
		frame_word_count : out std_logic_vector(5 downto 0);
		internal_word_select : out std_logic;
		internal_word_index : out std_logic_vector(4 downto 0);
		frame_word : out std_logic_vector(15 downto 0)
	);
end entity;

architecture rtl of TG68K_MMU_Fault_Frame is
begin
	frame_word_count <= std_logic_vector(to_unsigned(46, 6)) when
		long_format = '1' else std_logic_vector(to_unsigned(16, 6));

	format_word : process(long_format, word_index, status_register,
		program_counter, special_status_word, pipe_stage_c, pipe_stage_b,
		fault_address, data_output_buffer, stage_b_address,
		data_input_buffer, version, internal_word)
		variable index : natural range 0 to 63;
		variable internal_index : natural range 0 to 31;
	begin
		index := to_integer(unsigned(word_index));
		internal_index := 0;
		internal_word_select <= '0';
		internal_word_index <= (others => '0');
		frame_word <= (others => '0');

		case index is
			when 0 => frame_word <= status_register;
			when 1 => frame_word <= program_counter(31 downto 16);
			when 2 => frame_word <= program_counter(15 downto 0);
			when 3 =>
				if long_format = '1' then
					frame_word <= x"B008";
				else
					frame_word <= x"A008";
				end if;
			when 5 => frame_word <= special_status_word;
			when 6 => frame_word <= pipe_stage_c;
			when 7 => frame_word <= pipe_stage_b;
			when 8 => frame_word <= fault_address(31 downto 16);
			when 9 => frame_word <= fault_address(15 downto 0);
			when 12 => frame_word <= data_output_buffer(31 downto 16);
			when 13 => frame_word <= data_output_buffer(15 downto 0);
			when 18 =>
				if long_format = '1' then
					frame_word <= stage_b_address(31 downto 16);
				end if;
			when 19 =>
				if long_format = '1' then
					frame_word <= stage_b_address(15 downto 0);
				end if;
			when 22 =>
				if long_format = '1' then
					frame_word <= data_input_buffer(31 downto 16);
				end if;
			when 23 =>
				if long_format = '1' then
					frame_word <= data_input_buffer(15 downto 0);
				end if;
			when others =>
				internal_word_select <= '1';
				case index is
					when 4 => internal_index := 0;
					when 10 | 11 => internal_index := index - 9;
					when 14 | 15 | 16 | 17 => internal_index := index - 11;
					when 20 | 21 => internal_index := index - 13;
					when 24 | 25 | 26 => internal_index := index - 15;
					when 27 => internal_index := 12;
					when 28 to 45 => internal_index := index - 15;
					when others => internal_index := 31;
				end case;
				internal_word_index <= std_logic_vector(to_unsigned(
					internal_index, internal_word_index'length));
				if long_format = '1' and index = 27 then
					frame_word <= version & internal_word(11 downto 0);
				else
					frame_word <= internal_word;
				end if;
		end case;
	end process;
end architecture;
