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

package TG68K_FPU_Pack is
	constant FPU_COPROCESSOR_ID : std_logic_vector(2 downto 0) := "001";

	subtype fpu_extended_t is std_logic_vector(79 downto 0);
	subtype fpu_significand_grs_t is unsigned(66 downto 0);
	type fpu_register_array_t is array (0 to 7) of fpu_extended_t;
	type fpu_control_register_t is (FPU_REG_FPCR, FPU_REG_FPSR,
		FPU_REG_FPIAR);
	type fpu_rounding_precision_t is (FPU_PRECISION_EXTENDED,
		FPU_PRECISION_SINGLE, FPU_PRECISION_DOUBLE,
		FPU_PRECISION_RESERVED);
	type fpu_rounding_mode_t is (FPU_ROUND_NEAREST,
		FPU_ROUND_ZERO, FPU_ROUND_MINUS_INFINITY,
		FPU_ROUND_PLUS_INFINITY);
	type fpu_exponential_base_t is (FPU_EXP_BASE_TWO, FPU_EXP_BASE_E,
		FPU_EXP_BASE_TEN);
	type fpu_data_class_t is (FPU_CLASS_ZERO, FPU_CLASS_NORMAL,
		FPU_CLASS_INFINITY, FPU_CLASS_QUIET_NAN, FPU_CLASS_SIGNALING_NAN);
	type fpu_round_input_t is record
		data_class : fpu_data_class_t;
		sign : std_logic;
		exponent : signed(16 downto 0);
		significand : fpu_significand_grs_t;
		special : fpu_extended_t;
	end record;
	type fpu_exception_t is (FPU_EXCEPTION_NONE, FPU_EXCEPTION_BSUN,
		FPU_EXCEPTION_SNAN, FPU_EXCEPTION_OPERR, FPU_EXCEPTION_OVFL,
		FPU_EXCEPTION_UNFL, FPU_EXCEPTION_DZ, FPU_EXCEPTION_INEX2,
		FPU_EXCEPTION_INEX1);
	type fpu_move_direction_t is (FPU_MOVE_REGISTER_TO_REGISTER,
		FPU_MOVE_EXTERNAL_TO_REGISTER, FPU_MOVE_REGISTER_TO_EXTERNAL);
	type fpu_operand_format_t is (FPU_FORMAT_LONG_INTEGER,
		FPU_FORMAT_SINGLE, FPU_FORMAT_EXTENDED, FPU_FORMAT_PACKED,
		FPU_FORMAT_WORD_INTEGER, FPU_FORMAT_DOUBLE,
		FPU_FORMAT_BYTE_INTEGER, FPU_FORMAT_DYNAMIC_PACKED);
	type fpu_instruction_family_t is (FPU_FAMILY_NONE,
		FPU_FAMILY_REGISTER_OPERATION, FPU_FAMILY_EXTERNAL_OPERATION,
		FPU_FAMILY_MOVE_CONSTANT, FPU_FAMILY_MOVE_TO_EXTERNAL,
		FPU_FAMILY_MOVE_TO_CONTROL, FPU_FAMILY_MOVE_FROM_CONTROL,
		FPU_FAMILY_MOVEM_TO_FP, FPU_FAMILY_MOVEM_FROM_FP,
		FPU_FAMILY_SCC, FPU_FAMILY_DBCC, FPU_FAMILY_TRAPCC,
		FPU_FAMILY_BCC_WORD, FPU_FAMILY_BCC_LONG,
		FPU_FAMILY_SAVE, FPU_FAMILY_RESTORE);
	type fpu_operation_t is (FPU_OP_UNDEFINED, FPU_OP_RESERVED_ALIAS,
		FPU_OP_MOVE, FPU_OP_INT, FPU_OP_SINH, FPU_OP_INTRZ,
		FPU_OP_SQRT, FPU_OP_LOGNP1, FPU_OP_ETOXM1, FPU_OP_TANH,
		FPU_OP_ATAN, FPU_OP_ASIN, FPU_OP_ATANH, FPU_OP_SIN,
		FPU_OP_TAN, FPU_OP_ETOX, FPU_OP_TWOTOX, FPU_OP_TENTOX,
		FPU_OP_LOGN, FPU_OP_LOG10, FPU_OP_LOG2, FPU_OP_ABS,
		FPU_OP_COSH, FPU_OP_NEG, FPU_OP_ACOS, FPU_OP_COS,
		FPU_OP_GETEXP, FPU_OP_GETMAN, FPU_OP_DIV, FPU_OP_MOD,
		FPU_OP_ADD, FPU_OP_MUL, FPU_OP_SGLDIV, FPU_OP_REM,
		FPU_OP_SCALE, FPU_OP_SGLMUL, FPU_OP_SUB, FPU_OP_SINCOS,
		FPU_OP_CMP, FPU_OP_TST);

	constant FPU_RESET_NAN : fpu_extended_t := x"7FFFFFFFFFFFFFFFFFFF";
	constant FPU_EXTENDED_EXPONENT_BIAS : natural := 16383;
	constant FPU_EXTENDED_EXPONENT_MAX : natural := 32767;
	constant FPU_FPCR_IMPLEMENTED_MASK : std_logic_vector(31 downto 0) :=
		x"0000FFF0";
	constant FPU_FPCR_PRECISION_HIGH : natural := 7;
	constant FPU_FPCR_PRECISION_LOW : natural := 6;
	constant FPU_FPCR_ROUNDING_HIGH : natural := 5;
	constant FPU_FPCR_ROUNDING_LOW : natural := 4;

	constant FPU_FPSR_NEGATIVE_BIT : natural := 31;
	constant FPU_FPSR_ZERO_BIT : natural := 30;
	constant FPU_FPSR_INFINITY_BIT : natural := 29;
	constant FPU_FPSR_NAN_BIT : natural := 28;
	constant FPU_FPSR_QUOTIENT_SIGN_BIT : natural := 23;
	constant FPU_FPSR_BSUN_BIT : natural := 15;
	constant FPU_FPSR_SNAN_BIT : natural := 14;
	constant FPU_FPSR_OPERR_BIT : natural := 13;
	constant FPU_FPSR_OVFL_BIT : natural := 12;
	constant FPU_FPSR_UNFL_BIT : natural := 11;
	constant FPU_FPSR_DZ_BIT : natural := 10;
	constant FPU_FPSR_INEX2_BIT : natural := 9;
	constant FPU_FPSR_INEX1_BIT : natural := 8;
	constant FPU_FPSR_AEXC_IOP_BIT : natural := 7;
	constant FPU_FPSR_AEXC_OVFL_BIT : natural := 6;
	constant FPU_FPSR_AEXC_UNFL_BIT : natural := 5;
	constant FPU_FPSR_AEXC_DZ_BIT : natural := 4;
	constant FPU_FPSR_AEXC_INEX_BIT : natural := 3;

	function fpu_decode_format(
		value : std_logic_vector(2 downto 0)) return fpu_operand_format_t;
	function fpu_decode_operation(
		value : std_logic_vector(6 downto 0)) return fpu_operation_t;
	function fpu_operation_encoding_valid(
		value : std_logic_vector(6 downto 0)) return boolean;
	function fpu_unbiased_exponent(value : fpu_extended_t) return integer;
	function fpu_classify(value : fpu_extended_t) return fpu_data_class_t;
	function fpu_condition_codes(
		value : fpu_extended_t) return std_logic_vector;
