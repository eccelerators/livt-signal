library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_icontext_package.all;
use work.livt_lang_package.all;

entity livt_signal_ratechange_cicdecimatorq15pipelineprimitive is
    port (
        ctor_lvt_context_in : in t_icontext_in;
        ctor_rateshape : in std_logic_vector;
        ctor_stageshape : in std_logic_vector;
        ctor_delayshape : in std_logic_vector;
        ctor_widthshape : in std_logic_vector;
        ctor_outputshift : in signed(31 downto 0);
        ctor_inputvalid : in boolean;
        ctor_inputready : out boolean;
        ctor_inputsample : in std_logic_vector(15 downto 0);
        ctor_inputfirst : in boolean;
        ctor_inputlast : in boolean;
        ctor_outputvalid : out boolean;
        ctor_outputready : in boolean;
        ctor_outputsample : out std_logic_vector(15 downto 0);
        ctor_outputfirst : out boolean;
        ctor_outputlast : out boolean;
        ctor_framealignmenterror : out boolean
    );
end;

architecture rtl of livt_signal_ratechange_cicdecimatorq15pipelineprimitive is
    constant RATE : positive := ctor_rateshape'length;
    constant STAGES : positive := ctor_stageshape'length;
    constant DIFFERENTIAL_DELAY : positive := ctor_delayshape'length / STAGES;
    constant ACCUMULATOR_BITS : positive := ctor_widthshape'length;

    subtype accumulator_t is signed(ACCUMULATOR_BITS - 1 downto 0);
    type accumulator_array_t is array (natural range <>) of accumulator_t;

    function ceil_log2(value : positive) return natural is
        variable result : natural := 0;
        variable capacity : positive := 1;
    begin
        while capacity < value loop
            capacity := capacity * 2;
            result := result + 1;
        end loop;
        return result;
    end;

    function effective_shift(configured : integer) return natural is
    begin
        if configured = -1 then
            return STAGES * ceil_log2(RATE * DIFFERENTIAL_DELAY);
        end if;
        return configured;
    end;

    function quantize_q15(value : accumulator_t; shift : natural)
        return std_logic_vector is
        variable extended : signed(ACCUMULATOR_BITS downto 0);
        variable magnitude, rounded : unsigned(ACCUMULATOR_BITS downto 0);
        variable sticky : boolean := false;
        variable raw : integer;
    begin
        extended := resize(value, extended'length);
        if extended(extended'high) = '1' then
            magnitude := unsigned(-extended);
        else
            magnitude := unsigned(extended);
        end if;

        rounded := shift_right(magnitude, shift);
        if shift > 0 and magnitude(shift - 1) = '1' then
            if shift > 1 then
                for bit_index in 0 to shift - 2 loop
                    if magnitude(bit_index) = '1' then sticky := true; end if;
                end loop;
            end if;
            if sticky or rounded(0) = '1' then rounded := rounded + 1; end if;
        end if;

        if extended(extended'high) = '1' then
            if rounded >= resize(to_unsigned(32768, 16), rounded'length) then
                return std_logic_vector(to_signed(-32768, 16));
            end if;
            raw := to_integer(rounded(14 downto 0));
            return std_logic_vector(to_signed(-raw, 16));
        end if;
        if rounded > resize(to_unsigned(32767, 15), rounded'length) then
            return std_logic_vector(to_signed(32767, 16));
        end if;
        return std_logic_vector(to_signed(to_integer(rounded(14 downto 0)), 16));
    end;

    signal integrator_state, integrator_data : accumulator_array_t(0 to STAGES - 1) :=
        (others => (others => '0'));
    signal integrator_valid, integrator_boundary : std_logic_vector(0 to STAGES - 1) :=
        (others => '0');
    signal integrator_first, integrator_last : std_logic_vector(0 to STAGES - 1) :=
        (others => '0');

    signal comb_data : accumulator_array_t(0 to STAGES - 1) :=
        (others => (others => '0'));
    signal comb_valid, comb_first, comb_last : std_logic_vector(0 to STAGES - 1) :=
        (others => '0');
    signal comb_history : accumulator_array_t(0 to STAGES * DIFFERENTIAL_DELAY - 1) :=
        (others => (others => '0'));

    signal phase : natural range 0 to RATE - 1 := 0;
    signal group_first : std_logic := '0';
    signal frame_alignment_error : std_logic := '0';
    signal advance : boolean;
begin
    advance <= comb_valid(STAGES - 1) = '0' or ctor_outputready;
    ctor_inputready <= ctor_lvt_context_in.rst = '0' and advance;
    ctor_outputvalid <= ctor_lvt_context_in.rst = '0' and
        comb_valid(STAGES - 1) = '1';
    ctor_outputsample <= quantize_q15(comb_data(STAGES - 1),
        effective_shift(to_integer(ctor_outputshift)));
    ctor_outputfirst <= comb_first(STAGES - 1) = '1';
    ctor_outputlast <= comb_last(STAGES - 1) = '1';
    ctor_framealignmenterror <= frame_alignment_error = '1';

    process (ctor_lvt_context_in.clk)
        variable selected_phase : natural range 0 to RATE - 1;
        variable current_group_first, boundary : boolean;
        variable next_value, source_value, delayed_value : accumulator_t;
        variable base : natural;
    begin
        if rising_edge(ctor_lvt_context_in.clk) then
            if ctor_lvt_context_in.rst = '1' then
                integrator_state <= (others => (others => '0'));
                integrator_data <= (others => (others => '0'));
                integrator_valid <= (others => '0');
                integrator_boundary <= (others => '0');
                integrator_first <= (others => '0');
                integrator_last <= (others => '0');
                comb_data <= (others => (others => '0'));
                comb_valid <= (others => '0');
                comb_first <= (others => '0');
                comb_last <= (others => '0');
                comb_history <= (others => (others => '0'));
                phase <= 0;
                group_first <= '0';
                frame_alignment_error <= '0';
            else
                assert RATE >= 2 and RATE <= 1024
                    report "CIC decimation rate must be in 2..1024" severity failure;
                assert STAGES >= 1 and STAGES <= 6
                    report "CIC stage count must be in 1..6" severity failure;
                assert ctor_delayshape'length mod STAGES = 0 and
                    DIFFERENTIAL_DELAY >= 1 and DIFFERENTIAL_DELAY <= 2
                    report "CIC differential delay must be 1 or 2" severity failure;
                assert to_integer(ctor_outputshift) >= -1 and
                    effective_shift(to_integer(ctor_outputshift)) < ACCUMULATOR_BITS
                    report "CIC output shift exceeds the accumulator width" severity failure;

                if advance then
                    frame_alignment_error <= '0';

                    integrator_valid(0) <= '0';
                    integrator_boundary(0) <= '0';
                    integrator_first(0) <= '0';
                    integrator_last(0) <= '0';
                    if ctor_inputvalid then
                        next_value := integrator_state(0)
                            + resize(signed(ctor_inputsample), ACCUMULATOR_BITS);
                        integrator_state(0) <= next_value;
                        integrator_data(0) <= next_value;
                        integrator_valid(0) <= '1';

                        if ctor_inputfirst then
                            selected_phase := 0;
                            current_group_first := true;
                        else
                            selected_phase := phase;
                            current_group_first := group_first = '1';
                        end if;
                        boundary := selected_phase = RATE - 1;
                        if boundary then integrator_boundary(0) <= '1'; end if;
                        if boundary and current_group_first then
                            integrator_first(0) <= '1';
                        end if;
                        if boundary and ctor_inputlast then integrator_last(0) <= '1'; end if;

                        if ctor_inputlast then
                            if not boundary then frame_alignment_error <= '1'; end if;
                            phase <= 0;
                            group_first <= '0';
                        elsif boundary then
                            phase <= 0;
                            group_first <= '0';
                        else
                            phase <= selected_phase + 1;
                            if current_group_first then group_first <= '1';
                            else group_first <= '0'; end if;
                        end if;
                    end if;

                    for stage in 1 to STAGES - 1 loop
                        integrator_valid(stage) <= integrator_valid(stage - 1);
                        integrator_boundary(stage) <= integrator_boundary(stage - 1);
                        integrator_first(stage) <= integrator_first(stage - 1);
                        integrator_last(stage) <= integrator_last(stage - 1);
                        if integrator_valid(stage - 1) = '1' then
                            next_value := integrator_state(stage)
                                + integrator_data(stage - 1);
                            integrator_state(stage) <= next_value;
                            integrator_data(stage) <= next_value;
                        end if;
                    end loop;

                    comb_valid(0) <= integrator_valid(STAGES - 1)
                        and integrator_boundary(STAGES - 1);
                    comb_first(0) <= integrator_first(STAGES - 1);
                    comb_last(0) <= integrator_last(STAGES - 1);
                    if integrator_valid(STAGES - 1) = '1' and
                        integrator_boundary(STAGES - 1) = '1' then
                        source_value := integrator_data(STAGES - 1);
                        delayed_value := comb_history(DIFFERENTIAL_DELAY - 1);
                        for tap in DIFFERENTIAL_DELAY - 1 downto 1 loop
                            comb_history(tap) <= comb_history(tap - 1);
                        end loop;
                        comb_history(0) <= source_value;
                        comb_data(0) <= source_value - delayed_value;
                    end if;

                    for stage in 1 to STAGES - 1 loop
                        comb_valid(stage) <= comb_valid(stage - 1);
                        comb_first(stage) <= comb_first(stage - 1);
                        comb_last(stage) <= comb_last(stage - 1);
                        if comb_valid(stage - 1) = '1' then
                            source_value := comb_data(stage - 1);
                            base := stage * DIFFERENTIAL_DELAY;
                            delayed_value := comb_history(base + DIFFERENTIAL_DELAY - 1);
                            for tap in DIFFERENTIAL_DELAY - 1 downto 1 loop
                                comb_history(base + tap) <= comb_history(base + tap - 1);
                            end loop;
                            comb_history(base) <= source_value;
                            comb_data(stage) <= source_value - delayed_value;
                        end if;
                    end loop;
                end if;
            end if;
        end if;
    end process;
end;
