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

entity TG68KdotC_MMU is
	generic(
		SR_Read : integer := 2;
		VBR_Stackframe : integer := 2;
		extAddr_Mode : integer := 2;
		MUL_Mode : integer := 2;
		DIV_Mode : integer := 2;
		BitField : integer := 2;
		BarrelShifter : integer := 1;
		MUL_Hardware : integer := 1
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		clkena_in : in std_logic := '1';
		data_in : in std_logic_vector(15 downto 0);
		IPL : in std_logic_vector(2 downto 0) := "111";
		IPL_autovector : in std_logic := '0';
		berr : in std_logic := '0';
		CPU : in std_logic_vector(1 downto 0) := "00";
		MMU_enable : in std_logic := '1';
		addr_out : out std_logic_vector(31 downto 0);
		data_write : out std_logic_vector(15 downto 0);
		nWr : out std_logic;
		nUDS : out std_logic;
		nLDS : out std_logic;
		busstate : out std_logic_vector(1 downto 0);
		longword : out std_logic;
		cache_inhibit : out std_logic;
		logical_bus_address : out std_logic_vector(31 downto 0);
		logical_bus_access : out std_logic;
		nResetOut : out std_logic;
		FC : out std_logic_vector(2 downto 0);
		clr_berr : out std_logic;
		skipFetch : out std_logic;
		regin_out : out std_logic_vector(31 downto 0);
		CACR_out : out std_logic_vector(3 downto 0);
		D_CACHE_out : out std_logic;
		VBR_out : out std_logic_vector(31 downto 0)
	);
end entity;

architecture rtl of TG68KdotC_MMU is
	type bridge_state_t is (BRIDGE_IDLE, BRIDGE_TRANSLATE_WAIT,
		BRIDGE_PHYSICAL_WAIT, BRIDGE_FAULT);
	signal bridge_state : bridge_state_t := BRIDGE_IDLE;
	signal bridge_owner_operand : std_logic := '0';
	signal bridge_busstate : std_logic_vector(1 downto 0) := "01";
	signal bridge_address : std_logic_vector(31 downto 0) := (others => '0');
	signal bridge_logical_address : std_logic_vector(31 downto 0) := (others => '0');
	signal bridge_data : std_logic_vector(15 downto 0) := (others => '0');
	signal bridge_nuds : std_logic := '1';
	signal bridge_nlds : std_logic := '1';
	signal bridge_fc : std_logic_vector(2 downto 0) := (others => '0');
	signal bridge_longword : std_logic := '0';
	signal bridge_cache_inhibit : std_logic := '0';
	signal bridge_fault_write : std_logic;
	signal bridge_fault_instruction : std_logic;

	signal kernel_clkena : std_logic;
	signal kernel_berr : std_logic;
	signal kernel_mmu_fault : std_logic;
	signal kernel_address : std_logic_vector(31 downto 0);
	signal kernel_data_write : std_logic_vector(15 downto 0);
	signal kernel_nwr : std_logic;
	signal kernel_nuds : std_logic;
	signal kernel_nlds : std_logic;
	signal kernel_busstate : std_logic_vector(1 downto 0);
	signal kernel_longword : std_logic;
	signal kernel_fc : std_logic_vector(2 downto 0);

	signal mmu_instruction_match : std_logic;
	signal mmu_instruction_valid : std_logic;
	signal mmu_instruction_requires_ea : std_logic;
	signal mmu_fc_data_register_select : std_logic_vector(2 downto 0);
	signal mmu_instruction_busy : std_logic;
	signal mmu_instruction_done : std_logic;
	signal mmu_unimplemented_exception : std_logic;
	signal mmu_privilege_exception : std_logic;
	signal mmu_bus_error_exception : std_logic;
	signal mmu_configuration_exception : std_logic;
	signal mmu_address_register_write : std_logic;
	signal mmu_address_register_select : std_logic_vector(2 downto 0);
	signal mmu_address_register_data : std_logic_vector(31 downto 0);
	signal mmu_instruction_start : std_logic;
	signal mmu_opcode : std_logic_vector(15 downto 0);
	signal mmu_extension_word : std_logic_vector(15 downto 0);
	signal mmu_supervisor : std_logic;
	signal mmu_effective_address : std_logic_vector(31 downto 0);
	signal mmu_fc_data_register_value : std_logic_vector(2 downto 0);
	signal mmu_sfc : std_logic_vector(2 downto 0);
	signal mmu_dfc : std_logic_vector(2 downto 0);

	signal operand_ready : std_logic;
	signal operand_error : std_logic;
	signal operand_request : std_logic;
	signal operand_write : std_logic;
	signal operand_address : std_logic_vector(31 downto 0);
	signal operand_write_data : std_logic_vector(15 downto 0);
	signal operand_fc : std_logic_vector(2 downto 0);

	signal table_ready : std_logic;
	signal table_error : std_logic;
	signal table_request : std_logic;
	signal table_write : std_logic;
	signal table_address : std_logic_vector(31 downto 0);
	signal table_write_data : std_logic_vector(15 downto 0);
	signal table_fc : std_logic_vector(2 downto 0);

	signal translation_start : std_logic;
	signal translation_ready : std_logic;
	signal translation_done : std_logic;
	signal translation_physical_address : std_logic_vector(31 downto 0);
	signal translation_cache_inhibit : std_logic;
	signal translation_fault : std_logic;
	signal translation_logical_request : std_logic;
	signal translation_logical_address : std_logic_vector(31 downto 0);
	signal translation_logical_fc : std_logic_vector(2 downto 0);
	signal translation_logical_write : std_logic;
	signal direct_translation_bypass : std_logic;
	signal tc : mmu_tc_t;
