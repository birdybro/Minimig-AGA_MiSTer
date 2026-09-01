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

entity TG68K_FPU_State_Frame_Controller is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		family : in fpu_instruction_family_t;
		initialized : in std_logic;
		exception_pending : in std_logic;
		command_condition : in std_logic_vector(31 downto 0);
		exceptional_operand : in fpu_extended_t;
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
		memory_read_data : in std_logic_vector(15 downto 0);
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_nuds : out std_logic;
		memory_nlds : out std_logic;
		memory_function_code : out std_logic_vector(2 downto 0);

		frame_byte_count : out natural range 0 to
			FPU_STATE_FRAME_IDLE_BYTES_68882;
		save_complete : out std_logic;
		restore_null : out std_logic;
		restore_idle : out std_logic;
		restore_exception_pending : out std_logic;
		restore_command_condition : out std_logic_vector(31 downto 0);
		restore_exceptional_operand : out fpu_extended_t;
		format_error_exception : out std_logic;
		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_State_Frame_Controller is
	constant NULL_WORD_COUNT : natural := FPU_STATE_FRAME_NULL_BYTES / 2;
	constant IDLE_WORD_COUNT : natural :=
		FPU_STATE_FRAME_IDLE_BYTES_68882 / 2;
	type controller_state_t is (IDLE, SAVE_TRANSFER, RESTORE_TRANSFER,
		BUS_ERROR_WAIT, COMPLETE);
	signal state : controller_state_t := IDLE;
	signal resume_state : controller_state_t := IDLE;
	signal family_latched : fpu_instruction_family_t := FPU_FAMILY_NONE;
	signal address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal pending_latched : std_logic := '0';
	signal command_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal exceptional_latched : fpu_extended_t := (others => '0');
	signal transfer_index : natural range 0 to IDLE_WORD_COUNT - 1 := 0;
	signal word_count_latched : natural range NULL_WORD_COUNT to
		IDLE_WORD_COUNT := NULL_WORD_COUNT;
	signal frame_bytes_latched : natural range 0 to
		FPU_STATE_FRAME_IDLE_BYTES_68882 := 0;
	signal format_high_latched : std_logic_vector(15 downto 0) :=
		(others => '0');
	signal restore_command_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal restore_exceptional_latched : fpu_extended_t := (others => '0');
	signal restore_pending_latched : std_logic := '0';
	signal restore_null_latched : std_logic := '0';
	signal restore_idle_latched : std_logic := '0';
	signal format_error_latched : std_logic := '0';

	function save_frame_word(
		frame_word_index : natural;
		word_count : natural;
		pending_value : std_logic;
		command_value : std_logic_vector(31 downto 0);
		exceptional_value : fpu_extended_t)
		return std_logic_vector is
	begin
		case frame_word_index is
			when 0 =>
				if word_count = NULL_WORD_COUNT then
					return x"00" & std_logic_vector(to_unsigned(
						FPU_STATE_FRAME_IDLE_SIZE_68882, 8));
				end if;
				return FPU_STATE_FRAME_VERSION_68882 &
					std_logic_vector(to_unsigned(
					FPU_STATE_FRAME_IDLE_SIZE_68882, 8));
			when 1 => return x"0000";
			when 2 => return command_value(31 downto 16);
			when 3 => return command_value(15 downto 0);
			when 20 => return exceptional_value(79 downto 64);
			when 21 => return x"0000";
			when 22 => return exceptional_value(63 downto 48);
			when 23 => return exceptional_value(47 downto 32);
			when 24 => return exceptional_value(31 downto 16);
			when 25 => return exceptional_value(15 downto 0);
			when 28 =>
				if pending_value = '1' then
					return FPU_STATE_FRAME_BIU_EXCEPTION(31 downto 16);
				end if;
				return FPU_STATE_FRAME_BIU_IDLE(31 downto 16);
			when 29 => return FPU_STATE_FRAME_BIU_IDLE(15 downto 0);
			when others => return x"0000";
		end case;
	end function;

	function save_transfer_frame_index(
		sequence_index : natural;
		word_count : natural) return natural is
		variable longword_index : natural;
	begin
		if sequence_index < 2 then
			return sequence_index;
		end if;
		longword_index := word_count / 2 - 1 - (sequence_index - 2) / 2;
		return longword_index * 2 + (sequence_index mod 2);
	end function;
