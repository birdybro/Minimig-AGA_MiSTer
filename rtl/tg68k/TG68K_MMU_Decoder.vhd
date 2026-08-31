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
use work.TG68K_MMU_Pack.all;

entity TG68K_MMU_Decoder is
	port(
		descriptor_data : in std_logic_vector(63 downto 0);
		descriptor_format : in mmu_descriptor_format_t;
		leaf_level : in std_logic;
		descriptor_info : out mmu_descriptor_info_t
	);
end entity;

architecture rtl of TG68K_MMU_Decoder is
begin
	descriptor_info <= mmu_decode_descriptor(descriptor_data,
		descriptor_format, leaf_level);
end architecture;