begin
	direct_translation_bypass <= not MMU_enable or not tc(MMU_TC_ENABLE_BIT);
	bridge_fault_write <= '1' when bridge_busstate = "11" else '0';
	bridge_fault_instruction <= '1' when bridge_busstate = "00" else '0';
	translation_logical_request <= operand_request when operand_request = '1' else
		'1' when kernel_busstate /= "01" else '0';
	translation_logical_address <= operand_address when operand_request = '1' else
		kernel_address;
	translation_logical_fc <= operand_fc when operand_request = '1' else kernel_fc;
	translation_logical_write <= operand_write when operand_request = '1' else
		not kernel_nwr;
	translation_start <= '1' when bridge_state = BRIDGE_IDLE and
		direct_translation_bypass = '0' and table_request = '0' and
		translation_logical_request = '1' and translation_ready = '1' else '0';

	bridge : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' or MMU_enable = '0' then
				bridge_state <= BRIDGE_IDLE;
				bridge_owner_operand <= '0';
				bridge_busstate <= "01";
				bridge_address <= (others => '0');
				bridge_logical_address <= (others => '0');
				bridge_data <= (others => '0');
				bridge_nuds <= '1';
				bridge_nlds <= '1';
				bridge_fc <= (others => '0');
				bridge_longword <= '0';
				bridge_cache_inhibit <= '0';
			else
				case bridge_state is
					when BRIDGE_IDLE =>
						if translation_start = '1' then
							bridge_owner_operand <= operand_request;
							bridge_address <= translation_logical_address;
							bridge_logical_address <= translation_logical_address;
							bridge_fc <= translation_logical_fc;
							if operand_request = '1' then
								bridge_data <= operand_write_data;
								bridge_longword <= '0';
								if operand_write = '1' then
									bridge_busstate <= "11";
								else
									bridge_busstate <= "10";
								end if;
								bridge_nuds <= '0';
								bridge_nlds <= '0';
							else
								bridge_data <= kernel_data_write;
								bridge_longword <= kernel_longword;
								bridge_busstate <= kernel_busstate;
								bridge_nuds <= kernel_nuds;
								bridge_nlds <= kernel_nlds;
							end if;
							bridge_state <= BRIDGE_TRANSLATE_WAIT;
						end if;

					when BRIDGE_TRANSLATE_WAIT =>
						if translation_done = '1' then
							bridge_address <= translation_physical_address;
							bridge_cache_inhibit <= translation_cache_inhibit;
							if translation_fault = '1' then
								bridge_state <= BRIDGE_FAULT;
							else
								bridge_state <= BRIDGE_PHYSICAL_WAIT;
							end if;
						end if;

					when BRIDGE_PHYSICAL_WAIT =>
						if clkena_in = '1' then
							bridge_state <= BRIDGE_IDLE;
						end if;

					when BRIDGE_FAULT =>
						bridge_state <= BRIDGE_IDLE;
				end case;
			end if;
		end if;
	end process;

	bus_mux : process(MMU_enable, table_request, table_address,
		table_write_data, table_write, table_fc, direct_translation_bypass,
		bridge_state, bridge_address, bridge_logical_address, bridge_data, bridge_busstate,
		bridge_nuds, bridge_nlds, bridge_longword, bridge_cache_inhibit,
		bridge_fc, bridge_owner_operand, operand_request, operand_address,
		operand_write_data, operand_write, operand_fc,
		translation_logical_request, kernel_address, kernel_data_write,
		kernel_nwr, kernel_nuds, kernel_nlds, kernel_busstate,
		kernel_longword, kernel_fc, clkena_in, berr)
	begin
		addr_out <= kernel_address;
		data_write <= kernel_data_write;
		nWr <= kernel_nwr;
		nUDS <= kernel_nuds;
		nLDS <= kernel_nlds;
		busstate <= "01";
		longword <= '0';
		cache_inhibit <= '0';
		logical_bus_address <= kernel_address;
		logical_bus_access <= '0';
		FC <= kernel_fc;
		kernel_clkena <= '0';
		kernel_berr <= '0';
		kernel_mmu_fault <= '0';
		operand_ready <= '0';
		operand_error <= '0';
		table_ready <= '0';
		table_error <= '0';

		if MMU_enable = '0' then
			busstate <= kernel_busstate;
			longword <= kernel_longword;
			if kernel_busstate /= "01" then
				logical_bus_access <= '1';
			end if;
			kernel_clkena <= clkena_in;
			kernel_berr <= berr;
		elsif table_request = '1' then
			addr_out <= table_address;
			data_write <= table_write_data;
			nWr <= not table_write;
			nUDS <= '0';
			nLDS <= '0';
			if table_write = '1' then
				busstate <= "11";
			else
				busstate <= "10";
			end if;
			FC <= table_fc;
			cache_inhibit <= '1';
			table_ready <= clkena_in;
			table_error <= berr;
		elsif direct_translation_bypass = '1' and
				bridge_state = BRIDGE_IDLE then
			kernel_clkena <= clkena_in;
			if operand_request = '1' then
				addr_out <= operand_address;
				data_write <= operand_write_data;
				nWr <= not operand_write;
				nUDS <= '0';
				nLDS <= '0';
				if operand_write = '1' then
					busstate <= "11";
				else
					busstate <= "10";
				end if;
				FC <= operand_fc;
				operand_ready <= clkena_in;
				operand_error <= berr;
			else
				busstate <= kernel_busstate;
				longword <= kernel_longword;
				if kernel_busstate /= "01" then
					logical_bus_access <= '1';
				end if;
				kernel_berr <= berr;
			end if;
		elsif bridge_state = BRIDGE_IDLE then
			if translation_logical_request = '0' then
				kernel_clkena <= clkena_in;
			end if;
		elsif bridge_state = BRIDGE_PHYSICAL_WAIT then
			addr_out <= bridge_address;
			data_write <= bridge_data;
			if bridge_busstate = "11" then
				nWr <= '0';
			else
				nWr <= '1';
			end if;
			nUDS <= bridge_nuds;
			nLDS <= bridge_nlds;
			busstate <= bridge_busstate;
			longword <= bridge_longword;
			cache_inhibit <= bridge_cache_inhibit;
			FC <= bridge_fc;
			kernel_clkena <= clkena_in;
			if bridge_owner_operand = '1' then
				operand_ready <= clkena_in;
				operand_error <= berr;
			else
				logical_bus_access <= '1';
				kernel_berr <= berr;
			end if;
		elsif bridge_state = BRIDGE_FAULT then
			kernel_clkena <= '1';
			if bridge_owner_operand = '1' then
				operand_error <= '1';
			else
				kernel_mmu_fault <= '1';
			end if;
		end if;
	end process;

	kernel : entity work.TG68KdotC_Kernel
		generic map(
			SR_Read => SR_Read,
			VBR_Stackframe => VBR_Stackframe,
			extAddr_Mode => extAddr_Mode,
			MUL_Mode => MUL_Mode,
			DIV_Mode => DIV_Mode,
			BitField => BitField,
			BarrelShifter => BarrelShifter,
			MUL_Hardware => MUL_Hardware
		)
		port map(
			clk => clk,
			nReset => nReset,
			clkena_in => kernel_clkena,
			data_in => data_in,
			IPL => IPL,
			IPL_autovector => IPL_autovector,
			berr => kernel_berr,
			CPU => CPU,
			addr_out => kernel_address,
			data_write => kernel_data_write,
			nWr => kernel_nwr,
			nUDS => kernel_nuds,
			nLDS => kernel_nlds,
			busstate => kernel_busstate,
			longword => kernel_longword,
			nResetOut => nResetOut,
			FC => kernel_fc,
			clr_berr => clr_berr,
			MMU_enable => MMU_enable,
			MMU_instruction_match => mmu_instruction_match,
			MMU_instruction_valid => mmu_instruction_valid,
			MMU_instruction_requires_ea => mmu_instruction_requires_ea,
			MMU_instruction_busy => mmu_instruction_busy,
			MMU_instruction_done => mmu_instruction_done,
			MMU_unimplemented_exception => mmu_unimplemented_exception,
			MMU_privilege_exception => mmu_privilege_exception,
			MMU_bus_error_exception => mmu_bus_error_exception,
			MMU_configuration_exception => mmu_configuration_exception,
			MMU_access_fault => kernel_mmu_fault,
			MMU_fault_address => bridge_logical_address,
			MMU_fault_function_code => bridge_fc,
			MMU_fault_write => bridge_fault_write,
			MMU_fault_instruction => bridge_fault_instruction,
			MMU_address_register_write => mmu_address_register_write,
			MMU_address_register_select => mmu_address_register_select,
			MMU_address_register_data => mmu_address_register_data,
			MMU_fc_data_register_select => mmu_fc_data_register_select,
			MMU_instruction_start => mmu_instruction_start,
			MMU_opcode => mmu_opcode,
			MMU_extension_word => mmu_extension_word,
			MMU_supervisor => mmu_supervisor,
			MMU_effective_address => mmu_effective_address,
			MMU_fc_data_register_value => mmu_fc_data_register_value,
			MMU_SFC => mmu_sfc,
			MMU_DFC => mmu_dfc,
			skipFetch => skipFetch,
			regin_out => regin_out,
			CACR_out => CACR_out,
			D_CACHE_out => D_CACHE_out,
			VBR_out => VBR_out
		);

	mmu : entity work.TG68K_MMU_System
		port map(
			clk => clk,
			nReset => nReset,
			opcode => mmu_opcode,
			extension_word => mmu_extension_word,
			supervisor => mmu_supervisor,
			effective_address => mmu_effective_address,
			fc_data_register_value => mmu_fc_data_register_value,
			sfc => mmu_sfc,
			dfc => mmu_dfc,
			instruction_start => mmu_instruction_start,
			instruction_match => mmu_instruction_match,
			instruction_valid => mmu_instruction_valid,
			instruction_requires_effective_address => mmu_instruction_requires_ea,
			fc_data_register_select => mmu_fc_data_register_select,
			instruction_busy => mmu_instruction_busy,
			instruction_done => mmu_instruction_done,
			unimplemented_exception => mmu_unimplemented_exception,
			privilege_exception => mmu_privilege_exception,
			bus_error_exception => mmu_bus_error_exception,
			configuration_exception => mmu_configuration_exception,
			address_register_write => mmu_address_register_write,
			address_register_select => mmu_address_register_select,
			address_register_data => mmu_address_register_data,
			translation_start => translation_start,
			translation_logical_address => translation_logical_address,
			translation_function_code => translation_logical_fc,
			translation_write => translation_logical_write,
			translation_read_modify_write => '0',
			translation_ready => translation_ready,
			translation_busy => open,
			translation_done => translation_done,
			translation_physical_address => translation_physical_address,
			translation_cache_inhibit => translation_cache_inhibit,
			translation_bypassed => open,
			translation_atc_hit => open,
			translation_table_walk => open,
			translation_fault => translation_fault,
			translation_fault_from_atc => open,
			translation_fault_bus_error => open,
			translation_fault_invalid => open,
			translation_fault_limit => open,
			translation_fault_supervisor => open,
			translation_fault_write_protect => open,
			translation_fault_descriptor_address => open,
			translation_fault_during_update => open,
			operand_bus_ready => operand_ready,
			operand_bus_error => operand_error,
			operand_bus_read_data => data_in,
			operand_bus_request => operand_request,
			operand_bus_write => operand_write,
			operand_bus_address => operand_address,
			operand_bus_write_data => operand_write_data,
			operand_bus_function_code => operand_fc,
			table_bus_ready => table_ready,
			table_bus_error => table_error,
			table_bus_read_data => data_in,
			table_bus_request => table_request,
			table_bus_write => table_write,
			table_bus_lock => open,
			table_bus_address => table_address,
			table_bus_write_data => table_write_data,
			table_bus_function_code => table_fc,
			crp_out => open,
			srp_out => open,
			tc_out => tc,
			tt0_out => open,
			tt1_out => open,
			mmusr_out => open
		);
end architecture;
