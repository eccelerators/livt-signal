library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;
use work.livt_lang_package.all;

entity livt_signal_filter_firq15pipelineprimitive is
    port (
        ctor_lvt_context_in : in t_icontext_in;
        ctor_coefficients : in integer_1d;
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

architecture rtl of livt_signal_filter_firq15pipelineprimitive is
    function ceil_log2(value : positive) return natural is
        variable remaining : natural := value - 1;
        variable result : natural := 0;
    begin
        while remaining > 0 loop
            remaining := remaining / 2;
            result := result + 1;
        end loop;
        return result;
    end;

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

    constant TAPS : positive := ctor_coefficients'length;
    constant TREE_LEVELS : natural := ceil_log2(TAPS);
    constant LATENCY : positive := TREE_LEVELS + 2;

    type sample_array_t is array (natural range <>) of signed(15 downto 0);
    type sum_matrix_t is array (natural range <>, natural range <>) of signed(63 downto 0);
    signal history : sample_array_t(0 to TAPS - 1);
    signal sums : sum_matrix_t(0 to TREE_LEVELS, 0 to TAPS - 1);
    signal valid_pipe, first_pipe, last_pipe : std_logic_vector(0 to LATENCY - 1) := (others => '0');
    signal history_count : natural range 0 to TAPS - 1 := 0;
    signal result_sample : std_logic_vector(15 downto 0) := (others => '0');
    signal advance : boolean;
begin
    advance <= valid_pipe(LATENCY - 1) = '0' or ctor_outputready;
    ctor_inputready <= ctor_lvt_context_in.rst = '0' and advance;
    ctor_outputvalid <= ctor_lvt_context_in.rst = '0' and valid_pipe(LATENCY - 1) = '1';
    ctor_outputsample <= result_sample;
    ctor_outputfirst <= first_pipe(LATENCY - 1) = '1';
    ctor_outputlast <= last_pipe(LATENCY - 1) = '1';

    process (ctor_lvt_context_in.clk)
        variable sample_value : signed(15 downto 0);
        variable nodes, next_nodes : natural;
    begin
        if rising_edge(ctor_lvt_context_in.clk) then
            if ctor_lvt_context_in.rst = '1' then
                valid_pipe <= (others => '0');
                first_pipe <= (others => '0');
                last_pipe <= (others => '0');
                history_count <= 0;
            else
                assert to_integer(ctor_coefficientbits) >= 2 and
                    to_integer(ctor_coefficientbits) <= 31
                    report "FIR coefficient width must be in 2..31" severity failure;
                assert to_integer(ctor_coefficientfractionbits) >= 0 and
                    to_integer(ctor_coefficientfractionbits) < to_integer(ctor_coefficientbits)
                    report "FIR coefficient fractional bits are out of range" severity failure;
                for tap in 0 to TAPS - 1 loop
                    assert resize(ctor_coefficients(tap), 64) >=
                            -shift_left(to_signed(1, 64), to_integer(ctor_coefficientbits) - 1) and
                        resize(ctor_coefficients(tap), 64) <
                            shift_left(to_signed(1, 64), to_integer(ctor_coefficientbits) - 1)
                        report "FIR coefficient does not fit COEFFICIENT_BITS" severity failure;
                end loop;

                if advance then
                for stage in 1 to LATENCY - 1 loop
                    valid_pipe(stage) <= valid_pipe(stage - 1);
                    first_pipe(stage) <= first_pipe(stage - 1);
                    last_pipe(stage) <= last_pipe(stage - 1);
                end loop;
                if ctor_inputvalid then
                    valid_pipe(0) <= '1';
                else
                    valid_pipe(0) <= '0';
                end if;
                if ctor_inputvalid and ctor_inputfirst then first_pipe(0) <= '1'; else first_pipe(0) <= '0'; end if;
                if ctor_inputvalid and ctor_inputlast then last_pipe(0) <= '1'; else last_pipe(0) <= '0'; end if;

                for tap in 0 to TAPS - 1 loop
                    sample_value := (others => '0');
                    if tap = 0 then
                        sample_value := signed(ctor_inputsample);
                    elsif tap <= history_count then
                        sample_value := history(tap - 1);
                    end if;
                    sums(0, tap) <= resize(sample_value * ctor_coefficients(tap), 64);
                end loop;

                nodes := TAPS;
                for level in 0 to TREE_LEVELS - 1 loop
                    next_nodes := (nodes + 1) / 2;
                    for node in 0 to TAPS - 1 loop
                        if node < next_nodes then
                            if node * 2 + 1 < nodes then
                                sums(level + 1, node) <= sums(level, node * 2) + sums(level, node * 2 + 1);
                            else
                                sums(level + 1, node) <= sums(level, node * 2);
                            end if;
                        else
                            sums(level + 1, node) <= (others => '0');
                        end if;
                    end loop;
                    nodes := next_nodes;
                end loop;

                if valid_pipe(TREE_LEVELS) = '1' then
                    result_sample <= quantize_q15(sums(TREE_LEVELS, 0),
                        to_integer(ctor_coefficientfractionbits));
                end if;

                if ctor_inputvalid then
                    if TAPS > 1 then
                        for tap in TAPS - 1 downto 1 loop
                            history(tap) <= history(tap - 1);
                        end loop;
                    end if;
                    history(0) <= signed(ctor_inputsample);
                    if history_count < TAPS - 1 then
                        history_count <= history_count + 1;
                    end if;
                end if;
                end if;
            end if;
        end if;
    end process;
end;
