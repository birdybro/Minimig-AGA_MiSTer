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
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Condition is
	port(
		predicate : in std_logic_vector(5 downto 0);
		condition_codes : in std_logic_vector(3 downto 0);
		condition_true : out std_logic;
		bsun : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Condition is
begin
	evaluate : process(predicate, condition_codes)
		variable negative : std_logic;
		variable zero : std_logic;
		variable unordered : std_logic;
	begin
		negative := condition_codes(FPU_FPCC_NEGATIVE_BIT);
		zero := condition_codes(FPU_FPCC_ZERO_BIT);
		unordered := condition_codes(FPU_FPCC_NAN_BIT);
		case predicate(3 downto 0) is
			when x"0" => condition_true <= '0';
			when x"1" => condition_true <= zero;
			when x"2" => condition_true <= not (unordered or zero or negative);
			when x"3" => condition_true <= zero or (not unordered and not negative);
			when x"4" => condition_true <= negative and not unordered and not zero;
			when x"5" => condition_true <= zero or (negative and not unordered);
			when x"6" => condition_true <= not unordered and not zero;
			when x"7" => condition_true <= not unordered;
			when x"8" => condition_true <= unordered;
			when x"9" => condition_true <= unordered or zero;
			when x"A" => condition_true <= unordered or (not zero and not negative);
			when x"B" => condition_true <= unordered or zero or not negative;
			when x"C" => condition_true <= unordered or (negative and not zero);
			when x"D" => condition_true <= unordered or zero or negative;
			when x"E" => condition_true <= not zero;
			when others => condition_true <= '1';
		end case;
		bsun <= predicate(4) and unordered;
	end process;
end architecture;
