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

entity TG68K_FPU is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		null_restore : in std_logic;

		data_register_select : in std_logic_vector(2 downto 0);
		data_register_write : in std_logic;
		data_register_write_data : in fpu_extended_t;
		data_register_read_data : out fpu_extended_t;

		control_register_select : in fpu_control_register_t;
		control_register_write : in std_logic;
		control_register_write_data : in std_logic_vector(31 downto 0);
		control_register_read_data : out std_logic_vector(31 downto 0);

		fp_registers_out : out fpu_register_array_t;
		fpcr_out : out std_logic_vector(31 downto 0);
		fpsr_out : out std_logic_vector(31 downto 0);
		fpiar_out : out std_logic_vector(31 downto 0)
	);
end entity;

architecture rtl of TG68K_FPU is
	signal fp_registers : fpu_register_array_t :=
		(others => FPU_RESET_NAN);
	signal fpcr : std_logic_vector(31 downto 0) := (others => '0');
	signal fpsr : std_logic_vector(31 downto 0) := (others => '0');
	signal fpiar : std_logic_vector(31 downto 0) := (others => '0');
begin
	data_register_read_data <= fp_registers(
		to_integer(unsigned(data_register_select)));
	with control_register_select select control_register_read_data <=
		fpcr when FPU_REG_FPCR,
		fpsr when FPU_REG_FPSR,
		fpiar when FPU_REG_FPIAR;

	fp_registers_out <= fp_registers;
	fpcr_out <= fpcr;
	fpsr_out <= fpsr;
	fpiar_out <= fpiar;

	registers : process(clk)
	begin
		if rising_edge(clk) then
			if nReset = '0' or null_restore = '1' then
				fp_registers <= (others => FPU_RESET_NAN);
				fpcr <= (others => '0');
				fpsr <= (others => '0');
				fpiar <= (others => '0');
			else
				if data_register_write = '1' then
					fp_registers(to_integer(unsigned(
						data_register_select))) <= data_register_write_data;
				end if;
				if control_register_write = '1' then
					case control_register_select is
						when FPU_REG_FPCR =>
							fpcr <= control_register_write_data and
								FPU_FPCR_IMPLEMENTED_MASK;
						when FPU_REG_FPSR =>
							fpsr <= control_register_write_data;
						when FPU_REG_FPIAR =>
							fpiar <= control_register_write_data;
					end case;
				end if;
			end if;
		end if;
	end process;
end architecture;
