# Q1.15 streaming window contract

Livt.Signal window components multiply each accepted Q1.15 sample by one fixed
Q1.15 coefficient. They are intended for FFT preparation, spectral analysis,
and other finite-frame weighting without synthesizing runtime trigonometry.

## Components

The arbitrary fixed-table component is:

```livt
WindowQ15<SAMPLES>
```

Its constructor accepts exactly `SAMPLES` elaboration-time signed Q1.15
coefficients. `SAMPLES` may be any positive value.

Standard window components support power-of-two lengths from 8 through
4096:

```livt
HannWindowQ15<SAMPLES>
HammingWindowQ15<SAMPLES>
BlackmanWindowQ15<SAMPLES>

PeriodicHannWindowQ15<SAMPLES>
PeriodicHammingWindowQ15<SAMPLES>
PeriodicBlackmanWindowQ15<SAMPLES>
```

The symmetric forms include both endpoints of a finite sequence and use
`SAMPLES - 1` as the phase denominator. The periodic forms use `SAMPLES`, omit
the duplicated final endpoint, and are normally appropriate for an
`SAMPLES`-point FFT.

“Hanning” is a common discoverability term for the Hann window, but it is not a
separate API name.

## Standard coefficient definitions

For sample position `n`, define:

```text
phase = 2*pi*n/denominator

Hann     = 0.5  - 0.5*cos(phase)
Hamming  = 0.54 - 0.46*cos(phase)
Blackman = 0.42 - 0.5*cos(phase) + 0.08*cos(2*phase)
```

Standard coefficient tables use Q1.15 values rounded to nearest with ties to
even and clamped to `0..32767`. Mathematical positive one is therefore encoded
as `32767`, the closest positive Q1.15 value. The tables are fixed package data;
they require no runtime trigonometry or coefficient generation.

## Numeric result

For signed Q1.15 sample `x` and signed Q1.15 coefficient `w`:

```text
product = x * w
output  = saturateQ15(roundTiesToEven(product / 32768))
```

The signed 16-by-16 product is exact. There is one rounding boundary and no
automatic coherent-gain, RMS-gain, or FFT normalization compensation. A
pipeline needing such compensation must apply it explicitly at its chosen
numeric boundary.

Standard coefficients are nonnegative. `WindowQ15` permits the complete signed
Q1.15 range for custom modulation or weighting sequences.

## Architecture and timing

Every component contains one coefficient lookup, one signed multiplier, a
registered lookup/sample stage, and a registered rounded result stage. Public
timing constants are:

```text
INITIATION_INTERVAL = 1
NOMINAL_LATENCY     = 2
CAPACITY            = 2
MULTIPLIER_COUNT    = 1
```

Standard tables exploit coefficient symmetry by folding the second half of the
frame onto the stored first half. The checked-in tables contain integer
constants only; they do not instantiate CORDIC, cosine, division, or runtime
coefficient-generation hardware. Synthesis chooses whether a particular
constant lookup maps to logic, distributed storage, or ROM resources.

## Position and frame behavior

The coefficient position advances only on an accepted input transfer. Input
bubbles do not change it. A blocked output freezes both pipeline stages, the
coefficient position, the sample, and its markers.

Position recovery is deterministic:

- An accepted `first` uses coefficient zero, even in the middle of a frame.
- An accepted `last` closes the current frame; the next token uses coefficient
  zero even if that token has no `first` marker.
- An early `last` therefore produces a shortened windowed frame.
- Without `last`, the position wraps after `SAMPLES` accepted tokens.
- A frame longer than `SAMPLES` becomes consecutive fixed-size windows.
- An unframed stream likewise consists of consecutive `SAMPLES`-token windows.

`first` and `last` pass through with the result caused by the same input token.
The component never inserts or removes tokens.

Reset clears the coefficient position and cancels both pending pipeline tokens.
Fixed coefficient payloads do not require reset storage.

## Choosing a standard window

- Hann is the general-purpose choice when leakage reduction and main-lobe width
  need a balanced tradeoff.
- Hamming retains nonzero endpoints and reduces its first sidelobe relative to
  Hann, with a different far-sidelobe tradeoff.
- Blackman provides stronger sidelobe suppression at the cost of a wider main
  lobe and reduced coherent gain.

Window choice, FFT scaling, overlap, and amplitude correction remain system
design decisions rather than runtime modes of one hardware component.
