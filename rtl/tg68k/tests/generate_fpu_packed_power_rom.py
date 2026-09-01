#!/usr/bin/env python3

POWER_BIT_COUNT = 125
MAXIMUM_EXPONENT = 1681
INVERSE_BASE = MAXIMUM_EXPONENT + 1


def normalized_power(exponent: int) -> tuple[int, int]:
    power = 5 ** exponent
    power_bits = power.bit_length()
    shift = POWER_BIT_COUNT - power_bits
    if shift >= 0:
        multiplier = power << shift
    else:
        multiplier = power >> -shift
    return multiplier, power_bits


def normalized_inverse(exponent: int) -> tuple[int, int]:
    power = 5 ** exponent
    power_bits = power.bit_length()
    multiplier = (1 << (power_bits - 1 + POWER_BIT_COUNT)) // power + 1
    return multiplier, power_bits


def emit_rom() -> None:
    values = []
    for exponent in range(MAXIMUM_EXPONENT + 1):
        values.append(normalized_power(exponent))
    for exponent in range(MAXIMUM_EXPONENT + 1):
        values.append(normalized_inverse(exponent))

    print("""------------------------------------------------------------------------------
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

entity TG68K_FPU_Packed_Power_ROM is
    port(
        clk : in std_logic;
        inverse : in std_logic;
        exponent : in unsigned(10 downto 0);
        multiplier : out unsigned(127 downto 0);
        power_bits : out unsigned(11 downto 0)
    );
end entity;

architecture rtl of TG68K_FPU_Packed_Power_ROM is
    constant INVERSE_BASE : natural := 1682;
    type power_rom_t is array(0 to 4095) of std_logic_vector(139 downto 0);
    signal power_rom : power_rom_t := (""")
    for index, (multiplier, power_bits) in enumerate(values):
        print(f'        {index} => x"{multiplier:032X}{power_bits:03X}",')
    print("""        others => (others => '0')
    );
    attribute ramstyle : string;
    attribute ramstyle of power_rom : signal is "M10K";
begin
    read_power : process(clk)
        variable address : natural range 0 to 4095;
    begin
        if rising_edge(clk) then
            address := to_integer(exponent);
            if inverse = '1' then
                address := address + INVERSE_BASE;
            end if;
            multiplier <= unsigned(power_rom(address)(139 downto 12));
            power_bits <= unsigned(power_rom(address)(11 downto 0));
        end if;
    end process;
end architecture;
""", end="")


if __name__ == "__main__":
    emit_rom()
