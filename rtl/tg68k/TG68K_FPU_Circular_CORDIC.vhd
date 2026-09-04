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

entity TG68K_FPU_Circular_CORDIC is
	generic(
		INCLUDE_SHIFT_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		vectoring : in std_logic;
		narrow_precision : in std_logic;
		hyperbolic : in std_logic := '0';
		rotate_on_start : in std_logic;
		x_input : in signed(147 downto 0);
		y_input : in signed(147 downto 0);
		z_input : in signed(147 downto 0);
		external_shifted_coordinate : in signed(147 downto 0) :=
			(others => '0');
		shift_source_out : out signed(147 downto 0);
		shift_amount_out : out natural range 0 to 144;

		x_result : out signed(147 downto 0);
		y_result : out signed(147 downto 0);
		z_result : out signed(147 downto 0);
		busy : out std_logic;
		done : out std_logic
	);
end entity;

architecture rtl of TG68K_FPU_Circular_CORDIC is
	constant CORDIC_WIDTH : natural := 140;
	constant NARROW_WIDTH : natural := 116;
	constant NARROW_ITERATIONS : natural := 112;
	constant WIDE_ITERATIONS : natural := 136;
	constant HYPERBOLIC_XY_WIDTH : natural := 100;
	constant HYPERBOLIC_Z_WIDTH : natural := 113;
	constant HYPERBOLIC_ITERATIONS : natural := 96;
	type cordic_state_t is (IDLE, ROTATE_XY, ROTATE_Z, COMPLETE);
	subtype cordic_value_t is signed(CORDIC_WIDTH - 1 downto 0);
	type wide_angle_rom_t is array(0 to 63) of signed(147 downto 0);
	type narrow_angle_rom_t is array(0 to 63) of signed(NARROW_WIDTH - 1 downto 0);
	type hyperbolic_angle_rom_t is array(0 to 31) of
		signed(HYPERBOLIC_XY_WIDTH - 1 downto 0);
	type angle_rom_t is array(0 to 255) of cordic_value_t;
	constant WIDE_ANGLE_ZERO : cordic_value_t :=
		signed'(x"08000000000000000000000000000000000");
	constant NARROW_ANGLE_ZERO : signed(NARROW_WIDTH - 1 downto 0) :=
		signed'(x"0C90FDAA22168C234C4C6628B80DC");
	constant HYPERBOLIC_ANGLE_ONE : signed(
		HYPERBOLIC_XY_WIDTH - 1 downto 0) :=
		signed'(x"08C9F53D5681854BB520CC6AB");

	constant WIDE_ANGLE_TABLE : wide_angle_rom_t := (
		0 => signed'(x"0800000000000000000000000000000000000"),
		1 => signed'(x"04B90147677CC21995A23DB6B8D4656BF2816"),
		2 => signed'(x"027ECE16D7B8E7A377D0FCF2824878347837D"),
		3 => signed'(x"0144447507776686DFE49572C7C78A5A99849"),
		4 => signed'(x"00A2C350C39626BB303300048A6DA76F3C743"),
		5 => signed'(x"005175F85641189E15A72537A0B6BDCE8F2BC"),
		6 => signed'(x"0028BD87970A098A6135AFD62D2D16923D3FE"),
		7 => signed'(x"00145F15447510ABA8B0C1B2B7AAA6C7A4C3E"),
		8 => signed'(x"000A2F94D1B430CDBF245E9BAC7B0F2ADF9EA"),
		9 => signed'(x"000517CBAECC2ACDEE4D07CB50E3BA1098D82"),
		10 => signed'(x"00028BE600246E9ED9FD0EA488467200A23AA"),
		11 => signed'(x"000145F3052A032DC1E23C00E5D9AAF496522"),
		12 => signed'(x"0000A2F98337FB186652DD8577A994773CBB6"),
		13 => signed'(x"0000517CC1B05CBC91ABD2FE7F4921E75B03A"),
		14 => signed'(x"000028BE60DABA445614E76D187CE4F82DE6B"),
		15 => signed'(x"0000145F306DAE9EECBDC8FF826B712438A54"),
		16 => signed'(x"00000A2F9836E17F0E95AAD539E4055427C4D"),
		17 => signed'(x"00000517CC1B72057A51B112AED731E455262"),
		18 => signed'(x"0000028BE60DB92B7B89B41544BEBA46F7E97"),
		19 => signed'(x"00000145F306DC9AD590F57CD762752A02B35"),
		20 => signed'(x"000000A2F9836E4E0DC1FE2CB80C6334B29BF"),
		21 => signed'(x"000000517CC1B7271B402F8425BF6CDB467B9"),
		22 => signed'(x"00000028BE60DB93902BFDCFCC184C87289BB"),
		23 => signed'(x"000000145F306DC9C8677BA99D33447C50375"),
		24 => signed'(x"0000000A2F9836E4E43DED6D057E8660EBF2D"),
		25 => signed'(x"0000000517CC1B7272203CA9899BDFB7ABD71"),
		26 => signed'(x"000000028BE60DB93910471325A9836CD3926"),
		27 => signed'(x"0000000145F306DC9C8828A15EF034288A356"),
		28 => signed'(x"00000000A2F9836E4E4414F3A8FB8862892DF"),
		29 => signed'(x"00000000517CC1B727220A8E33AE31FB0D199"),
		30 => signed'(x"0000000028BE60DB93910549A5BD26B6BF9D2"),
		31 => signed'(x"00000000145F306DC9C882A5245B551286F0A"),
		32 => signed'(x"000000000A2F9836E4E441529C5D42C0285C9"),
		33 => signed'(x"000000000517CC1B727220A94F749466F0CAD"),
		34 => signed'(x"00000000028BE60DB9391054A7E3089453F90"),
		35 => signed'(x"000000000145F306DC9C882A53F69C16456EF"),
		36 => signed'(x"0000000000A2F9836E4E441529FBF104A625C"),
		37 => signed'(x"0000000000517CC1B727220A94FE0CE18380B"),
		38 => signed'(x"000000000028BE60DB9391054A7F08FCA7CE1"),
		39 => signed'(x"0000000000145F306DC9C882A53F84CFD0A8C"),
		40 => signed'(x"00000000000A2F9836E4E441529FC27217EC9"),
		41 => signed'(x"00000000000517CC1B727220A94FE13A51E95"),
		42 => signed'(x"0000000000028BE60DB9391054A7F09D51B31"),
		43 => signed'(x"00000000000145F306DC9C882A53F84EADF15"),
		44 => signed'(x"000000000000A2F9836E4E441529FC27579BA"),
		45 => signed'(x"000000000000517CC1B727220A94FE13ABE23"),
		46 => signed'(x"00000000000028BE60DB9391054A7F09D5F3A"),
		47 => signed'(x"000000000000145F306DC9C882A53F84EAFA2"),
		48 to 63 => (others => '0')
	);
	constant NARROW_ANGLE_TABLE : narrow_angle_rom_t := (
		0 => signed'(x"0C90FDAA22168C234C4C6628B80DC"),
		1 => signed'(x"076B19C1586ED3DA2B7F222F65E1D"),
		2 => signed'(x"03EB6EBF25901BAC55B71E7BD7DE9"),
		3 => signed'(x"01FD5BA9AAC2F6DC65912F313E7D1"),
		4 => signed'(x"00FFAADDB967EF4E36CB2792DC0E3"),
		5 => signed'(x"007FF556EEA5D892A13BCEBBB6ED4"),
		6 => signed'(x"003FFEAAB776E5356EF9E31590058"),
		7 => signed'(x"001FFFD555BBBA972D00C46A3F77D"),
		8 => signed'(x"000FFFFAAAADDDDB94BB12AFB6B6D"),
		9 => signed'(x"0007FFFF55556EEEEA5CA6ADEAB02"),
		10 => signed'(x"0003FFFFEAAAAB77776E52E5A01A0"),
		11 => signed'(x"0001FFFFFD55555BBBBBA97297625"),
		12 => signed'(x"0000FFFFFFAAAAAADDDDDDB94B94D"),
		13 => signed'(x"00007FFFFFF5555556EEEEEEA5CA6"),
		14 => signed'(x"00003FFFFFFEAAAAAAB7777776E53"),
		15 => signed'(x"00001FFFFFFFD5555555BBBBBBBA9"),
		16 => signed'(x"00000FFFFFFFFAAAAAAAADDDDDDDE"),
		17 => signed'(x"000007FFFFFFFF555555556EEEEEF"),
		18 => signed'(x"000003FFFFFFFFEAAAAAAAAB77777"),
		19 => signed'(x"000001FFFFFFFFFD555555555BBBC"),
		20 => signed'(x"000000FFFFFFFFFFAAAAAAAAAADDE"),
		21 => signed'(x"0000007FFFFFFFFFF55555555556F"),
		22 => signed'(x"0000003FFFFFFFFFFEAAAAAAAAAAB"),
		23 => signed'(x"0000001FFFFFFFFFFFD5555555555"),
		24 => signed'(x"0000000FFFFFFFFFFFFAAAAAAAAAB"),
		25 => signed'(x"00000007FFFFFFFFFFFF555555555"),
		26 => signed'(x"00000003FFFFFFFFFFFFEAAAAAAAB"),
		27 => signed'(x"00000001FFFFFFFFFFFFFD5555555"),
		28 => signed'(x"00000000FFFFFFFFFFFFFFAAAAAAB"),
		29 => signed'(x"000000007FFFFFFFFFFFFFF555555"),
		30 => signed'(x"000000003FFFFFFFFFFFFFFEAAAAB"),
		31 => signed'(x"000000001FFFFFFFFFFFFFFFD5555"),
		32 => signed'(x"000000000FFFFFFFFFFFFFFFFAAAB"),
		33 => signed'(x"0000000007FFFFFFFFFFFFFFFF555"),
		34 => signed'(x"0000000003FFFFFFFFFFFFFFFFEAB"),
		35 => signed'(x"0000000001FFFFFFFFFFFFFFFFFD5"),
		36 => signed'(x"0000000000FFFFFFFFFFFFFFFFFFB"),
		37 => signed'(x"00000000007FFFFFFFFFFFFFFFFFF"),
		38 => signed'(x"00000000004000000000000000000"),
		39 => signed'(x"00000000002000000000000000000"),
		40 => signed'(x"00000000001000000000000000000"),
		41 => signed'(x"00000000000800000000000000000"),
		42 => signed'(x"00000000000400000000000000000"),
		43 => signed'(x"00000000000200000000000000000"),
		44 => signed'(x"00000000000100000000000000000"),
		45 => signed'(x"00000000000080000000000000000"),
		46 => signed'(x"00000000000040000000000000000"),
		47 => signed'(x"00000000000020000000000000000"),
		48 to 63 => (others => '0')
	);
	constant HYPERBOLIC_ANGLE_TABLE : hyperbolic_angle_rom_t := (
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
	function build_angle_rom return angle_rom_t is
		variable values : angle_rom_t := (others => (others => '0'));
	begin
		for index in WIDE_ANGLE_TABLE'range loop
			values(index) := WIDE_ANGLE_TABLE(index)(147 downto 8);
		end loop;
		for index in NARROW_ANGLE_TABLE'range loop
			values(64 + index) := resize(NARROW_ANGLE_TABLE(index),
				CORDIC_WIDTH);
		end loop;
		for index in HYPERBOLIC_ANGLE_TABLE'range loop
			values(128 + index) := resize(HYPERBOLIC_ANGLE_TABLE(index),
				CORDIC_WIDTH);
		end loop;
		return values;
	end function;

	signal angle_rom : angle_rom_t := build_angle_rom;
	attribute ramstyle : string;
	attribute ramstyle of angle_rom : signal is "M10K";

	function fit_precision(
			value : signed;
			narrow : std_logic) return cordic_value_t is
	begin
		if narrow = '1' then
			return resize(resize(value, NARROW_WIDTH), CORDIC_WIDTH);
		end if;
		return resize(value, CORDIC_WIDTH);
	end function;

	function fit_hyperbolic_xy(value : signed) return cordic_value_t is
	begin
		return resize(resize(value, HYPERBOLIC_XY_WIDTH), CORDIC_WIDTH);
	end function;

	function fit_hyperbolic_z(
			value : signed;
			vectoring_mode : std_logic) return cordic_value_t is
	begin
		if vectoring_mode = '1' then
			return resize(resize(value, HYPERBOLIC_Z_WIDTH), CORDIC_WIDTH);
		end if;
		return fit_hyperbolic_xy(value);
	end function;

	signal state : cordic_state_t := IDLE;
	signal vectoring_latched : std_logic := '0';
	signal narrow_latched : std_logic := '0';
	signal hyperbolic_latched : std_logic := '0';
	signal x_value : cordic_value_t := (others => '0');
	signal y_value : cordic_value_t := (others => '0');
	signal x_next : cordic_value_t := (others => '0');
	signal z_value : cordic_value_t := (others => '0');
	signal iteration : natural range 0 to WIDE_ITERATIONS := 0;
	signal angle_address : natural range 0 to 47 := 0;
	signal hyperbolic_angle_address : natural range 1 to 31 := 1;
	signal angle_rom_address : natural range 0 to 159;
	signal angle_data : cordic_value_t := (others => '0');
	signal shift_angle : cordic_value_t := (others => '0');
	signal repeat_iteration : std_logic := '0';
	signal active_vectoring : std_logic;
	signal active_narrow : std_logic;
	signal active_hyperbolic : std_logic;
	signal active_iteration : natural range 0 to WIDE_ITERATIONS;
	signal active_x : cordic_value_t;
	signal active_y : cordic_value_t;
	signal active_z : cordic_value_t;
	signal active_angle : cordic_value_t;
	signal active_direction : std_logic;
	signal shift_source : cordic_value_t;
	signal shifted_coordinate : cordic_value_t;
	signal x_addend : cordic_value_t;
	signal y_addend : cordic_value_t;
	signal z_addend : cordic_value_t;
	signal x_subtract : std_logic;
	signal y_subtract : std_logic;
	signal z_subtract : std_logic;
	signal xy_arithmetic_result : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal z_arithmetic_result : unsigned(CORDIC_WIDTH - 1 downto 0);
	signal fitted_x_result : cordic_value_t;
	signal fitted_y_result : cordic_value_t;
	signal fitted_z_result : cordic_value_t;
begin
	active_vectoring <= vectoring when state = IDLE else vectoring_latched;
	active_narrow <= narrow_precision when state = IDLE else narrow_latched;
	active_hyperbolic <= hyperbolic when state = IDLE else
		hyperbolic_latched;
	active_iteration <= 1 when state = IDLE and hyperbolic = '1' else
		iteration;
	active_x <= fit_hyperbolic_xy(x_input) when
		state = IDLE and hyperbolic = '1' else
		fit_precision(x_input, narrow_precision) when state = IDLE else x_value;
	active_y <= fit_hyperbolic_xy(y_input) when
		state = IDLE and hyperbolic = '1' else
		fit_precision(y_input, narrow_precision) when state = IDLE else y_value;
	active_z <= fit_hyperbolic_z(z_input, vectoring) when
		state = IDLE and hyperbolic = '1' else
		fit_precision(z_input, narrow_precision) when state = IDLE else z_value;
	angle_rom_address <= 128 + hyperbolic_angle_address when
		active_hyperbolic = '1' else
		64 + angle_address when active_narrow = '1' else angle_address;
	active_angle <= resize(HYPERBOLIC_ANGLE_ONE, CORDIC_WIDTH) when
		state = IDLE and hyperbolic = '1' else
		resize(NARROW_ANGLE_ZERO, CORDIC_WIDTH) when
		state = IDLE and narrow_precision = '1' else
		WIDE_ANGLE_ZERO when state = IDLE else
		angle_data when
		active_hyperbolic = '1' and iteration <= 31 else
		shift_angle when active_hyperbolic = '1' else
		angle_data when iteration <= 47 else shift_angle;
	active_direction <= '1' when
		(active_vectoring = '1' and active_hyperbolic = '1' and
			active_y >= 0) or
		(active_vectoring = '1' and active_hyperbolic = '0' and
			active_y > 0) or
		(active_vectoring = '0' and active_z >= 0) else '0';
	shift_source <= active_y when state = ROTATE_XY or
		(state = IDLE and start = '1' and rotate_on_start = '1') else
		x_value;
	shift_source_out <= resize(shift_source, shift_source_out'length);
	shift_amount_out <= active_iteration;

	with_shift_stage : if INCLUDE_SHIFT_STAGE generate
		shifted_coordinate <= shift_right(shift_source, active_iteration);
	end generate;

	without_shift_stage : if not INCLUDE_SHIFT_STAGE generate
		shifted_coordinate <= resize(external_shifted_coordinate,
			CORDIC_WIDTH);
	end generate;

	busy <= '1' when state /= IDLE or start = '1' else '0';
	done <= '1' when state = COMPLETE else '0';
	x_result <= resize(x_value, x_result'length);
	y_result <= resize(y_value, y_result'length);
	z_result <= resize(z_value, z_result'length);

	arithmetic_operands : process(state, start, rotate_on_start,
		active_vectoring, active_hyperbolic, active_y, active_z,
		active_angle, active_direction, shifted_coordinate)
	begin
		x_addend <= (others => '0');
		y_addend <= (others => '0');
		z_addend <= (others => '0');
		x_subtract <= '0';
		y_subtract <= '0';
		z_subtract <= '0';
		if active_hyperbolic = '1' then
			if state = ROTATE_XY or
					(state = IDLE and start = '1' and
					rotate_on_start = '1') then
				x_addend <= shifted_coordinate;
				if (active_vectoring = '1' and active_y >= 0) or
						(active_vectoring = '0' and active_z < 0) then
					x_subtract <= '1';
				end if;
			elsif state = ROTATE_Z then
				y_addend <= shifted_coordinate;
				z_addend <= active_angle;
				if active_vectoring = '1' then
					z_subtract <= not active_direction;
				else
					z_subtract <= active_direction;
				end if;
				if (active_vectoring = '1' and active_direction = '1') or
						(active_vectoring = '0' and
						active_direction = '0') then
					y_subtract <= '1';
				end if;
			end if;
		else
			x_addend <= shifted_coordinate;
			y_addend <= shifted_coordinate;
			z_addend <= active_angle;
			if active_vectoring = '1' then
				if active_y = 0 then
					x_addend <= (others => '0');
					y_addend <= (others => '0');
					z_addend <= (others => '0');
				elsif active_y > 0 then
					y_subtract <= '1';
				else
					x_subtract <= '1';
					z_subtract <= '1';
				end if;
			else
				if active_direction = '1' then
					x_subtract <= '1';
					z_subtract <= '1';
				else
					y_subtract <= '1';
				end if;
			end if;
		end if;
	end process;

	arithmetic_add_subtract : process(x_subtract, active_x, x_addend,
			y_subtract, y_value, y_addend, z_subtract, z_value, z_addend,
			state)
		variable xy_left : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable xy_right : unsigned(CORDIC_WIDTH - 1 downto 0);
		variable xy_subtract : std_logic;
	begin
		if state = ROTATE_Z then
			xy_left := unsigned(y_value);
			xy_right := unsigned(y_addend);
			xy_subtract := y_subtract;
		else
			xy_left := unsigned(active_x);
			xy_right := unsigned(x_addend);
			xy_subtract := x_subtract;
		end if;
		if xy_subtract = '1' then
			xy_arithmetic_result <= xy_left - xy_right;
		else
			xy_arithmetic_result <= xy_left + xy_right;
		end if;
		if z_subtract = '1' then
			z_arithmetic_result <= unsigned(z_value) - unsigned(z_addend);
		else
			z_arithmetic_result <= unsigned(z_value) + unsigned(z_addend);
		end if;
	end process;

	fitted_x_result <= fit_hyperbolic_xy(signed(xy_arithmetic_result)) when
		active_hyperbolic = '1' else
		fit_precision(signed(xy_arithmetic_result), active_narrow);
	fitted_y_result <= fit_hyperbolic_xy(signed(xy_arithmetic_result)) when
		active_hyperbolic = '1' else
		fit_precision(signed(xy_arithmetic_result), active_narrow);
	fitted_z_result <= fit_hyperbolic_z(signed(z_arithmetic_result),
		active_vectoring) when active_hyperbolic = '1' else
		fit_precision(signed(z_arithmetic_result), active_narrow);

	cordic_sequence : process(clk)
		variable next_tail : cordic_value_t;
	begin
		if rising_edge(clk) then
			angle_data <= angle_rom(angle_rom_address);
			if nReset = '0' then
				state <= IDLE;
				vectoring_latched <= '0';
				narrow_latched <= '0';
				hyperbolic_latched <= '0';
				x_value <= (others => '0');
				y_value <= (others => '0');
				x_next <= (others => '0');
				z_value <= (others => '0');
				iteration <= 0;
				angle_address <= 0;
				hyperbolic_angle_address <= 1;
				shift_angle <= (others => '0');
				repeat_iteration <= '0';
			else
				case state is
					when IDLE =>
						angle_address <= 0;
						hyperbolic_angle_address <= 1;
						repeat_iteration <= '0';
						if hyperbolic = '1' then
							iteration <= 1;
						else
							iteration <= 0;
						end if;
						if start = '1' then
							vectoring_latched <= vectoring;
							narrow_latched <= narrow_precision;
							hyperbolic_latched <= hyperbolic;
							x_value <= active_x;
							y_value <= active_y;
							z_value <= active_z;
							shift_angle <= (others => '0');
							if rotate_on_start = '1' then
								x_next <= fitted_x_result;
								if hyperbolic = '1' then
									hyperbolic_angle_address <= 2;
								else
									angle_address <= 1;
								end if;
								state <= ROTATE_Z;
							else
								state <= ROTATE_XY;
							end if;
						end if;

					when ROTATE_XY =>
						x_next <= fitted_x_result;
						if hyperbolic_latched = '1' then
							if not ((iteration = 4 or iteration = 13 or
									iteration = 40) and
									repeat_iteration = '0') then
								if iteration < 31 then
									hyperbolic_angle_address <= iteration + 1;
								elsif iteration = 31 then
									next_tail := (others => '0');
									next_tail(64) := '1';
									shift_angle <= next_tail;
								end if;
							end if;
						elsif iteration < 47 then
							angle_address <= iteration + 1;
						elsif iteration = 47 then
							if narrow_latched = '1' then
								next_tail := (others => '0');
								next_tail(64) := '1';
								shift_angle <= next_tail;
							else
								shift_angle <= signed'(
								x"0000000000000A2F9836E4E441529FC2757");
							end if;
						end if;
						state <= ROTATE_Z;

					when ROTATE_Z =>
						x_value <= x_next;
						z_value <= fitted_z_result;
						y_value <= fitted_y_result;
						if hyperbolic_latched = '1' and
								(iteration = 4 or iteration = 13 or
								iteration = 40) and repeat_iteration = '0' then
							repeat_iteration <= '1';
							state <= ROTATE_XY;
						elsif hyperbolic_latched = '1' and
								iteration = HYPERBOLIC_ITERATIONS then
							state <= COMPLETE;
						elsif hyperbolic_latched = '0' and
								((narrow_latched = '1' and
								iteration = NARROW_ITERATIONS) or
								(narrow_latched = '0' and
								iteration = WIDE_ITERATIONS)) then
							state <= COMPLETE;
						else
							if (hyperbolic_latched = '1' and iteration > 31) or
									(hyperbolic_latched = '0' and iteration > 47) then
								shift_angle <= shift_right(shift_angle, 1);
							end if;
							repeat_iteration <= '0';
							iteration <= iteration + 1;
							state <= ROTATE_XY;
						end if;

					when COMPLETE =>
						angle_address <= 0;
						hyperbolic_angle_address <= 1;
						repeat_iteration <= '0';
						iteration <= 0;
						state <= IDLE;
				end case;
			end if;
		end if;
	end process;
end architecture;
