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
use work.TG68K_MMU_Pack.all;

entity TG68K_MMU_Translation is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		logical_address : in std_logic_vector(31 downto 0);
		function_code : in std_logic_vector(2 downto 0);
		write_access : in std_logic;
		read_modify_write : in std_logic;
		tc : in mmu_tc_t;
		tt0 : in mmu_tt_t;
		tt1 : in mmu_tt_t;

		atc_lookup_match : in std_logic;
		atc_lookup_hit : in std_logic;
		atc_lookup_requires_walk : in std_logic;
		atc_lookup_physical_address : in std_logic_vector(31 downto 0);
		atc_lookup_cache_inhibit : in std_logic;
		atc_lookup_write_protected : in std_logic;
		atc_lookup_modified : in std_logic;
		atc_lookup_bus_error : in std_logic;
		atc_lookup_request : out std_logic;
		atc_lookup_address : out std_logic_vector(31 downto 0);
		atc_lookup_function_code : out std_logic_vector(2 downto 0);
		atc_lookup_write : out std_logic;
		atc_fill_request : out std_logic;
		atc_fill_logical_address : out std_logic_vector(31 downto 0);
		atc_fill_function_code : out std_logic_vector(2 downto 0);
		atc_fill_physical_address : out std_logic_vector(31 downto 0);
		atc_fill_cache_inhibit : out std_logic;
		atc_fill_write_protected : out std_logic;
		atc_fill_modified : out std_logic;
		atc_fill_bus_error : out std_logic;

		walker_done : in std_logic;
		walker_mapping_valid : in std_logic;
		walker_physical_address : in std_logic_vector(31 downto 0);
		walker_cache_inhibit : in std_logic;
		walker_write_protected : in std_logic;
		walker_supervisor_violation : in std_logic;
		walker_modified : in std_logic;
		walker_invalid_descriptor : in std_logic;
		walker_limit_violation : in std_logic;
		walker_bus_error : in std_logic;
		walker_fault_descriptor_address : in std_logic_vector(31 downto 0);
		walker_fault_during_update : in std_logic;
		walker_start : out std_logic;
		walker_logical_address : out std_logic_vector(31 downto 0);
		walker_function_code : out std_logic_vector(2 downto 0);
		walker_write_access : out std_logic;

		busy : out std_logic;
		done : out std_logic;
		physical_address : out std_logic_vector(31 downto 0);
		cache_inhibit : out std_logic;
		translation_bypassed : out std_logic;
		translation_atc_hit : out std_logic;
		translation_table_walk : out std_logic;
		fault : out std_logic;
		fault_from_atc : out std_logic;
		fault_bus_error : out std_logic;
		fault_invalid : out std_logic;
		fault_limit : out std_logic;
		fault_supervisor : out std_logic;
		fault_write_protect : out std_logic;
		fault_descriptor_address : out std_logic_vector(31 downto 0);
		fault_during_update : out std_logic
	);
end entity;

architecture rtl of TG68K_MMU_Translation is
	type translation_state_t is (IDLE, CLASSIFY, LOOKUP, WALK_START,
		WALK_WAIT, FILL, COMPLETE);
	signal state : translation_state_t := IDLE;
	signal logical_address_latched : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal function_code_latched : std_logic_vector(2 downto 0) :=
		(others => '0');
	signal write_access_latched : std_logic := '0';
	signal read_modify_write_latched : std_logic := '0';
	signal physical_address_reg : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal cache_inhibit_reg : std_logic := '0';
	signal bypassed_reg : std_logic := '0';
	signal atc_hit_reg : std_logic := '0';
	signal table_walk_reg : std_logic := '0';
	signal fault_reg : std_logic := '0';
	signal fault_from_atc_reg : std_logic := '0';
	signal fault_bus_error_reg : std_logic := '0';
	signal fault_invalid_reg : std_logic := '0';
	signal fault_limit_reg : std_logic := '0';
	signal fault_supervisor_reg : std_logic := '0';
	signal fault_write_protect_reg : std_logic := '0';
	signal fault_descriptor_address_reg : std_logic_vector(31 downto 0) :=
		(others => '0');
	signal fault_during_update_reg : std_logic := '0';
	signal fill_write_protected_reg : std_logic := '0';
	signal fill_bus_error_reg : std_logic := '0';
	signal transparent_match : std_logic;
	signal transparent_bypass : std_logic;
	signal transparent_cache_inhibit : std_logic;
