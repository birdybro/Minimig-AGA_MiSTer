library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_condition is
end entity;

architecture test of tb_tg68k_fpu_condition is
	function boolean_to_logic(value : boolean) return std_logic is
	begin
		if value then
			return '1';
		end if;
		return '0';
	end function;

	signal predicate : std_logic_vector(5 downto 0) := (others => '0');
	signal condition_codes : std_logic_vector(3 downto 0) := (others => '0');
	signal condition_true : std_logic;
	signal bsun : std_logic;
begin
	dut : entity work.TG68K_FPU_Condition
		port map(
			predicate => predicate,
			condition_codes => condition_codes,
			condition_true => condition_true,
			bsun => bsun
		);

	stimulus : process
		variable negative : boolean;
		variable zero : boolean;
		variable unordered : boolean;
		variable expected_true : boolean;
		variable expected_bsun : boolean;
	begin
		for predicate_value in 0 to 63 loop
			for condition_value in 0 to 15 loop
				predicate <= std_logic_vector(to_unsigned(predicate_value, 6));
				condition_codes <= std_logic_vector(to_unsigned(condition_value, 4));
				wait for 1 ns;
				negative := condition_value mod 16 >= 8;
				zero := condition_value mod 8 >= 4;
				unordered := condition_value mod 2 = 1;
				case predicate_value mod 16 is
					when 0 => expected_true := false;
					when 1 => expected_true := zero;
					when 2 => expected_true := not unordered and not zero and
						not negative;
					when 3 => expected_true := zero or
						(not unordered and not negative);
					when 4 => expected_true := negative and not unordered and
						not zero;
					when 5 => expected_true := zero or
						(negative and not unordered);
					when 6 => expected_true := not unordered and not zero;
					when 7 => expected_true := not unordered;
					when 8 => expected_true := unordered;
					when 9 => expected_true := unordered or zero;
					when 10 => expected_true := unordered or
						(not zero and not negative);
					when 11 => expected_true := unordered or zero or not negative;
					when 12 => expected_true := unordered or
						(negative and not zero);
					when 13 => expected_true := unordered or zero or negative;
					when 14 => expected_true := not zero;
					when others => expected_true := true;
				end case;
				expected_bsun := unordered and
					(predicate_value mod 32) >= 16;
				assert condition_true = boolean_to_logic(expected_true) and
					bsun = boolean_to_logic(expected_bsun)
					report "condition evaluation mismatch: predicate=" &
						integer'image(predicate_value) & " fpcc=" &
						integer'image(condition_value)
					severity failure;
			end loop;
		end loop;
		report "PASS: all MC68882 condition predicates and FPCC combinations"
			severity note;
		stop;
	end process;
end architecture;
