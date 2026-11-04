# Q1.15 NCO and mixer contract

## Phase convention

`CordicNcoQ15<PHASE_BITS, INITIAL_PHASE>` owns an unsigned modulo phase
accumulator. Zero is zero turns, `2^(PHASE_BITS - 2)` is one quarter turn, and
the accumulator wraps after `2^PHASE_BITS`. The runtime `phaseIncrement` is a
two's-complement frequency-control word interpreted modulo that width:

```text
normalized output frequency = signed(phaseIncrement) / 2^PHASE_BITS
```

The default 32-bit accumulator provides fine tuning while its upper 16 bits
select the angle supplied to `Livt.Math.Trigonometry.CordicSinCosQ15`. The
complex output is `(cos(phase), sin(phase))` in Q1.15. It is an unframed stream,
so `first` and `last` remain false.

The CORDIC architecture deliberately shares one iterative worker. It is suited
to area-oriented paths whose sample period allows the 16 rotation steps.

Phase advances only when the oscillator output token is accepted. A blocked
consumer therefore holds the token and accumulator stable. Reset cancels an
active request and restores `INITIAL_PHASE` before generating a new token.

## Mixer convention

`RealMixerQ15` multiplies a real input `x` by oscillator `(c, s)`:

```text
real = x*c
imag = x*s
```

It uses two real multipliers. `ComplexMixerQ15` uses four real multipliers:

```text
real = a*c - b*d
imag = a*d + b*c
```

Both mixers retain the full product or sum-of-products width, round once to
nearest with ties to even at the Q1.15 boundary, then saturate. The sample and
oscillator inputs form an atomic pair: neither reports `ready` unless the other
has a valid token and the output stage has capacity. Sample frame markers pass
to the result; oscillator markers are ignored.

Both mixers have nominal latency one and initiation interval one when their two
inputs and output can transfer every clock. A blocked result holds its complete
payload and markers stable and prevents either input from advancing.