begin
	outputs : process(state, family_latched, address_latched,
		function_code_latched, pending_latched, command_latched,
		exceptional_latched, transfer_index, word_count_latched,
		frame_bytes_latched, restore_command_latched,
		restore_exceptional_latched, restore_pending_latched,
		restore_null_latched, restore_idle_latched, format_error_latched)
		variable frame_word_index : natural range 0 to IDLE_WORD_COUNT - 1;
	begin
		frame_word_index := transfer_index;
		if state = SAVE_TRANSFER then
			frame_word_index := save_transfer_frame_index(transfer_index,
				word_count_latched);
		end if;

		memory_request <= '0';
		memory_write <= '0';
		memory_address <= std_logic_vector(unsigned(address_latched) +
			to_unsigned(frame_word_index * 2, 32));
		memory_write_data <= save_frame_word(frame_word_index,
			word_count_latched, pending_latched, command_latched,
			exceptional_latched);
		memory_nuds <= '0';
		memory_nlds <= '0';
		memory_function_code <= function_code_latched;
		frame_byte_count <= frame_bytes_latched;
		save_complete <= '0';
		restore_null <= '0';
		restore_idle <= '0';
		restore_exception_pending <= restore_pending_latched;
		restore_command_condition <= restore_command_latched;
		restore_exceptional_operand <= restore_exceptional_latched;
		format_error_exception <= '0';
		done <= '0';
		bus_error_exception <= '0';
		if state = IDLE then
			busy <= '0';
		else
			busy <= '1';
		end if;

		case state is
			when SAVE_TRANSFER =>
				memory_request <= '1';
				memory_write <= '1';
			when RESTORE_TRANSFER =>
				memory_request <= '1';
			when BUS_ERROR_WAIT =>
				bus_error_exception <= '1';
			when COMPLETE =>
				done <= '1';
				format_error_exception <= format_error_latched;
				if format_error_latched = '0' then
					if family_latched = FPU_FAMILY_SAVE then
						save_complete <= '1';
					else
						restore_null <= restore_null_latched;
						restore_idle <= restore_idle_latched;
					end if;
				end if;
			when others => null;
		end case;
	end process;

	sequencer : process(clk)
		variable format_value : std_logic_vector(31 downto 0);
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				resume_state <= IDLE;
				family_latched <= FPU_FAMILY_NONE;
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				pending_latched <= '0';
				command_latched <= (others => '0');
				exceptional_latched <= (others => '0');
				transfer_index <= 0;
				word_count_latched <= NULL_WORD_COUNT;
				frame_bytes_latched <= 0;
				format_high_latched <= (others => '0');
				restore_command_latched <= (others => '0');
				restore_exceptional_latched <= (others => '0');
				restore_pending_latched <= '0';
				restore_null_latched <= '0';
				restore_idle_latched <= '0';
				format_error_latched <= '0';
			else
				case state is
					when IDLE =>
						if start = '1' then
							family_latched <= family;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							pending_latched <= exception_pending;
							command_latched <= command_condition;
							exceptional_latched <= exceptional_operand;
							transfer_index <= 0;
							restore_command_latched <= (others => '0');
							restore_exceptional_latched <= (others => '0');
							restore_pending_latched <= '0';
							restore_null_latched <= '0';
							restore_idle_latched <= '0';
							format_error_latched <= '0';
							if family = FPU_FAMILY_SAVE then
								if initialized = '1' then
									word_count_latched <= IDLE_WORD_COUNT;
									frame_bytes_latched <=
										FPU_STATE_FRAME_IDLE_BYTES_68882;
								else
									word_count_latched <= NULL_WORD_COUNT;
									frame_bytes_latched <=
										FPU_STATE_FRAME_NULL_BYTES;
								end if;
								state <= SAVE_TRANSFER;
							else
								word_count_latched <= NULL_WORD_COUNT;
								frame_bytes_latched <=
									FPU_STATE_FRAME_NULL_BYTES;
								state <= RESTORE_TRANSFER;
							end if;
						end if;

					when SAVE_TRANSFER =>
						if memory_error = '1' then
							resume_state <= SAVE_TRANSFER;
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							if transfer_index + 1 = word_count_latched then
								state <= COMPLETE;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when RESTORE_TRANSFER =>
						if memory_error = '1' then
							resume_state <= RESTORE_TRANSFER;
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							case transfer_index is
								when 0 => format_high_latched <= memory_read_data;
								when 2 =>
									restore_command_latched(31 downto 16) <=
										memory_read_data;
								when 3 =>
									restore_command_latched(15 downto 0) <=
										memory_read_data;
								when 20 =>
									restore_exceptional_latched(79 downto 64) <=
										memory_read_data;
								when 22 =>
									restore_exceptional_latched(63 downto 48) <=
										memory_read_data;
								when 23 =>
									restore_exceptional_latched(47 downto 32) <=
										memory_read_data;
								when 24 =>
									restore_exceptional_latched(31 downto 16) <=
										memory_read_data;
								when 25 =>
									restore_exceptional_latched(15 downto 0) <=
										memory_read_data;
								when 28 =>
									restore_pending_latched <= not memory_read_data(11);
								when others => null;
							end case;

							if transfer_index = 1 then
								format_value := format_high_latched & memory_read_data;
								if format_value(31 downto 24) = x"00" then
									restore_null_latched <= '1';
									frame_bytes_latched <=
										FPU_STATE_FRAME_NULL_BYTES;
									state <= COMPLETE;
								elsif format_value(31 downto 24) =
										FPU_STATE_FRAME_VERSION_68882 and
										format_value(23 downto 16) =
										std_logic_vector(to_unsigned(
										FPU_STATE_FRAME_IDLE_SIZE_68882, 8)) then
									restore_idle_latched <= '1';
									word_count_latched <= IDLE_WORD_COUNT;
									frame_bytes_latched <=
										FPU_STATE_FRAME_IDLE_BYTES_68882;
									transfer_index <= transfer_index + 1;
								else
									format_error_latched <= '1';
									state <= COMPLETE;
								end if;
							elsif transfer_index + 1 = word_count_latched then
								state <= COMPLETE;
							else
								transfer_index <= transfer_index + 1;
							end if;
						end if;

					when BUS_ERROR_WAIT =>
						if retry = '1' then
							state <= resume_state;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
