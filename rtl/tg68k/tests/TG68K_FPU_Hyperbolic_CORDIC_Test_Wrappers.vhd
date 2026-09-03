library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Exponential_With_CORDIC is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		exponential_base : in fpu_exponential_base_t;
		subtract_one : in std_logic;
		hyperbolic_sine : in std_logic := '0';
		hyperbolic_cosine : in std_logic := '0';
		hyperbolic_tangent : in std_logic := '0';
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture test of TG68K_FPU_Exponential_With_CORDIC is
	signal cordic_start : std_logic;
	signal cordic_x_input : signed(99 downto 0);
	signal cordic_y_input : signed(99 downto 0);
	signal cordic_z_input : signed(112 downto 0);
	signal cordic_x_result : signed(99 downto 0);
	signal cordic_y_result : signed(99 downto 0);
	signal cordic_done : std_logic;
begin
	cordic : entity work.TG68K_FPU_Hyperbolic_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => cordic_start,
			vectoring => '0',
			rotate_on_start => '1',
			x_input => cordic_x_input,
			y_input => cordic_y_input,
			z_input => cordic_z_input,
			external_shifted_coordinate => (others => '0'),
			shift_source_out => open,
			shift_amount_out => open,
			x_result => cordic_x_result,
			y_result => cordic_y_result,
			z_result => open,
			busy => open,
			done => cordic_done
		);

	dut : entity work.TG68K_FPU_Exponential
		generic map(
			INCLUDE_ROUNDING_STAGE => INCLUDE_ROUNDING_STAGE
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			exponential_base => exponential_base,
			subtract_one => subtract_one,
			hyperbolic_sine => hyperbolic_sine,
			hyperbolic_cosine => hyperbolic_cosine,
			hyperbolic_tangent => hyperbolic_tangent,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			cordic_start => cordic_start,
			cordic_x_input => cordic_x_input,
			cordic_y_input => cordic_y_input,
			cordic_z_input => cordic_z_input,
			cordic_x_result => cordic_x_result,
			cordic_y_result => cordic_y_result,
			cordic_done => cordic_done,
			series_arithmetic_start => open,
			series_cube_divide => open,
			series_divide_by_six => open,
			series_arithmetic_source => open,
			series_square_high => open,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			busy => busy,
			done => done,
			round_input => round_input,
			base_exception_status => base_exception_status
		);
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.TG68K_FPU_Pack.all;

entity TG68K_FPU_Logarithm_With_CORDIC is
	generic(
		INCLUDE_ROUNDING_STAGE : boolean := true
	);
	port(
		clk : in std_logic;
		nReset : in std_logic;
		start : in std_logic;
		source : in fpu_extended_t;
		add_one : in std_logic;
		logarithm_base : in fpu_logarithm_base_t;
		inverse_hyperbolic_tangent : in std_logic := '0';
		rounding_precision : in fpu_rounding_precision_t;
		rounding_mode : in fpu_rounding_mode_t;
		result : out fpu_extended_t;
		condition_codes : out std_logic_vector(3 downto 0);
		exception_status : out std_logic_vector(7 downto 0);
		busy : out std_logic;
		done : out std_logic;
		round_input : out fpu_round_input_t;
		base_exception_status : out std_logic_vector(7 downto 0)
	);
end entity;

architecture test of TG68K_FPU_Logarithm_With_CORDIC is
	signal cordic_start : std_logic;
	signal cordic_x_input : signed(99 downto 0);
	signal cordic_y_input : signed(99 downto 0);
	signal cordic_z_input : signed(112 downto 0);
	signal cordic_z_result : signed(112 downto 0);
	signal cordic_done : std_logic;
begin
	cordic : entity work.TG68K_FPU_Hyperbolic_CORDIC
		port map(
			clk => clk,
			nReset => nReset,
			start => cordic_start,
			vectoring => '1',
			rotate_on_start => '0',
			x_input => cordic_x_input,
			y_input => cordic_y_input,
			z_input => cordic_z_input,
			external_shifted_coordinate => (others => '0'),
			shift_source_out => open,
			shift_amount_out => open,
			x_result => open,
			y_result => open,
			z_result => cordic_z_result,
			busy => open,
			done => cordic_done
		);

	dut : entity work.TG68K_FPU_Logarithm
		generic map(
			INCLUDE_ROUNDING_STAGE => INCLUDE_ROUNDING_STAGE
		)
		port map(
			clk => clk,
			nReset => nReset,
			start => start,
			source => source,
			add_one => add_one,
			logarithm_base => logarithm_base,
			inverse_hyperbolic_tangent => inverse_hyperbolic_tangent,
			rounding_precision => rounding_precision,
			rounding_mode => rounding_mode,
			cordic_start => cordic_start,
			cordic_x_input => cordic_x_input,
			cordic_y_input => cordic_y_input,
			cordic_z_input => cordic_z_input,
			cordic_z_result => cordic_z_result,
			cordic_done => cordic_done,
			series_arithmetic_start => open,
			series_cube_divide => open,
			series_divide_by_six => open,
			series_arithmetic_source => open,
			series_square_high => open,
			result => result,
			condition_codes => condition_codes,
			exception_status => exception_status,
			busy => busy,
			done => done,
			round_input => round_input,
			base_exception_status => base_exception_status
		);
end architecture;
