# Q1.15 CIC rate change

`Livt.Signal.RateChange` provides compile-time integer-rate CIC components for
multiplier-free sample-rate conversion:

- `CicDecimatorQ15<RATE, STAGES, DIFFERENTIAL_DELAY, OUTPUT_SHIFT>` consumes
  every accepted input and emits one result per `RATE` samples.
- `CicInterpolatorQ15<RATE, STAGES, DIFFERENTIAL_DELAY, OUTPUT_SHIFT>` expands
  every accepted input into `RATE` results.

Both components use `IQ15SampleStream` endpoints. `RATE` is supported in
`2..1024`, `STAGES` in `1..6`, and `DIFFERENTIAL_DELAY` is 1 or 2. These are
elaboration-time parameters so accumulator widths, storage, cadence, and
resources remain predictable.

## Transfer functions and gain

For rate `R`, stage count `N`, and differential delay `M`, the CIC response is

```text
H(z) = ((1 - z^(-R M)) / (1 - z^-1))^N
```

The decimator DC gain is `(R M)^N`. The interpolator's constant low-rate input
gain, after zero insertion, is `R^(N-1) M^N`.

CIC filters have passband droop. The useful passband depends on `R`, `N`, and
`M`; the components do not claim a flat passband or include a compensation
filter. Compose a following `SymmetricFirQ15` after decimation, or place it
before interpolation, when an application requires droop correction. This
keeps the CIC datapath multiplier-free and lets the FIR implement the required
application-specific response and gain correction.

## Width and output scaling

The registered integrators and combs use

```text
INTERNAL_GROWTH_BITS = N * ceil(log2(R M))
ACCUMULATOR_BITS      = 16 + INTERNAL_GROWTH_BITS
```

This conservative full-width policy does not truncate between CIC stages.
Integrator wrap uses ordinary fixed-width two's-complement modular arithmetic;
the matching comb chain recovers the bounded CIC result at the selected width.

`OUTPUT_SHIFT = -1` selects automatic safe scaling. The decimator uses
`N * ceil(log2(R M))`. The interpolator uses
`(N - 1) * ceil(log2(R)) + N * ceil(log2(M))`. These shifts are exact gain
normalization when the factors are powers of two. Otherwise they reserve safe
headroom and introduce a documented attenuation; a compensation FIR can apply
the remaining constant gain.

A nonnegative `OUTPUT_SHIFT` overrides automatic scaling. Smaller shifts retain
more CIC gain and may saturate. Larger shifts reserve more headroom. At this
single output boundary, both components round to nearest with ties to even and
saturate to signed Q1.15. They never wrap the public output.

The wrappers publish `INTERNAL_GROWTH_BITS`, `ACCUMULATOR_BITS`,
`AUTOMATIC_OUTPUT_SHIFT`, `CONFIGURED_OUTPUT_SHIFT`, cadence, latency,
capacity, and a `MULTIPLIER_COUNT` of zero.

## Architecture and timing

The decimator implements registered integrators at the input rate, selects
every `RATE`th token, and then passes selected tokens through registered comb
stages. With no stalls, its input initiation interval is one, output initiation
interval is `RATE`, and nominal selected-token latency is `2 * STAGES` clocks.

The interpolator evaluates its comb chain once for each accepted low-rate
input, inserts `RATE - 1` zeros, and passes the expanded sequence through
registered integrators. Its input initiation interval is `RATE` transferred
output clocks, output initiation interval is one, and nominal first-result
latency is `STAGES` clocks.

Neither datapath contains a runtime multiplier or coefficient memory. The
decimator uses `STAGES * DIFFERENTIAL_DELAY` comb-history words; the
interpolator uses the same amount of low-rate comb history. All pipeline state
is clock-enabled only when the global pipeline advances.

## Backpressure and reset

Output payload and markers remain stable while `valid && !ready`. A blocked
output freezes the complete CIC pipeline, including integrators, comb history,
rate phase, zero insertion, and pending markers, and propagates backpressure to
the input. Consequently no state advances for an unaccepted token and no
sample is lost or duplicated.

Reset cancels pending input expansion and buffered results, clears filter
history and rate phase, and deasserts output validity. Observable behavior is
the same for synchronous and asynchronous project reset styles.

## Frame markers

Interpolation maps one input frame to a frame containing `RATE` times as many
samples. An input `first` appears on the first generated result, and input
`last` appears on the final generated result for that token.

Decimator frames are well formed when their length is a multiple of `RATE`.
An accepted `first` restarts the rate phase and marks the first complete output
group. A `last` on a group boundary marks that output as last. A `last` before
the group is complete discards that partial group and pulses
`frameAlignmentError`; the indication remains asserted if the global pipeline
is stalled. The component does not emit an irregularly timed partial CIC
sample. Arithmetic history remains continuous across ordinary frame markers.
Continuous streams keep both markers low.

An input frame shorter than `RATE` therefore produces no output frame and
reports `frameAlignmentError` when it ends. Reset also abandons an incomplete
group, without reporting an error.
