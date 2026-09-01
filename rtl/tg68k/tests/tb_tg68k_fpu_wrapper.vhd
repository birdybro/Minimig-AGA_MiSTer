library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tg68k_fpu_wrapper is
end entity;

architecture test of tb_tg68k_fpu_wrapper is
	constant CLK_PERIOD : time := 10 ns;
	constant MEMORY_WORDS : natural := 8192;
	type memory_t is array (0 to MEMORY_WORDS - 1) of
		std_logic_vector(15 downto 0);

	function initial_memory return memory_t is
		variable result : memory_t := (others => x"4E71");
	begin
		result(16#0000#) := x"0000";
		result(16#0001#) := x"1000";
		result(16#0002#) := x"0000";
		result(16#0003#) := x"0100";
		result(16#0080#) := x"7405";
		result(16#0081#) := x"F202";
		result(16#0082#) := x"4180";
		result(16#0083#) := x"F200";
		result(16#0084#) := x"0E00";
		result(16#0085#) := x"207C";
		result(16#0086#) := x"0000";
		result(16#0087#) := x"0300";
		result(16#0088#) := x"F210";
		result(16#0089#) := x"6600";
		result(16#008A#) := x"F210";
		result(16#008B#) := x"4700";
		result(16#008C#) := x"F201";
		result(16#008D#) := x"6700";
		result(16#008E#) := x"23C1";
		result(16#008F#) := x"0000";
		result(16#0090#) := x"0200";
		result(16#0091#) := x"227C";
		result(16#0092#) := x"0000";
		result(16#0093#) := x"0400";
		result(16#0094#) := x"F219";
		result(16#0095#) := x"6980";
		result(16#0096#) := x"F221";
		result(16#0097#) := x"4A80";
		result(16#0098#) := x"F200";
		result(16#0099#) := x"6680";
		result(16#009A#) := x"23C9";
		result(16#009B#) := x"0000";
		result(16#009C#) := x"0204";
		result(16#009D#) := x"23C0";
		result(16#009E#) := x"0000";
		result(16#009F#) := x"0208";
		result(16#00A0#) := x"263C";
		result(16#00A1#) := x"0000";
		result(16#00A2#) := x"00B0";
		result(16#00A3#) := x"F203";
		result(16#00A4#) := x"9000";
		result(16#00A5#) := x"F204";
		result(16#00A6#) := x"B000";
		result(16#00A7#) := x"23C4";
		result(16#00A8#) := x"0000";
		result(16#00A9#) := x"020C";
		result(16#00AA#) := x"247C";
		result(16#00AB#) := x"0000";
		result(16#00AC#) := x"0500";
		result(16#00AD#) := x"F21A";
		result(16#00AE#) := x"9C00";
		result(16#00AF#) := x"267C";
		result(16#00B0#) := x"0000";
		result(16#00B1#) := x"0600";
		result(16#00B2#) := x"F21B";
		result(16#00B3#) := x"BC00";
		result(16#00B4#) := x"23CA";
		result(16#00B5#) := x"0000";
		result(16#00B6#) := x"0210";
		result(16#00B7#) := x"23CB";
		result(16#00B8#) := x"0000";
		result(16#00B9#) := x"0214";
		result(16#00BA#) := x"287C";
		result(16#00BB#) := x"0000";
		result(16#00BC#) := x"0700";
		result(16#00BD#) := x"F21C";
		result(16#00BE#) := x"D081";
		result(16#00BF#) := x"2A7C";
		result(16#00C0#) := x"0000";
		result(16#00C1#) := x"0800";
		result(16#00C2#) := x"F215";
		result(16#00C3#) := x"F081";
		result(16#00C4#) := x"F224";
		result(16#00C5#) := x"E081";
		result(16#00C6#) := x"23CC";
		result(16#00C7#) := x"0000";
		result(16#00C8#) := x"0218";
		result(16#00C9#) := x"23CD";
		result(16#00CA#) := x"0000";
		result(16#00CB#) := x"021C";
		result(16#00CC#) := x"7A04";
		result(16#00CD#) := x"2C7C";
		result(16#00CE#) := x"0000";
		result(16#00CF#) := x"0900";
		result(16#00D0#) := x"F21E";
		result(16#00D1#) := x"D850";
		result(16#00D2#) := x"2C7C";
		result(16#00D3#) := x"0000";
		result(16#00D4#) := x"0A00";
		result(16#00D5#) := x"F216";
		result(16#00D6#) := x"F850";
		result(16#00D7#) := x"F200";
		result(16#00D8#) := x"171A";
		result(16#00D9#) := x"F200";
		result(16#00DA#) := x"1B98";
		result(16#00DB#) := x"F200";
		result(16#00DC#) := x"183A";
		result(16#00DD#) := x"F239";
		result(16#00DE#) := x"6780";
		result(16#00DF#) := x"0000";
		result(16#00E0#) := x"0B00";
		result(16#00E1#) := x"F200";
		result(16#00E2#) := x"1FA2";
		result(16#00E3#) := x"F239";
		result(16#00E4#) := x"6780";
		result(16#00E5#) := x"0000";
		result(16#00E6#) := x"0B10";
		result(16#00E7#) := x"F200";
		result(16#00E8#) := x"1FA3";
		result(16#00E9#) := x"F239";
		result(16#00EA#) := x"6780";
		result(16#00EB#) := x"0000";
		result(16#00EC#) := x"0B18";
		result(16#00ED#) := x"F200";
		result(16#00EE#) := x"1FA0";
		result(16#00EF#) := x"F200";
		result(16#00F0#) := x"1F84";
		result(16#00F1#) := x"F239";
		result(16#00F2#) := x"6780";
		result(16#00F3#) := x"0000";
		result(16#00F4#) := x"0B1C";
		result(16#00F5#) := x"4EF9";
		result(16#00F6#) := x"0000";
		result(16#00F7#) := x"1000";
		result(16#0280#) := x"0000";
		result(16#0281#) := x"0030";
		result(16#0282#) := x"A5A5";
		result(16#0283#) := x"1234";
		result(16#0284#) := x"1122";
		result(16#0285#) := x"3344";
		result(16#0380#) := x"4000";
		result(16#0381#) := x"DEAD";
		result(16#0382#) := x"8000";
		result(16#0383#) := x"0000";
		result(16#0384#) := x"0000";
		result(16#0385#) := x"0007";
		result(16#0386#) := x"4001";
		result(16#0387#) := x"BEEF";
		result(16#0388#) := x"9000";
		result(16#0389#) := x"0000";
		result(16#038A#) := x"0000";
		result(16#038B#) := x"0000";
		result(16#0480#) := x"4005";
		result(16#0481#) := x"CAFE";
		result(16#0482#) := x"A000";
		result(16#0483#) := x"0000";
		result(16#0484#) := x"0000";
		result(16#0485#) := x"0005";
		result(16#0598#) := x"3FC0";
		result(16#0599#) := x"0000";
		result(16#059A#) := x"BFC0";
		result(16#059B#) := x"0000";
		result(16#0800#) := x"F200";
		result(16#0801#) := x"1F1E";
		result(16#0802#) := x"F239";
		result(16#0803#) := x"6700";
		result(16#0804#) := x"0000";
		result(16#0805#) := x"0B20";
		result(16#0806#) := x"F200";
		result(16#0807#) := x"1E9F";
		result(16#0808#) := x"F239";
		result(16#0809#) := x"6680";
		result(16#080A#) := x"0000";
		result(16#080B#) := x"0B24";
		result(16#080C#) := x"F239";
		result(16#080D#) := x"4601";
		result(16#080E#) := x"0000";
		result(16#080F#) := x"0B30";
		result(16#0810#) := x"F239";
		result(16#0811#) := x"6600";
		result(16#0812#) := x"0000";
		result(16#0813#) := x"0B28";
		result(16#0814#) := x"F239";
		result(16#0815#) := x"4583";
		result(16#0816#) := x"0000";
		result(16#0817#) := x"0B34";
		result(16#0818#) := x"F239";
		result(16#0819#) := x"6580";
		result(16#081A#) := x"0000";
		result(16#081B#) := x"0B2C";
		result(16#081C#) := x"F200";
		result(16#081D#) := x"12A6";
		result(16#081E#) := x"F239";
		result(16#081F#) := x"6680";
		result(16#0820#) := x"0000";
		result(16#0821#) := x"0B38";
		result(16#0822#) := x"F200";
		result(16#0823#) := x"12A1";
		result(16#0824#) := x"F239";
		result(16#0825#) := x"6680";
		result(16#0826#) := x"0000";
		result(16#0827#) := x"0B3C";
		result(16#0828#) := x"F200";
		result(16#0829#) := x"0E25";
		result(16#082A#) := x"F239";
		result(16#082B#) := x"6600";
		result(16#082C#) := x"0000";
		result(16#082D#) := x"0B40";
		result(16#082E#) := x"F200";
		result(16#082F#) := x"A800";
		result(16#0830#) := x"23C0";
		result(16#0831#) := x"0000";
		result(16#0832#) := x"0B44";
		result(16#0833#) := x"F200";
		result(16#0834#) := x"1FA8";
		result(16#0835#) := x"F200";
		result(16#0836#) := x"1FB8";
		result(16#0837#) := x"F239";
		result(16#0838#) := x"6780";
		result(16#0839#) := x"0000";
		result(16#083A#) := x"0B14";
		result(16#083B#) := x"263C";
		result(16#083C#) := x"0000";
		result(16#083D#) := x"0080";
		result(16#083E#) := x"F203";
		result(16#083F#) := x"9000";
		result(16#0840#) := x"7403";
		result(16#0841#) := x"F202";
		result(16#0842#) := x"4180";
		result(16#0843#) := x"7402";
		result(16#0844#) := x"F202";
		result(16#0845#) := x"4200";
		result(16#0846#) := x"F200";
		result(16#0847#) := x"0E27";
		result(16#0848#) := x"F239";
		result(16#0849#) := x"6600";
		result(16#084A#) := x"0000";
		result(16#084B#) := x"0B48";
		result(16#084C#) := x"7401";
		result(16#084D#) := x"F202";
		result(16#084E#) := x"4200";
		result(16#084F#) := x"F200";
		result(16#0850#) := x"0E24";
		result(16#0851#) := x"F239";
		result(16#0852#) := x"6600";
		result(16#0853#) := x"0000";
		result(16#0854#) := x"0B4C";
		result(16#0855#) := x"F200";
		result(16#0856#) := x"5E00";
		result(16#0857#) := x"F239";
		result(16#0858#) := x"6600";
		result(16#0859#) := x"0000";
		result(16#085A#) := x"0B50";
		result(16#085B#) := x"F202";
		result(16#085C#) := x"4191";
		result(16#085D#) := x"F239";
		result(16#085E#) := x"6580";
		result(16#085F#) := x"0000";
		result(16#0860#) := x"0B54";
		result(16#0861#) := x"F202";
		result(16#0862#) := x"4190";
		result(16#0863#) := x"F239";
		result(16#0864#) := x"6580";
		result(16#0865#) := x"0000";
		result(16#0866#) := x"0B58";
		result(16#0867#) := x"F202";
		result(16#0868#) := x"4192";
		result(16#0869#) := x"F239";
		result(16#086A#) := x"6580";
		result(16#086B#) := x"0000";
		result(16#086C#) := x"0B5C";
		result(16#086D#) := x"F202";
		result(16#086E#) := x"4188";
		result(16#086F#) := x"F239";
		result(16#0870#) := x"6580";
		result(16#0871#) := x"0000";
		result(16#0872#) := x"0B60";
		result(16#0873#) := x"F202";
		result(16#0874#) := x"4186";
		result(16#0875#) := x"F239";
		result(16#0876#) := x"6580";
		result(16#0877#) := x"0000";
		result(16#0878#) := x"0B64";
		result(16#0879#) := x"4E72";
		result(16#087A#) := x"2700";
		return result;
	end function;

	signal clk : std_logic := '0';
	signal nReset : std_logic := '0';
	signal data_in : std_logic_vector(15 downto 0);
	signal addr_out : std_logic_vector(31 downto 0);
	signal data_write : std_logic_vector(15 downto 0);
	signal nWr : std_logic;
	signal nUDS : std_logic;
	signal nLDS : std_logic;
	signal busstate : std_logic_vector(1 downto 0);
	signal logical_address : std_logic_vector(31 downto 0);
	signal logical_access : std_logic;
	signal memory : memory_t := initial_memory;
	signal result_write_count : natural range 0 to 2 := 0;
	signal fpu_memory_transfer_count : natural range 0 to 4 := 0;
	signal extended_transfer_count : natural range 0 to 12 := 0;
	signal extended_result_write_count : natural range 0 to 4 := 0;
	signal control_result_write_count : natural range 0 to 6 := 0;
	signal control_memory_transfer_count : natural range 0 to 12 := 0;
	signal control_address_write_count : natural range 0 to 4 := 0;
	signal movem_transfer_count : natural range 0 to 48 := 0;
	signal movem_address_write_count : natural range 0 to 4 := 0;
	signal unary_result_write_count : natural range 0 to 2 := 0;
	signal extraction_result_write_count : natural range 0 to 4 := 0;
	signal integer_result_write_count : natural range 0 to 4 := 0;
	signal scale_result_write_count : natural range 0 to 2 := 0;
	signal remainder_result_write_count : natural range 0 to 4 := 0;
	signal fpsr_result_write_count : natural range 0 to 2 := 0;
	signal binary_result_write_count : natural range 0 to 8 := 0;
	signal single_result_write_count : natural range 0 to 4 := 0;
	signal constant_result_write_count : natural range 0 to 2 := 0;
	signal exponential_result_write_count : natural range 0 to 8 := 0;
	signal logarithm_result_write_count : natural range 0 to 2 := 0;
	signal post_fpu_fetch : std_logic := '0';
begin
	clk <= not clk after CLK_PERIOD / 2;

	dut : entity work.TG68KdotC_MMU
		port map(
			clk => clk,
			nReset => nReset,
			clkena_in => '1',
			data_in => data_in,
			IPL => "111",
			IPL_autovector => '1',
			berr => '0',
			CPU => "11",
			MMU_enable => '0',
			FPU_enable => '1',
			addr_out => addr_out,
			data_write => data_write,
			nWr => nWr,
			nUDS => nUDS,
			nLDS => nLDS,
			busstate => busstate,
			longword => open,
			cache_inhibit => open,
			logical_bus_address => logical_address,
			logical_bus_access => logical_access,
			nResetOut => open,
			FC => open,
			clr_berr => open,
			skipFetch => open,
			regin_out => open,
			CACR_out => open,
			D_CACHE_out => open,
			VBR_out => open
		);

	memory_read : process(all)
		variable word_address : natural;
	begin
		data_in <= x"FFFF";
		if not is_x(addr_out) then
			word_address := to_integer(unsigned(addr_out(13 downto 1)));
			if word_address < MEMORY_WORDS then
				data_in <= memory(word_address);
			end if;
		end if;
	end process;

	memory_write : process(clk)
		variable word_address : natural;
	begin
		if rising_edge(clk) then
			if busstate /= "01" and
					(addr_out = x"00000300" or addr_out = x"00000302") then
				assert logical_access = '1' and logical_address = addr_out
					report "FPU memory cycle lost its logical bus address"
					severity failure;
				fpu_memory_transfer_count <= fpu_memory_transfer_count + 1;
			end if;
			if busstate /= "01" and unsigned(addr_out) >= unsigned'(x"00000400") and
					unsigned(addr_out) <= unsigned'(x"0000040A") then
				extended_transfer_count <= extended_transfer_count + 1;
			end if;
			if busstate /= "01" and
					((unsigned(addr_out) >= unsigned'(x"00000500") and
					unsigned(addr_out) <= unsigned'(x"0000050A")) or
					(unsigned(addr_out) >= unsigned'(x"00000600") and
					unsigned(addr_out) <= unsigned'(x"0000060A"))) then
				control_memory_transfer_count <=
					control_memory_transfer_count + 1;
			end if;
			if busstate /= "01" and
					((unsigned(addr_out) >= unsigned'(x"00000700") and
					unsigned(addr_out) <= unsigned'(x"00000717")) or
					(unsigned(addr_out) >= unsigned'(x"00000800") and
					unsigned(addr_out) <= unsigned'(x"00000817")) or
					(unsigned(addr_out) >= unsigned'(x"00000900") and
					unsigned(addr_out) <= unsigned'(x"0000090B")) or
					(unsigned(addr_out) >= unsigned'(x"00000A00") and
					unsigned(addr_out) <= unsigned'(x"00000A0B"))) then
				movem_transfer_count <= movem_transfer_count + 1;
			end if;
			if busstate = "11" and not is_x(addr_out) then
				word_address := to_integer(unsigned(addr_out(13 downto 1)));
				if nUDS = '0' then
					memory(word_address)(15 downto 8) <= data_write(15 downto 8);
				end if;
				if nLDS = '0' then
					memory(word_address)(7 downto 0) <= data_write(7 downto 0);
				end if;
				if addr_out = x"00000200" or addr_out = x"00000202" then
					result_write_count <= result_write_count + 1;
				end if;
				if addr_out = x"00000204" or addr_out = x"00000206" or
						addr_out = x"00000208" or addr_out = x"0000020A" then
					extended_result_write_count <= extended_result_write_count + 1;
				end if;
				if addr_out = x"0000020C" or addr_out = x"0000020E" then
					control_result_write_count <= control_result_write_count + 1;
				end if;
				if addr_out = x"00000210" or addr_out = x"00000212" or
						addr_out = x"00000214" or addr_out = x"00000216" then
					control_address_write_count <=
						control_address_write_count + 1;
				end if;
				if addr_out = x"00000218" or addr_out = x"0000021A" or
						addr_out = x"0000021C" or addr_out = x"0000021E" then
					movem_address_write_count <= movem_address_write_count + 1;
				end if;
				if addr_out = x"00000B00" or addr_out = x"00000B02" then
					unary_result_write_count <= unary_result_write_count + 1;
				end if;
				if addr_out = x"00000B20" or addr_out = x"00000B22" or
						addr_out = x"00000B24" or addr_out = x"00000B26" then
					extraction_result_write_count <=
						extraction_result_write_count + 1;
				end if;
				if addr_out = x"00000B28" or addr_out = x"00000B2A" or
						addr_out = x"00000B2C" or addr_out = x"00000B2E" then
					integer_result_write_count <= integer_result_write_count + 1;
				end if;
				if addr_out = x"00000B38" or addr_out = x"00000B3A" then
					scale_result_write_count <= scale_result_write_count + 1;
				end if;
				if addr_out = x"00000B3C" or addr_out = x"00000B3E" or
						addr_out = x"00000B40" or addr_out = x"00000B42" then
					remainder_result_write_count <=
						remainder_result_write_count + 1;
				end if;
				if addr_out = x"00000B44" or addr_out = x"00000B46" then
					fpsr_result_write_count <= fpsr_result_write_count + 1;
				end if;
				if addr_out = x"00000B10" or addr_out = x"00000B12" or
						addr_out = x"00000B14" or addr_out = x"00000B16" or
						addr_out = x"00000B18" or addr_out = x"00000B1A" or
						addr_out = x"00000B1C" or addr_out = x"00000B1E" then
					binary_result_write_count <= binary_result_write_count + 1;
				end if;
				if addr_out = x"00000B48" or addr_out = x"00000B4A" or
						addr_out = x"00000B4C" or addr_out = x"00000B4E" then
					single_result_write_count <= single_result_write_count + 1;
				end if;
				if addr_out = x"00000B50" or addr_out = x"00000B52" then
					constant_result_write_count <= constant_result_write_count + 1;
				end if;
				if addr_out = x"00000B54" or addr_out = x"00000B56" or
					addr_out = x"00000B58" or addr_out = x"00000B5A" or
					addr_out = x"00000B5C" or addr_out = x"00000B5E" or
					addr_out = x"00000B60" or addr_out = x"00000B62" then
					exponential_result_write_count <=
						exponential_result_write_count + 1;
				end if;
				if addr_out = x"00000B64" or addr_out = x"00000B66" then
					logarithm_result_write_count <=
						logarithm_result_write_count + 1;
				end if;
			end if;
			if busstate = "00" and addr_out = x"000010F2" then
				post_fpu_fetch <= '1';
			end if;
		end if;
	end process;

	stimulus : process
	begin
		wait for 5 * CLK_PERIOD;
		wait until falling_edge(clk);
		nReset <= '1';
		for cycle in 0 to 3000 loop
			wait until rising_edge(clk);
			exit when result_write_count = 2 and
				extended_result_write_count = 4 and
				control_result_write_count = 2 and
				control_address_write_count = 4 and
				movem_transfer_count = 48 and
				movem_address_write_count = 4 and
				unary_result_write_count = 2 and
				extraction_result_write_count = 4 and
				integer_result_write_count = 4 and
				scale_result_write_count = 2 and
				remainder_result_write_count = 4 and
				fpsr_result_write_count = 2 and
				binary_result_write_count = 8 and
				single_result_write_count = 4 and
				constant_result_write_count = 2 and
				exponential_result_write_count = 8 and
				logarithm_result_write_count = 2 and post_fpu_fetch = '1';
		end loop;
		assert result_write_count = 2 and memory(16#0100#) = x"40A0" and
			memory(16#0101#) = x"0000"
			report "TG68K FPU instruction stream result mismatch: " &
				to_hstring(memory(16#0100#)) & to_hstring(memory(16#0101#))
			severity failure;
		assert post_fpu_fetch = '1'
			report "TG68K did not retire the FPU instruction stream" severity failure;
		assert fpu_memory_transfer_count = 4 and
			memory(16#0180#) = x"40A0" and memory(16#0181#) = x"0000"
			report "TG68K FPU memory transfer sequence mismatch" severity failure;
		assert extended_transfer_count = 12 and
			memory(16#0102#) = x"0000" and memory(16#0103#) = x"0400" and
			memory(16#0104#) = x"40A0" and memory(16#0105#) = x"0000"
			report "TG68K FPU extended predecrement/postincrement mismatch: cycles=" &
				integer'image(extended_transfer_count) & " A1=" &
				to_hstring(memory(16#0102#)) & to_hstring(memory(16#0103#)) &
				" result=" & to_hstring(memory(16#0104#)) &
				to_hstring(memory(16#0105#))
			severity failure;
		assert control_result_write_count = 2 and
			memory(16#0106#) = x"0000" and memory(16#0107#) = x"00B0"
			report "TG68K direct FPU control-register transfer mismatch"
			severity failure;
		assert control_memory_transfer_count = 12 and
			memory(16#0300#) = x"0000" and memory(16#0301#) = x"0030" and
			memory(16#0302#) = x"A5A5" and memory(16#0303#) = x"1234" and
			memory(16#0304#) = x"1122" and memory(16#0305#) = x"3344"
			report "TG68K FPU control-register memory ordering mismatch"
			severity failure;
		assert control_address_write_count = 4 and
			memory(16#0108#) = x"0000" and memory(16#0109#) = x"050C" and
			memory(16#010A#) = x"0000" and memory(16#010B#) = x"060C"
			report "TG68K FPU control-register EA update mismatch"
			severity failure;
		assert movem_transfer_count = 48 and
			memory(16#0400#) = x"4000" and memory(16#0401#) = x"0000" and
			memory(16#0402#) = x"8000" and memory(16#0405#) = x"0007" and
			memory(16#0406#) = x"4001" and memory(16#0407#) = x"0000" and
			memory(16#0408#) = x"9000" and
			memory(16#0500#) = x"4005" and memory(16#0501#) = x"0000" and
			memory(16#0502#) = x"A000" and memory(16#0505#) = x"0005"
			report "TG68K FPU data-register FMOVEM image mismatch: cycles=" &
				integer'image(movem_transfer_count) & " static=" &
				to_hstring(memory(16#0400#)) & to_hstring(memory(16#0401#)) &
				to_hstring(memory(16#0402#)) & to_hstring(memory(16#0405#)) &
				to_hstring(memory(16#0406#)) & to_hstring(memory(16#0407#)) &
				to_hstring(memory(16#0408#)) & " dynamic=" &
				to_hstring(memory(16#0500#)) & to_hstring(memory(16#0501#)) &
				to_hstring(memory(16#0502#)) & to_hstring(memory(16#0505#))
			severity failure;
		assert movem_address_write_count = 4 and
			memory(16#010C#) = x"0000" and memory(16#010D#) = x"0700" and
			memory(16#010E#) = x"0000" and memory(16#010F#) = x"0800"
			report "TG68K FPU data-register FMOVEM EA update mismatch"
			severity failure;
		assert unary_result_write_count = 2 and
			memory(16#0580#) = x"42A0" and memory(16#0581#) = x"0001"
			report "TG68K FPU unary instruction stream result mismatch: " &
				to_hstring(memory(16#0580#)) & to_hstring(memory(16#0581#))
			severity failure;
		assert extraction_result_write_count = 4 and
			memory(16#0590#) = x"0000" and memory(16#0591#) = x"0000" and
			memory(16#0592#) = x"3F80" and memory(16#0593#) = x"0000"
			report "TG68K FPU extraction instruction stream mismatch: " &
				to_hstring(memory(16#0590#)) & to_hstring(memory(16#0591#)) &
				" " & to_hstring(memory(16#0592#)) &
				to_hstring(memory(16#0593#))
			severity failure;
		assert integer_result_write_count = 4 and
			memory(16#0594#) = x"4000" and memory(16#0595#) = x"0000" and
			memory(16#0596#) = x"BF80" and memory(16#0597#) = x"0000"
			report "TG68K FPU integral instruction stream mismatch: " &
				to_hstring(memory(16#0594#)) & to_hstring(memory(16#0595#)) &
				" " & to_hstring(memory(16#0596#)) &
				to_hstring(memory(16#0597#))
			severity failure;
		assert scale_result_write_count = 2 and
			memory(16#059C#) = x"4080" and memory(16#059D#) = x"0000"
			report "TG68K FPU scale instruction stream mismatch: " &
				to_hstring(memory(16#059C#)) & to_hstring(memory(16#059D#))
			severity failure;
		assert remainder_result_write_count = 4 and
			memory(16#059E#) = x"0000" and memory(16#059F#) = x"0000" and
			memory(16#05A0#) = x"0000" and memory(16#05A1#) = x"0000"
			report "TG68K FPU remainder instruction stream mismatch: " &
				to_hstring(memory(16#059E#)) & to_hstring(memory(16#059F#)) &
				" " & to_hstring(memory(16#05A0#)) &
				to_hstring(memory(16#05A1#))
			severity failure;
		assert fpsr_result_write_count = 2 and memory(16#05A2#) = x"4582"
			report "TG68K FPU remainder quotient byte mismatch: " &
				to_hstring(memory(16#05A2#)) & to_hstring(memory(16#05A3#))
			severity failure;
		assert binary_result_write_count = 8 and
			memory(16#0588#) = x"4320" and memory(16#0589#) = x"0001" and
			memory(16#058A#) = x"0000" and memory(16#058B#) = x"0000" and
			memory(16#058C#) = x"46C8" and memory(16#058D#) = x"0001" and
			memory(16#058E#) = x"3F80" and memory(16#058F#) = x"0000"
			report "TG68K FPU arithmetic instruction stream mismatch: " &
				to_hstring(memory(16#0588#)) & to_hstring(memory(16#0589#)) &
				" " & to_hstring(memory(16#058A#)) &
				to_hstring(memory(16#058B#)) & " " &
				to_hstring(memory(16#058C#)) & to_hstring(memory(16#058D#)) &
				" " & to_hstring(memory(16#058E#)) &
				to_hstring(memory(16#058F#))
			severity failure;
		assert single_result_write_count = 4 and
			memory(16#05A4#) = x"40C0" and memory(16#05A5#) = x"0000" and
			memory(16#05A6#) = x"3EAA" and memory(16#05A7#) = x"AAAB"
			report "TG68K FSGLMUL/FSGLDIV instruction stream mismatch: " &
				to_hstring(memory(16#05A4#)) &
				to_hstring(memory(16#05A5#)) & " " &
				to_hstring(memory(16#05A6#)) &
				to_hstring(memory(16#05A7#))
			severity failure;
		assert constant_result_write_count = 2 and
			memory(16#05A8#) = x"4049" and memory(16#05A9#) = x"0FDB"
			report "TG68K FMOVECR instruction stream mismatch: " &
				to_hstring(memory(16#05A8#)) &
				to_hstring(memory(16#05A9#))
			severity failure;
		assert exponential_result_write_count = 8 and
			memory(16#05AA#) = x"4000" and memory(16#05AB#) = x"0000" and
			memory(16#05AC#) = x"402D" and memory(16#05AD#) = x"F854" and
			memory(16#05AE#) = x"4120" and memory(16#05AF#) = x"0000" and
			memory(16#05B0#) = x"3FDB" and memory(16#05B1#) = x"F0A9"
			report "TG68K exponential instruction stream mismatch: " &
				to_hstring(memory(16#05AA#)) &
				to_hstring(memory(16#05AB#)) & " " &
				to_hstring(memory(16#05AC#)) &
				to_hstring(memory(16#05AD#)) & " " &
				to_hstring(memory(16#05AE#)) &
				to_hstring(memory(16#05AF#)) & " " &
				to_hstring(memory(16#05B0#)) &
				to_hstring(memory(16#05B1#))
			severity failure;
		assert logarithm_result_write_count = 2 and
			memory(16#05B2#) = x"3F31" and memory(16#05B3#) = x"7218"
			report "TG68K FLOGNP1 instruction stream mismatch: " &
				to_hstring(memory(16#05B2#)) &
				to_hstring(memory(16#05B3#))
			severity failure;
		report "PASS: TG68K instruction-level FPU moves, constants, exponentials, logarithms, extraction, integral rounding, scaling, remainder, arithmetic, single arithmetic, FMOVEM, and control state"
			severity note;
		stop;
	end process;
end architecture;
