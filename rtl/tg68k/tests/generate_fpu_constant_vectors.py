#!/usr/bin/env python3

from fpu_exact_reference import mode_name, precision_name


CONSTANTS = (
    (0x00, 0x4000, 0xC90FDAA22168C235, -1),
    (0x0B, 0x3FFD, 0x9A209A84FBCFF798, 1),
    (0x0C, 0x4000, 0xADF85458A2BB4A9A, 1),
    (0x0D, 0x3FFF, 0xB8AA3B295C17F0BC, -1),
    (0x0E, 0x3FFD, 0xDE5BD8A937287195, 0),
    (0x0F, 0x0000, 0x0000000000000000, 0),
    (0x30, 0x3FFE, 0xB17217F7D1CF79AC, -1),
    (0x31, 0x4000, 0x935D8DDDAAA8AC17, -1),
    (0x32, 0x3FFF, 0x8000000000000000, 0),
    (0x33, 0x4002, 0xA000000000000000, 0),
    (0x34, 0x4005, 0xC800000000000000, 0),
    (0x35, 0x400C, 0x9C40000000000000, 0),
    (0x36, 0x4019, 0xBEBC200000000000, 0),
    (0x37, 0x4034, 0x8E1BC9BF04000000, 0),
    (0x38, 0x4069, 0x9DC5ADA82B70B59E, -1),
    (0x39, 0x40D3, 0xC2781F49FFCFA6D5, 1),
    (0x3A, 0x41A8, 0x93BA47C980E98CE0, -1),
    (0x3B, 0x4351, 0xAA7EEBFB9DF9DE8E, -1),
    (0x3C, 0x46A3, 0xE319A0AEA60E91C7, -1),
    (0x3D, 0x4D48, 0xC976758681750C17, 1),
    (0x3E, 0x5A92, 0x9E8B3B5DC53D5DE5, -1),
    (0x3F, 0x7525, 0xC46052028A20979B, -1),
)


def round_constant(exponent: int, significand: int, tail: int,
                   precision: int, mode: int) -> tuple[int, int, int]:
    if significand == 0:
        return 0, 4, 0
    if tail < 0:
        intermediate = (significand - 1) * 8 + 5
    elif tail > 0:
        intermediate = significand * 8 + 1
    else:
        intermediate = significand * 8
    discarded_bits = 67 - precision
    quotient, remainder = divmod(intermediate, 1 << discarded_bits)
    increment = False
    if mode == 0:
        midpoint = 1 << (discarded_bits - 1)
        increment = remainder > midpoint or (
            remainder == midpoint and (quotient & 1) != 0)
    elif mode == 3:
        increment = remainder != 0
    if increment:
        quotient += 1
    if quotient == 1 << precision:
        quotient >>= 1
        exponent += 1
    rounded_significand = quotient << (64 - precision)
    result = (exponent << 64) | rounded_significand
    return result, 0, 0x02 if remainder else 0


def make_vectors():
    vectors = []
    for offset, exponent, significand, tail in CONSTANTS:
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = round_constant(
                    exponent, significand, tail, precision_bits, mode)
                vectors.append((offset, precision, mode_name(mode), result,
                                condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_constant_differential is
end entity;

architecture test of tb_tg68k_fpu_constant_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        offset_value : std_logic_vector(5 downto 0);
        precision_value : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_result : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        offset, precision, mode, result, cc, status = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (std_logic_vector(to_unsigned(16#{offset:02X}#, 6)), '
              f'{precision}, {mode}, x"{result:020X}", x"{cc:X}", '
              f'x"{status:02X}"){suffix}')
    print("""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal start : std_logic := '0';
    signal rom_offset : std_logic_vector(5 downto 0) := (others => '0');
    signal rounding_precision : fpu_rounding_precision_t :=
        FPU_PRECISION_EXTENDED;
    signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal fp_register_write : std_logic;
    signal fp_register_write_data : fpu_extended_t;
    signal operation_status_write : std_logic;
    signal condition_codes_write : std_logic;
    signal operation_condition_codes : std_logic_vector(3 downto 0);
    signal operation_exception_status : std_logic_vector(7 downto 0);
    signal busy : std_logic;
    signal done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.TG68K_FPU_Constant_Controller
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            rom_offset => rom_offset,
            rounding_precision => rounding_precision,
            rounding_mode => rounding_mode,
            fp_register_write => fp_register_write,
            fp_register_write_data => fp_register_write_data,
            operation_status_write => operation_status_write,
            condition_codes_write => condition_codes_write,
            operation_condition_codes => operation_condition_codes,
            operation_exception_status => operation_exception_status,
            busy => busy,
            done => done
        );

    stimulus : process
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        nReset <= '1';
        wait until rising_edge(clk);
        for index in vectors'range loop
            wait until falling_edge(clk);
            rom_offset <= vectors(index).offset_value;
            rounding_precision <= vectors(index).precision_value;
            rounding_mode <= vectors(index).mode_value;
            start <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            start <= '0';
            assert fp_register_write = '1' and
                operation_status_write = '1' and
                condition_codes_write = '1' and
                fp_register_write_data = vectors(index).expected_result and
                operation_condition_codes = vectors(index).expected_cc and
                operation_exception_status = vectors(index).expected_status
                report "differential FMOVECR vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(fp_register_write_data) &
                    " cc=" & to_hstring(operation_condition_codes) &
                    " status=" & to_hstring(operation_exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
            assert done = '1'
                report "differential FMOVECR completion mismatch"
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 264 FMOVECR ROM/precision/rounding vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
