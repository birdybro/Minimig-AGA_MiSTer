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

entity TG68K_FPU_Control_Controller is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		external_to_control : in std_logic;
		register_mask : in std_logic_vector(2 downto 0);
		data_register_direct : in std_logic;
		address_register_direct : in std_logic;
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		data_register_data : in std_logic_vector(31 downto 0);
		address_register_data : in std_logic_vector(31 downto 0);

		control_register_read_data : in std_logic_vector(31 downto 0);
		control_register_select : out fpu_control_register_t;
		control_register_write : out std_logic;
		control_register_write_data : out std_logic_vector(31 downto 0);

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
		resume_context : in std_logic;
		saved_context_in : in std_logic_vector(55 downto 0);
		saved_context_out : out std_logic_vector(55 downto 0);
		memory_read_data : in std_logic_vector(15 downto 0);
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_function_code : out std_logic_vector(2 downto 0);

		data_register_write : out std_logic;
		data_register_write_data : out std_logic_vector(31 downto 0);
		address_register_write : out std_logic;
		address_register_write_data : out std_logic_vector(31 downto 0);
		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Control_Controller is
	type controller_state_t is (IDLE, SELECT_REGISTER, LOAD_HIGH, LOAD_LOW,
		CONTROL_COMMIT, STORE_HIGH, STORE_LOW, DIRECT_STORE, BUS_ERROR_WAIT,
		COMPLETE);

	function selected(mask : std_logic_vector(2 downto 0);
		index : natural) return boolean is
	begin
		return mask(2 - index) = '1';
	end function;

	function control_select(index : natural) return fpu_control_register_t is
	begin
		case index is
			when 0 => return FPU_REG_FPCR;
			when 1 => return FPU_REG_FPSR;
			when others => return FPU_REG_FPIAR;
		end case;
	end function;

	function restored_register_index(
		value : std_logic_vector(1 downto 0)) return natural is
		variable decoded : natural;
	begin
		decoded := to_integer(unsigned(value));
		if decoded <= 2 then
			return decoded;
		end if;
		return 0;
	end function;

	function restored_byte_offset(
		value : std_logic_vector(3 downto 0)) return natural is
		variable decoded : natural;
	begin
		decoded := to_integer(unsigned(value));
		if decoded <= 10 then
			return decoded;
		end if;
		return 0;
	end function;

	signal state : controller_state_t := IDLE;
	signal direction_latched : std_logic := '0';
	signal mask_latched : std_logic_vector(2 downto 0) := (others => '0');
	signal data_direct_latched : std_logic := '0';
	signal address_direct_latched : std_logic := '0';
	signal address_latched : std_logic_vector(31 downto 0) := (others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal direct_data_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal register_index : natural range 0 to 2 := 0;
	signal byte_offset : natural range 0 to 10 := 0;
	signal high_word : std_logic_vector(15 downto 0) := (others => '0');
	signal load_data : std_logic_vector(31 downto 0) := (others => '0');
	signal store_data_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal fault_state : controller_state_t := LOAD_HIGH;
begin
	control_register_select <= control_select(register_index);
	saved_context_out <= store_data_latched & high_word &
		std_logic_vector(to_unsigned(register_index, 2)) &
		std_logic_vector(to_unsigned(byte_offset, 4)) &
		"00" when fault_state = LOAD_HIGH else
		store_data_latched & high_word &
		std_logic_vector(to_unsigned(register_index, 2)) &
		std_logic_vector(to_unsigned(byte_offset, 4)) &
		"01" when fault_state = LOAD_LOW else
		store_data_latched & high_word &
		std_logic_vector(to_unsigned(register_index, 2)) &
		std_logic_vector(to_unsigned(byte_offset, 4)) &
		"10" when fault_state = STORE_HIGH else
		store_data_latched & high_word &
		std_logic_vector(to_unsigned(register_index, 2)) &
		std_logic_vector(to_unsigned(byte_offset, 4)) & "11";

	outputs : process(state, address_latched, byte_offset,
		function_code_latched, high_word, load_data, store_data_latched,
		control_register_read_data,
		data_direct_latched, address_direct_latched)
	begin
		control_register_write <= '0';
		control_register_write_data <= load_data;
		memory_request <= '0';
		memory_write <= '0';
		memory_address <= std_logic_vector(unsigned(address_latched) +
			to_unsigned(byte_offset, 32));
		memory_write_data <= (others => '0');
		memory_function_code <= function_code_latched;
		data_register_write <= '0';
		data_register_write_data <= control_register_read_data;
		address_register_write <= '0';
		address_register_write_data <= control_register_read_data;
		done <= '0';
		bus_error_exception <= '0';
		if state = IDLE then
			busy <= '0';
		else
			busy <= '1';
		end if;

		case state is
			when LOAD_HIGH | LOAD_LOW =>
				memory_request <= '1';
			when CONTROL_COMMIT =>
				control_register_write <= '1';
			when STORE_HIGH =>
				memory_request <= '1';
				memory_write <= '1';
				memory_write_data <= store_data_latched(31 downto 16);
			when STORE_LOW =>
				memory_request <= '1';
				memory_write <= '1';
				memory_write_data <= store_data_latched(15 downto 0);
			when DIRECT_STORE =>
				if data_direct_latched = '1' then
					data_register_write <= '1';
				elsif address_direct_latched = '1' then
					address_register_write <= '1';
				end if;
			when BUS_ERROR_WAIT =>
				bus_error_exception <= '1';
			when COMPLETE =>
				done <= '1';
			when others => null;
		end case;
	end process;

	sequencer : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				direction_latched <= '0';
				mask_latched <= (others => '0');
				data_direct_latched <= '0';
				address_direct_latched <= '0';
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				direct_data_latched <= (others => '0');
				register_index <= 0;
				byte_offset <= 0;
				high_word <= (others => '0');
				load_data <= (others => '0');
				store_data_latched <= (others => '0');
				fault_state <= LOAD_HIGH;
			else
				case state is
					when IDLE =>
						if start = '1' then
							direction_latched <= external_to_control;
							mask_latched <= register_mask;
							data_direct_latched <= data_register_direct;
							address_direct_latched <= address_register_direct;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							if data_register_direct = '1' then
								direct_data_latched <= data_register_data;
							else
								direct_data_latched <= address_register_data;
							end if;
							register_index <= 0;
							byte_offset <= 0;
							if resume_context = '1' then
								store_data_latched <= saved_context_in(55 downto 24);
								high_word <= saved_context_in(23 downto 8);
								register_index <= restored_register_index(
									saved_context_in(7 downto 6));
								byte_offset <= restored_byte_offset(
									saved_context_in(5 downto 2));
								case saved_context_in(1 downto 0) is
									when "00" => fault_state <= LOAD_HIGH;
										state <= LOAD_HIGH;
									when "01" => fault_state <= LOAD_LOW;
										state <= LOAD_LOW;
									when "10" => fault_state <= STORE_HIGH;
										state <= STORE_HIGH;
									when others => fault_state <= STORE_LOW;
										state <= STORE_LOW;
								end case;
							else
								state <= SELECT_REGISTER;
							end if;
						end if;

					when SELECT_REGISTER =>
						if selected(mask_latched, register_index) then
							if data_direct_latched = '1' or
									address_direct_latched = '1' then
								if direction_latched = '1' then
									load_data <= direct_data_latched;
									state <= CONTROL_COMMIT;
								else
									state <= DIRECT_STORE;
								end if;
							elsif direction_latched = '1' then
								state <= LOAD_HIGH;
							else
								store_data_latched <= control_register_read_data;
								state <= STORE_HIGH;
							end if;
						elsif register_index = 2 then
							state <= COMPLETE;
						else
							register_index <= register_index + 1;
						end if;

					when LOAD_HIGH =>
						if memory_error = '1' then
							fault_state <= LOAD_HIGH;
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							high_word <= memory_read_data;
							byte_offset <= byte_offset + 2;
							state <= LOAD_LOW;
						end if;

					when LOAD_LOW =>
						if memory_error = '1' then
							fault_state <= LOAD_LOW;
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							load_data <= high_word & memory_read_data;
							state <= CONTROL_COMMIT;
						end if;

					when CONTROL_COMMIT =>
						if data_direct_latched = '1' or
								address_direct_latched = '1' or register_index = 2 then
							state <= COMPLETE;
						else
							register_index <= register_index + 1;
							byte_offset <= byte_offset + 2;
							state <= SELECT_REGISTER;
						end if;

					when STORE_HIGH =>
						if memory_error = '1' then
							fault_state <= STORE_HIGH;
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							byte_offset <= byte_offset + 2;
							state <= STORE_LOW;
						end if;

					when STORE_LOW =>
						if memory_error = '1' then
							fault_state <= STORE_LOW;
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							if register_index = 2 then
								state <= COMPLETE;
							else
								register_index <= register_index + 1;
								byte_offset <= byte_offset + 2;
								state <= SELECT_REGISTER;
							end if;
						end if;

					when DIRECT_STORE => state <= COMPLETE;

					when BUS_ERROR_WAIT =>
						if retry = '1' then
							state <= fault_state;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
