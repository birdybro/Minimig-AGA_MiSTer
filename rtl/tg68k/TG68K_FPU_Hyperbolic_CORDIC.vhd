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

entity TG68K_FPU_Hyperbolic_CORDIC is
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		vectoring : in std_logic;
		rotate_on_start : in std_logic;
		x_input : in signed(99 downto 0);
		y_input : in signed(99 downto 0);
		z_input : in signed(112 downto 0);

		x_result : out signed(99 downto 0);
		y_result : out signed(99 downto 0);
		z_result : out signed(112 downto 0);
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Hyperbolic_CORDIC is
	constant XY_WIDTH : natural := 100;
	constant Z_WIDTH : natural := 113;
	constant LAST_ITERATION : natural := 96;
	type cordic_state_t is (IDLE, ROTATE_XY, ROTATE_Z, COMPLETE);
	subtype xy_value_t is signed(XY_WIDTH - 1 downto 0);
	subtype z_value_t is signed(Z_WIDTH - 1 downto 0);
	type angle_rom_t is array(0 to 31) of xy_value_t;
	constant ANGLE_ONE : xy_value_t :=
		signed'(x"08C9F53D5681854BB520CC6AB");

	signal angle_rom : angle_rom_t := (
		0 => (others => '0'),
		1 => signed'(x"08C9F53D5681854BB520CC6AB"),
		2 => signed'(x"04162BBEA0451469C9DAF0BE1"),
		3 => signed'(x"0202B12393D5DEED328CF41ED"),
		4 => signed'(x"01005588AD375ACDCB1312A56"),
		5 => signed'(x"00800AAC448D77125A4EE9FEE"),
		6 => signed'(x"004001556222B47263834E959"),
		7 => signed'(x"0020002AAB111235A6E87A2A0"),
		8 => signed'(x"001000055558888AD1AEE1EF9"),
		9 => signed'(x"00080000AAAAC44448D68E4C6"),
		10 => signed'(x"0004000015555622222B46B4E"),
		11 => signed'(x"0002000002AAAAB11111235A3"),
		12 => signed'(x"0001000000555555888888AD2"),
		13 => signed'(x"00008000000AAAAAAC4444449"),
		14 => signed'(x"0000400000015555556222222"),
		15 => signed'(x"0000200000002AAAAAAB11111"),
		16 => signed'(x"0000100000000555555558889"),
		17 => signed'(x"00000800000000AAAAAAAAC44"),
		18 => signed'(x"0000040000000015555555562"),
		19 => signed'(x"0000020000000002AAAAAAAAB"),
		20 => signed'(x"0000010000000000555555555"),
		21 => signed'(x"00000080000000000AAAAAAAB"),
		22 => signed'(x"0000004000000000015555555"),
		23 => signed'(x"0000002000000000002AAAAAB"),
		24 => signed'(x"0000001000000000000555555"),
		25 => signed'(x"00000008000000000000AAAAB"),
		26 => signed'(x"0000000400000000000015555"),
		27 => signed'(x"0000000200000000000002AAB"),
		28 => signed'(x"0000000100000000000000555"),
		29 => signed'(x"00000000800000000000000AB"),
		30 => signed'(x"0000000040000000000000015"),
		31 => signed'(x"0000000020000000000000003")
	);
	attribute ramstyle : string;
	attribute ramstyle of angle_rom : signal is "M10K";

	function fit_z(
			value : z_value_t;
			vectoring_mode : std_logic) return z_value_t is
	begin
		if vectoring_mode = '0' then
			return resize(value(XY_WIDTH - 1 downto 0), Z_WIDTH);
		end if;
		return value;
	end function;

	signal state : cordic_state_t := IDLE;
	signal vectoring_latched : std_logic := '0';
	signal x_value : xy_value_t := (others => '0');
	signal y_value : xy_value_t := (others => '0');
	signal z_value : z_value_t := (others => '0');
	signal z_previous : z_value_t := (others => '0');
	signal angle_previous : z_value_t := (others => '0');
	signal direction_previous : std_logic := '0';
	signal iteration : natural range 1 to LAST_ITERATION := 1;
	signal repeat_iteration : std_logic := '0';
	signal angle_address : natural range 1 to 31 := 1;
	signal angle_data : xy_value_t := (others => '0');
	signal shift_angle : xy_value_t := (others => '0');
	signal active_vectoring : std_logic;
	signal active_x : xy_value_t;
	signal active_y : xy_value_t;
	signal active_z : z_value_t;
	signal active_angle : xy_value_t;
	signal active_direction : std_logic;
	signal left_a : unsigned(Z_WIDTH - 1 downto 0);
	signal right_a : unsigned(Z_WIDTH - 1 downto 0);
	signal left_b : unsigned(Z_WIDTH - 1 downto 0);
	signal right_b : unsigned(Z_WIDTH - 1 downto 0);
	signal subtract_a : std_logic;
	signal subtract_b : std_logic;
	signal arithmetic_result_a : unsigned(Z_WIDTH - 1 downto 0);
	signal arithmetic_result_b : unsigned(Z_WIDTH - 1 downto 0);