end package;

package body TG68K_FPU_Pack is
	function fpu_decode_format(
		value : std_logic_vector(2 downto 0)) return fpu_operand_format_t is
	begin
		case value is
			when "000" => return FPU_FORMAT_LONG_INTEGER;
			when "001" => return FPU_FORMAT_SINGLE;
			when "010" => return FPU_FORMAT_EXTENDED;
			when "011" => return FPU_FORMAT_PACKED;
			when "100" => return FPU_FORMAT_WORD_INTEGER;
			when "101" => return FPU_FORMAT_DOUBLE;
			when "110" => return FPU_FORMAT_BYTE_INTEGER;
			when others => return FPU_FORMAT_DYNAMIC_PACKED;
		end case;
	end function;

	function fpu_decode_operation(
		value : std_logic_vector(6 downto 0)) return fpu_operation_t is
	begin
		case value is
			when "0000000" => return FPU_OP_MOVE;
			when "0000001" => return FPU_OP_INT;
			when "0000010" => return FPU_OP_SINH;
			when "0000011" => return FPU_OP_INTRZ;
			when "0000100" => return FPU_OP_SQRT;
			when "0000110" => return FPU_OP_LOGNP1;
			when "0001000" => return FPU_OP_ETOXM1;
			when "0001001" => return FPU_OP_TANH;
			when "0001010" => return FPU_OP_ATAN;
			when "0001100" => return FPU_OP_ASIN;
			when "0001101" => return FPU_OP_ATANH;
			when "0001110" => return FPU_OP_SIN;
			when "0001111" => return FPU_OP_TAN;
			when "0010000" => return FPU_OP_ETOX;
			when "0010001" => return FPU_OP_TWOTOX;
			when "0010010" => return FPU_OP_TENTOX;
			when "0010100" => return FPU_OP_LOGN;
			when "0010101" => return FPU_OP_LOG10;
			when "0010110" => return FPU_OP_LOG2;
			when "0011000" => return FPU_OP_ABS;
			when "0011001" => return FPU_OP_COSH;
			when "0011010" => return FPU_OP_NEG;
			when "0011100" => return FPU_OP_ACOS;
			when "0011101" => return FPU_OP_COS;
			when "0011110" => return FPU_OP_GETEXP;
			when "0011111" => return FPU_OP_GETMAN;
			when "0100000" => return FPU_OP_DIV;
			when "0100001" => return FPU_OP_MOD;
			when "0100010" => return FPU_OP_ADD;
			when "0100011" => return FPU_OP_MUL;
			when "0100100" => return FPU_OP_SGLDIV;
			when "0100101" => return FPU_OP_REM;
			when "0100110" => return FPU_OP_SCALE;
			when "0100111" => return FPU_OP_SGLMUL;
			when "0101000" => return FPU_OP_SUB;
			when "0110000" | "0110001" | "0110010" | "0110011" |
					"0110100" | "0110101" | "0110110" | "0110111" =>
				return FPU_OP_SINCOS;
			when "0111000" => return FPU_OP_CMP;
			when "0111010" => return FPU_OP_TST;
			when "0000101" | "0000111" | "0001011" | "0010011" |
					"0010111" | "0011011" | "0101001" | "0101010" |
					"0101011" | "0101100" | "0101101" | "0101110" |
					"0101111" | "0111001" | "0111011" | "0111100" |
					"0111101" | "0111110" | "0111111" =>
				return FPU_OP_RESERVED_ALIAS;
			when others => return FPU_OP_UNDEFINED;
		end case;
	end function;

	function fpu_operation_encoding_valid(
		value : std_logic_vector(6 downto 0)) return boolean is
	begin
		return value(6) = '0';
	end function;

	function fpu_unbiased_exponent(value : fpu_extended_t) return integer is
	begin
		-- Extended precision retains -16383 at exponent zero because its
		-- integer bit is explicit and may still identify a normalized value.
		return to_integer(unsigned(value(78 downto 64))) -
			FPU_EXTENDED_EXPONENT_BIAS;
	end function;

	function fpu_classify(value : fpu_extended_t) return fpu_data_class_t is
	begin
		if value(78 downto 64) = "111111111111111" then
			if value(62 downto 0) = x"000000000000000" & "000" then
				return FPU_CLASS_INFINITY;
			elsif value(62) = '1' then
				return FPU_CLASS_QUIET_NAN;
			else
				return FPU_CLASS_SIGNALING_NAN;
			end if;
		elsif value(78 downto 64) = "000000000000000" and
				value(63 downto 0) = x"0000000000000000" then
			return FPU_CLASS_ZERO;
		else
			return FPU_CLASS_NORMAL;
		end if;
	end function;

	function fpu_condition_codes(
		value : fpu_extended_t) return std_logic_vector is
		variable condition_codes : std_logic_vector(3 downto 0) :=
			(others => '0');
		variable data_class : fpu_data_class_t;
	begin
		data_class := fpu_classify(value);
		condition_codes(3) := value(79);
		case data_class is
			when FPU_CLASS_ZERO => condition_codes(2) := '1';
			when FPU_CLASS_INFINITY => condition_codes(1) := '1';
			when FPU_CLASS_QUIET_NAN | FPU_CLASS_SIGNALING_NAN =>
				condition_codes(0) := '1';
			when others => null;
		end case;
		return condition_codes;
	end function;
end package body;
