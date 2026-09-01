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

entity TG68K_FPU_Conditional_Controller is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		family : in fpu_instruction_family_t;
		predicate : in std_logic_vector(5 downto 0);
		condition_codes : in std_logic_vector(3 downto 0);
		bsun_enable : in std_logic;
		data_register_direct : in std_logic;
		integer_register_data : in std_logic_vector(31 downto 0);
		effective_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);

		memory_ready : in std_logic;
		memory_error : in std_logic;
		retry : in std_logic;
		memory_request : out std_logic;
		memory_write : out std_logic;
		memory_address : out std_logic_vector(31 downto 0);
		memory_write_data : out std_logic_vector(15 downto 0);
		memory_nuds : out std_logic;
		memory_nlds : out std_logic;
		memory_function_code : out std_logic_vector(2 downto 0);

		integer_register_write : out std_logic;
		integer_register_write_data : out std_logic_vector(31 downto 0);
		integer_register_write_format : out fpu_operand_format_t;
		conditional_status_write : out std_logic;
		conditional_bsun : out std_logic;
		condition_result : out std_logic;
		branch_taken : out std_logic;
		trap_taken : out std_logic;
		busy : out std_logic;
		done : out std_logic;
		bus_error_exception : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Conditional_Controller is
	type controller_state_t is (IDLE, UPDATE_STATUS, STORE_MEMORY,
		WRITE_REGISTER, BUS_ERROR_WAIT, COMPLETE);
	signal state : controller_state_t := IDLE;
	signal family_latched : fpu_instruction_family_t := FPU_FAMILY_NONE;
	signal condition_latched : std_logic := '0';
	signal bsun_latched : std_logic := '0';
	signal bsun_trap_latched : std_logic := '0';
	signal data_register_latched : std_logic := '0';
	signal integer_data_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal address_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal evaluated_condition : std_logic;
	signal evaluated_bsun : std_logic;
begin
	evaluator : entity work.TG68K_FPU_Condition
		port map(
			predicate => predicate,
			condition_codes => condition_codes,
			condition_true => evaluated_condition,
			bsun => evaluated_bsun
		);

	outputs : process(state, family_latched, condition_latched,
		bsun_latched, bsun_trap_latched, data_register_latched,
		integer_data_latched, address_latched, function_code_latched)
		variable byte_result : std_logic_vector(7 downto 0);
		variable decremented : unsigned(15 downto 0);
	begin
		if condition_latched = '1' then
			byte_result := x"FF";
		else
			byte_result := x"00";
		end if;
		decremented := unsigned(integer_data_latched(15 downto 0)) - 1;

		memory_request <= '0';
		memory_write <= '0';
		memory_address <= address_latched;
		memory_write_data <= byte_result & byte_result;
		memory_nuds <= '1';
		memory_nlds <= '1';
		memory_function_code <= function_code_latched;
		integer_register_write <= '0';
		integer_register_write_data <= (others => '0');
		integer_register_write_format <= FPU_FORMAT_BYTE_INTEGER;
		if family_latched = FPU_FAMILY_DBCC then
			integer_register_write_data(15 downto 0) <=
				std_logic_vector(decremented);
			integer_register_write_format <= FPU_FORMAT_WORD_INTEGER;
		else
			integer_register_write_data(7 downto 0) <= byte_result;
		end if;
		conditional_status_write <= '0';
		conditional_bsun <= bsun_latched;
		condition_result <= condition_latched;
		branch_taken <= '0';
		trap_taken <= '0';
		done <= '0';
		bus_error_exception <= '0';
		if state = IDLE then
			busy <= '0';
		else
			busy <= '1';
		end if;

		case state is
			when UPDATE_STATUS =>
				conditional_status_write <= '1';

			when STORE_MEMORY =>
				memory_request <= '1';
				memory_write <= '1';
				if address_latched(0) = '0' then
					memory_nuds <= '0';
				else
					memory_nlds <= '0';
				end if;

			when WRITE_REGISTER =>
				integer_register_write <= '1';

			when BUS_ERROR_WAIT =>
				bus_error_exception <= '1';

			when COMPLETE =>
				done <= '1';
				if bsun_trap_latched = '0' then
					if family_latched = FPU_FAMILY_BCC_WORD or
							family_latched = FPU_FAMILY_BCC_LONG then
						branch_taken <= condition_latched;
					elsif family_latched = FPU_FAMILY_DBCC and
							condition_latched = '0' and decremented /= x"FFFF" then
						branch_taken <= '1';
					elsif family_latched = FPU_FAMILY_TRAPCC then
						trap_taken <= condition_latched;
					end if;
				end if;

			when others => null;
		end case;
	end process;

	sequencer : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				family_latched <= FPU_FAMILY_NONE;
				condition_latched <= '0';
				bsun_latched <= '0';
				bsun_trap_latched <= '0';
				data_register_latched <= '0';
				integer_data_latched <= (others => '0');
				address_latched <= (others => '0');
				function_code_latched <= (others => '0');
			else
				case state is
					when IDLE =>
						if start = '1' then
							family_latched <= family;
							condition_latched <= evaluated_condition;
							bsun_latched <= evaluated_bsun;
							bsun_trap_latched <= evaluated_bsun and bsun_enable;
							data_register_latched <= data_register_direct;
							integer_data_latched <= integer_register_data;
							address_latched <= effective_address;
							function_code_latched <= function_code;
							state <= UPDATE_STATUS;
						end if;

					when UPDATE_STATUS =>
						if bsun_trap_latched = '1' then
							state <= COMPLETE;
						elsif family_latched = FPU_FAMILY_SCC then
							if data_register_latched = '1' then
								state <= WRITE_REGISTER;
							else
								state <= STORE_MEMORY;
							end if;
						elsif family_latched = FPU_FAMILY_DBCC and
								condition_latched = '0' then
							state <= WRITE_REGISTER;
						else
							state <= COMPLETE;
						end if;

					when STORE_MEMORY =>
						if memory_error = '1' then
							state <= BUS_ERROR_WAIT;
						elsif memory_ready = '1' then
							state <= COMPLETE;
						end if;

					when WRITE_REGISTER => state <= COMPLETE;

					when BUS_ERROR_WAIT =>
						if retry = '1' then
							state <= STORE_MEMORY;
						end if;

					when COMPLETE => state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
