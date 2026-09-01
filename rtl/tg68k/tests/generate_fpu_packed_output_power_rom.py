#!/usr/bin/env python3

POWER_BIT_COUNT = 192
SEGMENT_SIZE = 128
RESIDUAL_COUNT = SEGMENT_SIZE
CHUNK_COUNT = 39
CHUNK_BASE = 128
INVERSE_BASE = 256


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
    numerator = 1 << (power_bits - 2 + POWER_BIT_COUNT)
    multiplier = (numerator + power - 1) // power
    return multiplier, power_bits


def emit_rom() -> None:
    values = {}
    for exponent in range(RESIDUAL_COUNT):
        values[exponent] = normalized_power(exponent)
        values[INVERSE_BASE + exponent] = normalized_inverse(exponent)
    for index in range(CHUNK_COUNT):
        exponent = index * SEGMENT_SIZE
        values[CHUNK_BASE + index] = normalized_power(exponent)
        values[INVERSE_BASE + CHUNK_BASE + index] = normalized_inverse(exponent)

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

entity TG68K_FPU_Packed_Output_Power_ROM is
    port(
        clk : in std_logic;
        inverse : in std_logic;
        chunk : in std_logic;
        index : in unsigned(6 downto 0);
        multiplier : out unsigned(191 downto 0);
        power_bits : out unsigned(13 downto 0)
    );
end entity;

architecture rtl of TG68K_FPU_Packed_Output_Power_ROM is
    constant CHUNK_BASE : natural := 128;
    constant INVERSE_BASE : natural := 256;
    type power_rom_t is array(0 to 511) of std_logic_vector(207 downto 0);
    signal power_rom : power_rom_t := (""")
    for address in sorted(values):
        multiplier, power_bits = values[address]
        packed_value = (multiplier << 14) | power_bits
        print(f'        {address} => x"{packed_value:052X}",')
    print("""        others => (others => '0')
    );
    attribute ramstyle : string;
    attribute ramstyle of power_rom : signal is "M10K";
begin
    read_power : process(clk)
        variable address : natural range 0 to 511;
    begin
        if rising_edge(clk) then
            address := to_integer(index);
            if chunk = '1' then
                address := address + CHUNK_BASE;
            end if;
            if inverse = '1' then
                address := address + INVERSE_BASE;
            end if;
            multiplier <= unsigned(power_rom(address)(205 downto 14));
            power_bits <= unsigned(power_rom(address)(13 downto 0));
        end if;
    end process;
end architecture;
""", end="")


if __name__ == "__main__":
    emit_rom()
