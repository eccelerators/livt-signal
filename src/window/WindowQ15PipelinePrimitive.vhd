library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;
use work.livt_lang_package.all;

entity livt_signal_window_windowq15pipelineprimitive is
    port (
        ctor_lvt_context_in : in t_icontext_in;
        ctor_coefficients : in integer_1d;
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

architecture rtl of livt_signal_window_windowq15pipelineprimitive is
    function quantize_q15(value : signed(63 downto 0)) return std_logic_vector is
        variable magnitude : unsigned(63 downto 0);
        variable rounded : unsigned(63 downto 0);
        variable sticky : boolean := false;
        variable negative : boolean;
        variable raw : integer;
    begin
        negative := value(63) = '1';
        if negative then magnitude := unsigned(-value);
        else magnitude := unsigned(value); end if;
        rounded := shift_right(magnitude, 15);
        if magnitude(14) = '1' then
            for bit_index in 0 to 13 loop
                if magnitude(bit_index) = '1' then sticky := true; end if;
            end loop;
            if sticky or rounded(0) = '1' then rounded := rounded + 1; end if;
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

    constant SAMPLES : positive := ctor_coefficients'length;
    signal position : natural range 0 to SAMPLES - 1 := 0;
    signal stage_sample : signed(15 downto 0) := (others => '0');
    signal stage_coefficient : integer range -32768 to 32767 := 0;
    signal stage_valid, stage_first, stage_last : std_logic := '0';
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
        variable selected_position : natural range 0 to SAMPLES - 1;
        variable product : signed(63 downto 0);
    begin
        if rising_edge(ctor_lvt_context_in.clk) then
            if ctor_lvt_context_in.rst = '1' then
                position <= 0;
                stage_valid <= '0';
                stage_first <= '0';
                stage_last <= '0';
                result_valid <= '0';
                result_first <= '0';
                result_last <= '0';
            else
                for index in ctor_coefficients'range loop
                    assert to_integer(ctor_coefficients(index)) >= -32768 and
                        to_integer(ctor_coefficients(index)) <= 32767
                        report "window coefficient must fit signed Q1.15" severity failure;
                end loop;

                if advance then
                    result_valid <= stage_valid;
                    result_first <= stage_first;
                    result_last <= stage_last;
                    if stage_valid = '1' then
                        product := resize(stage_sample * stage_coefficient, 64);
                        result_sample <= quantize_q15(product);
                    end if;

                    if ctor_inputvalid then
                        if ctor_inputfirst then selected_position := 0;
                        else selected_position := position; end if;
                        stage_sample <= signed(ctor_inputsample);
                        stage_coefficient <= to_integer(ctor_coefficients(selected_position));
                        stage_valid <= '1';
                        if ctor_inputfirst then stage_first <= '1';
                        else stage_first <= '0'; end if;
                        if ctor_inputlast then stage_last <= '1';
                        else stage_last <= '0'; end if;

                        if ctor_inputlast or selected_position = SAMPLES - 1 then
                            position <= 0;
                        else
                            position <= selected_position + 1;
                        end if;
                    else
                        stage_valid <= '0';
                        stage_first <= '0';
                        stage_last <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
end;