begin
	active_vectoring <= vectoring when state = IDLE else vectoring_latched;
	active_x <= x_input when state = IDLE else x_value;
	active_y <= y_input when state = IDLE else y_value;
	active_z <= fit_z(z_input, vectoring) when state = IDLE else z_value;
	active_angle <= ANGLE_ONE when state = IDLE else
		angle_data when iteration <= 31 else shift_angle;
	active_direction <= '1' when
		(active_vectoring = '1' and active_y >= 0) or
		(active_vectoring = '0' and active_z >= 0) else '0';

	busy <= '1' when state /= IDLE or start = '1' else '0';
	done <= '1' when state = COMPLETE else '0';
	x_result <= x_value;
	y_result <= y_value;
	z_result <= z_value;

	arithmetic_operands : process(state, start, rotate_on_start,
		active_vectoring, active_x, active_y, active_z, active_angle,
		active_direction, iteration, z_previous, angle_previous,
		direction_previous, vectoring_latched)
	begin
		left_a <= (others => '0');
		right_a <= (others => '0');
		left_b <= (others => '0');
		right_b <= (others => '0');
		subtract_a <= '0';
		subtract_b <= '0';
		if state = ROTATE_XY or
				(state = IDLE and start = '1' and rotate_on_start = '1') then
			left_a <= unsigned(resize(active_x, Z_WIDTH));
			right_a <= unsigned(resize(shift_right(active_y, iteration),
				Z_WIDTH));
			left_b <= unsigned(resize(active_y, Z_WIDTH));
			right_b <= unsigned(resize(shift_right(active_x, iteration),
				Z_WIDTH));
			if (active_vectoring = '1' and active_y >= 0) or
					(active_vectoring = '0' and active_z < 0) then
				subtract_a <= '1';
				subtract_b <= '1';
			end if;
		elsif state = ROTATE_Z then
			left_a <= unsigned(z_previous);
			right_a <= unsigned(angle_previous);
			if vectoring_latched = '1' then
				subtract_a <= not direction_previous;
			else
				subtract_a <= direction_previous;
			end if;
		end if;
	end process;

	arithmetic_add_subtract : process(subtract_a, left_a, right_a,
			subtract_b, left_b, right_b)
	begin
		if subtract_a = '1' then
			arithmetic_result_a <= left_a - right_a;
		else
			arithmetic_result_a <= left_a + right_a;
		end if;
		if subtract_b = '1' then
			arithmetic_result_b <= left_b - right_b;
		else
			arithmetic_result_b <= left_b + right_b;
		end if;
	end process;

	cordic_sequence : process(clk)
		variable next_tail : xy_value_t;
	begin
		if rising_edge(clk) then
			angle_data <= angle_rom(angle_address);
			if nReset = '0' then
				state <= IDLE;
				vectoring_latched <= '0';
				x_value <= (others => '0');
				y_value <= (others => '0');
				z_value <= (others => '0');
				z_previous <= (others => '0');
				angle_previous <= (others => '0');
				direction_previous <= '0';
				iteration <= 1;
				repeat_iteration <= '0';
				angle_address <= 1;
				shift_angle <= (others => '0');
			else
				case state is
					when IDLE =>
						iteration <= 1;
						repeat_iteration <= '0';
						angle_address <= 1;
						if start = '1' then
							vectoring_latched <= vectoring;
							x_value <= x_input;
							y_value <= y_input;
							z_value <= fit_z(z_input, vectoring);
							shift_angle <= (others => '0');
							if rotate_on_start = '1' then
								z_previous <= active_z;
								angle_previous <= resize(active_angle, Z_WIDTH);
								direction_previous <= active_direction;
								x_value <= signed(arithmetic_result_a(
									XY_WIDTH - 1 downto 0));
								y_value <= signed(arithmetic_result_b(
									XY_WIDTH - 1 downto 0));
								angle_address <= 2;
								state <= ROTATE_Z;
							else
								state <= ROTATE_XY;
							end if;
						end if;

					when ROTATE_XY =>
						z_previous <= z_value;
						angle_previous <= resize(active_angle, Z_WIDTH);
						direction_previous <= active_direction;
						x_value <= signed(arithmetic_result_a(
							XY_WIDTH - 1 downto 0));
						y_value <= signed(arithmetic_result_b(
							XY_WIDTH - 1 downto 0));
						if not ((iteration = 4 or iteration = 13 or
								iteration = 40) and repeat_iteration = '0') then
							if iteration < 31 then
								angle_address <= iteration + 1;
							elsif iteration = 31 then
								next_tail := (others => '0');
								next_tail(64) := '1';
								shift_angle <= next_tail;
							else
								shift_angle <= shift_right(shift_angle, 1);
							end if;
						end if;
						state <= ROTATE_Z;

					when ROTATE_Z =>
						z_value <= fit_z(signed(arithmetic_result_a),
							vectoring_latched);
						-- Hyperbolic CORDIC repeats these iterations to converge.
						if (iteration = 4 or iteration = 13 or iteration = 40) and
								repeat_iteration = '0' then
							repeat_iteration <= '1';
							state <= ROTATE_XY;
						elsif iteration = LAST_ITERATION then
							state <= COMPLETE;
						else
							repeat_iteration <= '0';
							iteration <= iteration + 1;
							state <= ROTATE_XY;
						end if;

					when COMPLETE =>
						iteration <= 1;
						repeat_iteration <= '0';
						angle_address <= 1;
						state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
