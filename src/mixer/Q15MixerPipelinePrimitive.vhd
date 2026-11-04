library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;

entity livt_signal_mixer_q15mixerpipelineprimitive is
    port (
        ctor_lvt_context_in : in t_icontext_in;
        ctor_realinput : in boolean;
        ctor_samplevalid : in boolean;
        ctor_sampleready : out boolean;
        ctor_samplereal : in std_logic_vector(15 downto 0);
        ctor_sampleimag : in std_logic_vector(15 downto 0);
        ctor_samplefirst : in boolean;
        ctor_samplelast : in boolean;
        ctor_oscillatorvalid : in boolean;
        ctor_oscillatorready : out boolean;
        ctor_oscillatorreal : in std_logic_vector(15 downto 0);
        ctor_oscillatorimag : in std_logic_vector(15 downto 0);
        ctor_outputvalid : out boolean;
        ctor_outputready : in boolean;
        ctor_outputreal : out std_logic_vector(15 downto 0);
        ctor_outputimag : out std_logic_vector(15 downto 0);
        ctor_outputfirst : out boolean;
        ctor_outputlast : out boolean
    );
end;

architecture rtl of livt_signal_mixer_q15mixerpipelineprimitive is
    subtype wide_t is signed(32 downto 0);
    signal result_valid : boolean := false;
    signal result_real, result_imag : std_logic_vector(15 downto 0) := (others => '0');
    signal result_first, result_last : boolean := false;
    signal advance : boolean;

    function quantize_q15(value : wide_t) return std_logic_vector is
        variable magnitude, rounded : unsigned(32 downto 0);
        variable negative : boolean;
    begin
        negative := value(value'high) = '1';
        if negative then magnitude := unsigned(-value); else magnitude := unsigned(value); end if;
        rounded := shift_right(magnitude, 15);
        if magnitude(14) = '1' and
            (magnitude(13 downto 0) /= to_unsigned(0, 14) or rounded(0) = '1') then
            rounded := rounded + 1;
        end if;
        if negative then
            if rounded > to_unsigned(32768, rounded'length) then
                return std_logic_vector(to_signed(-32768, 16));
            end if;
            return std_logic_vector(-signed(resize(rounded, 16)));
        end if;
        if rounded > to_unsigned(32767, rounded'length) then
            return std_logic_vector(to_signed(32767, 16));
        end if;
        return std_logic_vector(resize(rounded, 16));
    end function;
begin
    advance <= not result_valid or ctor_outputready;
    ctor_sampleready <= ctor_lvt_context_in.rst = '0' and advance and ctor_oscillatorvalid;
    ctor_oscillatorready <= ctor_lvt_context_in.rst = '0' and advance and ctor_samplevalid;
    ctor_outputvalid <= ctor_lvt_context_in.rst = '0' and result_valid;
    ctor_outputreal <= result_real;
    ctor_outputimag <= result_imag;
    ctor_outputfirst <= result_first;
    ctor_outputlast <= result_last;

    process (ctor_lvt_context_in.clk)
        variable ar, ai, br, bi : signed(15 downto 0);
        variable ac, bd, ad, bc : signed(31 downto 0);
    begin
        if rising_edge(ctor_lvt_context_in.clk) then
            if ctor_lvt_context_in.rst = '1' then
                result_valid <= false;
                result_first <= false;
                result_last <= false;
            elsif advance then
                result_valid <= ctor_samplevalid and ctor_oscillatorvalid;
                if ctor_samplevalid and ctor_oscillatorvalid then
                    ar := signed(ctor_samplereal);
                    ai := signed(ctor_sampleimag);
                    br := signed(ctor_oscillatorreal);
                    bi := signed(ctor_oscillatorimag);
                    ac := ar * br;
                    ad := ar * bi;
                    if ctor_realinput then
                        result_real <= quantize_q15(resize(ac, wide_t'length));
                        result_imag <= quantize_q15(resize(ad, wide_t'length));
                    else
                        bd := ai * bi;
                        bc := ai * br;
                        result_real <= quantize_q15(resize(ac, wide_t'length) - resize(bd, wide_t'length));
                        result_imag <= quantize_q15(resize(ad, wide_t'length) + resize(bc, wide_t'length));
                    end if;
                    result_first <= ctor_samplefirst;
                    result_last <= ctor_samplelast;
                else
                    result_first <= false;
                    result_last <= false;
                end if;
            end if;
        end if;
    end process;
end;