begin
	transparent : entity work.TG68K_MMU_Transparent
		port map(
			logical_address => logical_address_latched,
			function_code => function_code_latched,
			write_access => write_access_latched,
			read_modify_write => read_modify_write_latched,
			tt0 => tt0,
			tt1 => tt1,
			cpu_space_access => open,
			tt0_match => open,
			tt1_match => open,
			transparent_match => transparent_match,
			translation_bypass => transparent_bypass,
			physical_address => open,
			cache_inhibit => transparent_cache_inhibit
		);

	busy <= '1' when state /= IDLE else '0';
	done <= '1' when state = COMPLETE else '0';
	physical_address <= physical_address_reg;
	cache_inhibit <= cache_inhibit_reg;
	translation_bypassed <= bypassed_reg;
	translation_atc_hit <= atc_hit_reg;
	translation_table_walk <= table_walk_reg;
	fault <= fault_reg;
	fault_from_atc <= fault_from_atc_reg;
	fault_bus_error <= fault_bus_error_reg;
	fault_invalid <= fault_invalid_reg;
	fault_limit <= fault_limit_reg;
	fault_supervisor <= fault_supervisor_reg;
	fault_write_protect <= fault_write_protect_reg;
	fault_descriptor_address <= fault_descriptor_address_reg;
	fault_during_update <= fault_during_update_reg;

	atc_lookup_request <= '1' when state = LOOKUP else '0';
	atc_lookup_address <= logical_address_latched;
	atc_lookup_function_code <= function_code_latched;
	atc_lookup_write <= write_access_latched;
	atc_fill_request <= '1' when state = FILL else '0';
	atc_fill_logical_address <= logical_address_latched;
	atc_fill_function_code <= function_code_latched;
	atc_fill_physical_address <= physical_address_reg;
	atc_fill_cache_inhibit <= cache_inhibit_reg;
	atc_fill_write_protected <= fill_write_protected_reg;
	atc_fill_modified <= atc_lookup_modified when state = LOOKUP else
		walker_modified;
	atc_fill_bus_error <= fill_bus_error_reg;

	walker_start <= '1' when state = WALK_START else '0';
	walker_logical_address <= logical_address_latched;
	walker_function_code <= function_code_latched;
	walker_write_access <= write_access_latched;

	controller : process(clk)
		variable write_fault : std_logic;
		variable walk_fault : std_logic;
	begin
		if rising_edge(clk) then
			if nReset = '0' then
				state <= IDLE;
				logical_address_latched <= (others => '0');
				function_code_latched <= (others => '0');
				write_access_latched <= '0';
				read_modify_write_latched <= '0';
				physical_address_reg <= (others => '0');
				cache_inhibit_reg <= '0';
				bypassed_reg <= '0';
				atc_hit_reg <= '0';
				table_walk_reg <= '0';
				fault_reg <= '0';
				fault_from_atc_reg <= '0';
				fault_bus_error_reg <= '0';
				fault_invalid_reg <= '0';
				fault_limit_reg <= '0';
				fault_supervisor_reg <= '0';
				fault_write_protect_reg <= '0';
				fault_descriptor_address_reg <= (others => '0');
				fault_during_update_reg <= '0';
				fill_write_protected_reg <= '0';
				fill_bus_error_reg <= '0';
			else
				case state is
					when IDLE =>
						if start = '1' then
							logical_address_latched <= logical_address;
							function_code_latched <= function_code;
							write_access_latched <= write_access;
							read_modify_write_latched <= read_modify_write;
							physical_address_reg <= logical_address;
							cache_inhibit_reg <= '0';
							bypassed_reg <= '0';
							atc_hit_reg <= '0';
							table_walk_reg <= '0';
							fault_reg <= '0';
							fault_from_atc_reg <= '0';
							fault_bus_error_reg <= '0';
							fault_invalid_reg <= '0';
							fault_limit_reg <= '0';
							fault_supervisor_reg <= '0';
							fault_write_protect_reg <= '0';
							fault_descriptor_address_reg <= (others => '0');
							fault_during_update_reg <= '0';
							fill_write_protected_reg <= '0';
							fill_bus_error_reg <= '0';
							state <= CLASSIFY;
						end if;

					when CLASSIFY =>
						if tc(MMU_TC_ENABLE_BIT) = '0' or transparent_bypass = '1' then
							bypassed_reg <= '1';
							if transparent_match = '1' then
								cache_inhibit_reg <= transparent_cache_inhibit;
							end if;
							state <= COMPLETE;
						else
							state <= LOOKUP;
						end if;

					when LOOKUP =>
						if atc_lookup_hit = '1' then
							write_fault := write_access_latched and
								atc_lookup_write_protected;
							physical_address_reg <= atc_lookup_physical_address;
							cache_inhibit_reg <= atc_lookup_cache_inhibit;
							atc_hit_reg <= '1';
							fault_reg <= atc_lookup_bus_error or write_fault;
							fault_from_atc_reg <= atc_lookup_bus_error;
							fault_write_protect_reg <= write_fault;
							state <= COMPLETE;
						elsif atc_lookup_requires_walk = '1' or
								atc_lookup_match = '0' then
							table_walk_reg <= '1';
							state <= WALK_START;
						end if;

					when WALK_START =>
						state <= WALK_WAIT;

					when WALK_WAIT =>
						if walker_done = '1' then
							write_fault := write_access_latched and
								walker_write_protected;
							walk_fault := not walker_mapping_valid or walker_bus_error or
								walker_invalid_descriptor or walker_limit_violation or
								walker_supervisor_violation or write_fault;
							physical_address_reg <= walker_physical_address;
							cache_inhibit_reg <= walker_cache_inhibit;
							fault_reg <= walk_fault;
							fault_bus_error_reg <= walker_bus_error;
							fault_invalid_reg <= walker_invalid_descriptor;
							fault_limit_reg <= walker_limit_violation;
							fault_supervisor_reg <= walker_supervisor_violation;
							fault_write_protect_reg <= write_fault;
							fault_descriptor_address_reg <=
								walker_fault_descriptor_address;
							fault_during_update_reg <= walker_fault_during_update;
							fill_write_protected_reg <= walker_write_protected;
							fill_bus_error_reg <= not walker_mapping_valid or
								walker_bus_error or walker_invalid_descriptor or
								walker_limit_violation or walker_supervisor_violation;
							state <= FILL;
						end if;

					when FILL =>
						state <= COMPLETE;

					when COMPLETE =>
						state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
