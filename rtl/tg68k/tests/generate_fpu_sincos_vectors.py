#!/usr/bin/env python3

from fpu_exact_reference import mode_name, precision_name
from generate_fpu_sin_vectors import reference_trig, source_values


def emit_testbench() -> None:
    vectors = []
    for source in source_values():
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                sine, condition_codes, status = reference_trig(
                    source, precision_bits, mode, False)
                cosine, _, _ = reference_trig(
                    source, precision_bits, mode, True)
                vectors.append((source, precision, mode_name(mode), sine,
                                cosine, condition_codes, status))

    print("""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_sincos_differential is
end entity;

architecture test of tb_tg68k_fpu_sincos_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        source_value : fpu_extended_t;
        precision_value : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_sine : fpu_extended_t;
        expected_cosine : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        source, precision, mode, sine, cosine, cc, status = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:020X}", {precision}, {mode}, '
              f'x"{sine:020X}", x"{cosine:020X}", x"{cc:X}", '
              f'x"{status:02X}"){suffix}')
    print("""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal start : std_logic := '0';
    signal source : fpu_extended_t := (others => '0');
    signal rounding_precision : fpu_rounding_precision_t :=
        FPU_PRECISION_EXTENDED;
    signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal sine_result : fpu_extended_t;
    signal cosine_round_input : fpu_round_input_t;
    signal cosine_result : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
    signal done : std_logic;
    signal cordic_start : std_logic;
    signal cordic_x_input : signed(147 downto 0);
    signal cordic_y_input : signed(147 downto 0);
    signal cordic_z_input : signed(147 downto 0);
    signal cordic_x_result : signed(147 downto 0);
    signal cordic_y_result : signed(147 downto 0);
    signal cordic_done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    cordic : entity work.TG68K_FPU_Circular_CORDIC
        port map(
            clk => clk, nReset => nReset, start => cordic_start,
            vectoring => '0', narrow_precision => '0',
            rotate_on_start => '1', x_input => cordic_x_input,
            y_input => cordic_y_input, z_input => cordic_z_input,
            x_result => cordic_x_result, y_result => cordic_y_result,
            z_result => open, busy => open, done => cordic_done
        );

    dut : entity work.TG68K_FPU_Sine_Cosine
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            cosine => '0',
            tangent => '0',
            simultaneous => '1',
            source => source,
            rounding_precision => rounding_precision,
            rounding_mode => rounding_mode,
            cordic_start => cordic_start,
            cordic_x_input => cordic_x_input,
            cordic_y_input => cordic_y_input,
            cordic_z_input => cordic_z_input,
            cordic_x_result => cordic_x_result,
            cordic_y_result => cordic_y_result,
            cordic_done => cordic_done,
            result => sine_result,
            condition_codes => condition_codes,
            exception_status => exception_status,
            busy => open,
            done => done,
            round_input => open,
            secondary_round_input => cosine_round_input,
            base_exception_status => open
        );

    cosine_rounder : entity work.TG68K_FPU_Round
        port map(
            input_class => cosine_round_input.data_class,
            input_sign => cosine_round_input.sign,
            input_exponent => cosine_round_input.exponent,
            input_significand => cosine_round_input.significand,
            special_value => cosine_round_input.special,
            rounding_precision => rounding_precision,
            rounding_mode => rounding_mode,
            single_extended_range => '0',
            result => cosine_result,
            inexact => open,
            overflow => open,
            underflow => open,
            signaling_nan => open
        );

    stimulus : process
        variable cycles : natural;
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        nReset <= '1';
        wait until rising_edge(clk);
        for index in vectors'range loop
            wait until falling_edge(clk);
            source <= vectors(index).source_value;
            rounding_precision <= vectors(index).precision_value;
            rounding_mode <= vectors(index).mode_value;
            start <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            start <= '0';
            cycles := 0;
            while done = '0' loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycles := cycles + 1;
                assert cycles < 454
                    report "differential FSINCOS timeout" severity failure;
            end loop;
            assert sine_result = vectors(index).expected_sine and
                cosine_result = vectors(index).expected_cosine and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FSINCOS vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " sine=" & to_hstring(sine_result) &
                    " expected_sine=" & to_hstring(vectors(index).expected_sine) &
                    " cosine=" & to_hstring(cosine_result) &
                    " expected_cosine=" & to_hstring(vectors(index).expected_cosine) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1152 high-precision FSINCOS vector pairs" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
