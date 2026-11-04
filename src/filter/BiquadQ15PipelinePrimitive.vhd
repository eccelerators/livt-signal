library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;
use work.livt_lang_package.all;

entity livt_signal_filter_biquadq15pipelineprimitive is
    port (
        ctor_lvt_context_in : in t_icontext_in;
        ctor_numerator : in integer_1d;
        ctor_denominator : in integer_1d;
        ctor_coefficientbits : in signed(31 downto 0);
        ctor_coefficientfractionbits : in signed(31 downto 0);
        ctor_inputvalid : in boolean;
        ctor_inputready : out boolean;
        ctor_inputsample : in std_logic_vector(15 downto 0);
        ctor_inputfirst : in boolean;
        ctor_inputlast : in boolean;
        ctor_outputvalid : out boolean;
        ctor_outputready : in boolean;
        ctor_outputsample : out std_logic_vector(15 downto 0);
        ctor_outputfirst : out boolean;
        ctor_outputlast : out boolean
    );
end;

architecture rtl of livt_signal_filter_biquadq15pipelineprimitive is
    function quantize_q15(value : signed(63 downto 0); fraction_bits : natural)
        return std_logic_vector is
        variable magnitude : unsigned(63 downto 0);
        variable rounded : unsigned(63 downto 0);
        variable sticky : boolean := false;
        variable negative : boolean;
        variable raw : integer;
    begin
        negative := value(63) = '1';
        if negative then
            magnitude := unsigned(-value);
        else
            magnitude := unsigned(value);
        end if;

        rounded := shift_right(magnitude, fraction_bits);
        if fraction_bits > 0 and magnitude(fraction_bits - 1) = '1' then
            if fraction_bits > 1 then
                for bit_index in 0 to fraction_bits - 2 loop
                    if magnitude(bit_index) = '1' then
                        sticky := true;
                    end if;
                end loop;
            end if;
            if sticky or rounded(0) = '1' then
                rounded := rounded + 1;
            end if;
        end if;

        if negative then
            if rounded > to_unsigned(32768, 64) then
                return std_logic_vector(to_signed(-32768, 16));
            end if;
            raw := to_integer(rounded(15 downto 0));
            return std_logic_vector(to_signed(-raw, 16));
        end if;

        if rounded > to_unsigned(32767, 64) then
            return std_logic_vector(to_signed(32767, 16));
        end if;
        return std_logic_vector(to_signed(to_integer(rounded(14 downto 0)), 16));
    end;

    signal input_history_1, input_history_2 : signed(15 downto 0) := (others => '0');
    signal output_history_1, output_history_2 : signed(15 downto 0) := (others => '0');
    signal result_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal result_valid, result_first, result_last : std_logic := '0';
    signal advance : boolean;
begin
    advance <= result_valid = '0' or ctor_outputready;
    ctor_inputready <= ctor_lvt_context_in.rst = '0' and advance;
    ctor_outputvalid <= ctor_lvt_context_in.rst = '0' and result_valid = '1';
    ctor_outputsample <= result_sample;
    ctor_outputfirst <= result_first = '1';
    ctor_outputlast <= result_last = '1';

    process (ctor_lvt_context_in.clk)
        variable accumulator : signed(63 downto 0);
        variable product_0, product_1, product_2 : signed(63 downto 0);
        variable product_3, product_4 : signed(63 downto 0);
        variable sum_01, sum_23 : signed(63 downto 0);
        variable next_output : signed(15 downto 0);
        variable scale, a1, a2 : signed(63 downto 0);
    begin
        if rising_edge(ctor_lvt_context_in.clk) then
            if ctor_lvt_context_in.rst = '1' then
                input_history_1 <= (others => '0');
                input_history_2 <= (others => '0');
                output_history_1 <= (others => '0');
                output_history_2 <= (others => '0');
                result_valid <= '0';
                result_first <= '0';
                result_last <= '0';
            else
                assert ctor_numerator'length = 3
                    report "biquad numerator must contain b0, b1, and b2" severity failure;
                assert ctor_denominator'length = 2
                    report "biquad denominator must contain a1 and a2" severity failure;
                assert to_integer(ctor_coefficientbits) >= 2 and
                    to_integer(ctor_coefficientbits) <= 31
                    report "biquad coefficient width must be in 2..31" severity failure;
                assert to_integer(ctor_coefficientfractionbits) >= 0 and
                    to_integer(ctor_coefficientfractionbits) < to_integer(ctor_coefficientbits)
                    report "biquad coefficient fractional bits are out of range" severity failure;

                for index in ctor_numerator'range loop
                    assert resize(ctor_numerator(index), 64) >=
                            -shift_left(to_signed(1, 64), to_integer(ctor_coefficientbits) - 1) and
                        resize(ctor_numerator(index), 64) <
                            shift_left(to_signed(1, 64), to_integer(ctor_coefficientbits) - 1)
                        report "biquad numerator coefficient does not fit COEFFICIENT_BITS" severity failure;
                end loop;
                for index in ctor_denominator'range loop
                    assert resize(ctor_denominator(index), 64) >=
                            -shift_left(to_signed(1, 64), to_integer(ctor_coefficientbits) - 1) and
                        resize(ctor_denominator(index), 64) <
                            shift_left(to_signed(1, 64), to_integer(ctor_coefficientbits) - 1)
                        report "biquad denominator coefficient does not fit COEFFICIENT_BITS" severity failure;
                end loop;

                scale := shift_left(to_signed(1, 64),
                    to_integer(ctor_coefficientfractionbits));
                a1 := resize(ctor_denominator(0), 64);
                a2 := resize(ctor_denominator(1), 64);
                assert scale + a1 + a2 > to_signed(0, 64) and
                    scale - a1 + a2 > to_signed(0, 64) and
                    scale - a2 > to_signed(0, 64)
                    report "quantized biquad denominator is not strictly stable" severity failure;

                if advance then
                    if ctor_inputvalid then
                        product_0 := resize(signed(ctor_inputsample) * ctor_numerator(0), 64);
                        product_1 := resize(input_history_1 * ctor_numerator(1), 64);
                        product_2 := resize(input_history_2 * ctor_numerator(2), 64);
                        product_3 := resize(output_history_1 * ctor_denominator(0), 64);
                        product_4 := resize(output_history_2 * ctor_denominator(1), 64);
                        sum_01 := product_0 + product_1;
                        sum_23 := product_2 - product_3;
                        accumulator := sum_01 + sum_23 - product_4;
                        next_output := signed(quantize_q15(accumulator,
                            to_integer(ctor_coefficientfractionbits)));

                        result_sample <= std_logic_vector(next_output);
                        result_valid <= '1';
                        if ctor_inputfirst then result_first <= '1';
                        else result_first <= '0'; end if;
                        if ctor_inputlast then result_last <= '1';
                        else result_last <= '0'; end if;

                        input_history_2 <= input_history_1;
                        input_history_1 <= signed(ctor_inputsample);
                        output_history_2 <= output_history_1;
                        output_history_1 <= next_output;
                    else
                        result_valid <= '0';
                        result_first <= '0';
                        result_last <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
end;
