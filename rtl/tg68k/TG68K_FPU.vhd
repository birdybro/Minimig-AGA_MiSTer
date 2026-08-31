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
		operation_status_write : in std_logic;
		condition_codes_write : in std_logic;
		operation_condition_codes : in std_logic_vector(3 downto 0);
		quotient_write : in std_logic;
		operation_quotient : in std_logic_vector(7 downto 0);
		operation_exception_status : in std_logic_vector(7 downto 0);

		fp_registers_out : out fpu_register_array_t;
		fpcr_out : out std_logic_vector(31 downto 0);
		fpsr_out : out std_logic_vector(31 downto 0);
		fpiar_out : out std_logic_vector(31 downto 0);
		rounding_precision_out : out fpu_rounding_precision_t;
		rounding_mode_out : out fpu_rounding_mode_t;
		exception_trap : out std_logic;
		exception_class : out fpu_exception_t
	);
end entity;

architecture rtl of TG68K_FPU is
	signal fp_registers : fpu_register_array_t :=
		(others => FPU_RESET_NAN);
	signal fpcr : std_logic_vector(31 downto 0) := (others => '0');
	signal fpsr : std_logic_vector(31 downto 0) := (others => '0');
	signal fpiar : std_logic_vector(31 downto 0) := (others => '0');
	signal exception_class_register : fpu_exception_t := FPU_EXCEPTION_NONE;
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
	with fpcr(FPU_FPCR_PRECISION_HIGH downto FPU_FPCR_PRECISION_LOW) select
		rounding_precision_out <=
		FPU_PRECISION_EXTENDED when "00",
		FPU_PRECISION_SINGLE when "01",
		FPU_PRECISION_DOUBLE when "10",
		FPU_PRECISION_RESERVED when others;
	with fpcr(FPU_FPCR_ROUNDING_HIGH downto FPU_FPCR_ROUNDING_LOW) select
		rounding_mode_out <=
		FPU_ROUND_NEAREST when "00",
		FPU_ROUND_ZERO when "01",
		FPU_ROUND_MINUS_INFINITY when "10",
		FPU_ROUND_PLUS_INFINITY when others;
	exception_class <= exception_class_register;

	registers : process(clk)
		variable enabled_status : std_logic_vector(7 downto 0);
	begin
		if rising_edge(clk) then
			exception_trap <= '0';
			exception_class_register <= FPU_EXCEPTION_NONE;
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
				if operation_status_write = '1' then
					if condition_codes_write = '1' then
						fpsr(31 downto 28) <= operation_condition_codes;
					end if;
					if quotient_write = '1' then
						fpsr(23 downto 16) <= operation_quotient;
					end if;
					fpsr(15 downto 8) <= operation_exception_status;
					if operation_exception_status(7) = '1' or
							operation_exception_status(6) = '1' or
							operation_exception_status(5) = '1' then
						fpsr(FPU_FPSR_AEXC_IOP_BIT) <= '1';
					end if;
					if operation_exception_status(4) = '1' then
						fpsr(FPU_FPSR_AEXC_OVFL_BIT) <= '1';
					end if;
					if operation_exception_status(3) = '1' and
							operation_exception_status(1) = '1' then
						fpsr(FPU_FPSR_AEXC_UNFL_BIT) <= '1';
					end if;
					if operation_exception_status(2) = '1' then
						fpsr(FPU_FPSR_AEXC_DZ_BIT) <= '1';
					end if;
					if operation_exception_status(1) = '1' or
							operation_exception_status(0) = '1' or
							operation_exception_status(4) = '1' then
						fpsr(FPU_FPSR_AEXC_INEX_BIT) <= '1';
					end if;

					enabled_status := operation_exception_status and fpcr(15 downto 8);
					if enabled_status /= x"00" then
						exception_trap <= '1';
						if enabled_status(7) = '1' then
							exception_class_register <= FPU_EXCEPTION_BSUN;
						elsif enabled_status(6) = '1' then
							exception_class_register <= FPU_EXCEPTION_SNAN;
						elsif enabled_status(5) = '1' then
							exception_class_register <= FPU_EXCEPTION_OPERR;
						elsif enabled_status(4) = '1' then
							exception_class_register <= FPU_EXCEPTION_OVFL;
						elsif enabled_status(3) = '1' then
							exception_class_register <= FPU_EXCEPTION_UNFL;
						elsif enabled_status(2) = '1' then
							exception_class_register <= FPU_EXCEPTION_DZ;
						elsif enabled_status(1) = '1' then
							exception_class_register <= FPU_EXCEPTION_INEX2;
						else
							exception_class_register <= FPU_EXCEPTION_INEX1;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;
end architecture;
