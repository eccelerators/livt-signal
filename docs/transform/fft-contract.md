# FFT and IFFT contract

`Livt.Signal.Transform` defines the mathematical, framing, ordering, scaling,
and stream contracts used by `SequentialFftQ15`.

## Compile-time composition

The transform size, numeric policy, ordering, and payload width are static
design choices. `SequentialFftQ15<SAMPLES>` shares one butterfly and owns
in-place storage for power-of-two sizes from 8 through 4096.

## Complex transport

`IComplexSampleStream<T>` selects its scalar or vector payload through `T`:

```livt
IComplexSampleStream<logic[16]>
IComplexSampleStream<logic[32, 16]>
```

The first form transfers one complex Q1.15 sample. The second transfers 32
consecutive complex Q1.15 samples. For a vector transfer, lane zero has the
lowest logical sample index and lane `LANES - 1` the highest. A frame contains
exactly `SAMPLES` complex samples, `SAMPLES` must be divisible by `LANES`, and
partial vector tokens are not permitted.

`first` marks the token containing logical sample zero. `last` marks the token
containing logical sample `SAMPLES - 1`. A producer holds the real payload,
imaginary payload, markers, and `valid` stable until a transfer occurs.

A real-input transform supplies zero for each imaginary input sample. This does
not introduce a different bin definition.

## Transform definition and ordering

For `N = SAMPLES`, the forward transform is

```text
X[k] = sum(x[n] * exp(-j 2 pi k n / N)), n = 0..N-1
```

The inverse uses the positive kernel sign. Scaling is specified separately; it
is never hidden in the direction selection.

`FftOrder.Natural` transfers indices `0, 1, ..., N - 1`.
`FftOrder.BitReversed` transfers the same values in radix-2 bit-reversed index
order. Input and output order are independent compile-time choices. Natural
order is the application-facing default; bit-reversed order allows adjacent
transform stages to omit a permutation when their contracts match.

## Q1.15 arithmetic

Real and imaginary boundary values are signed two's-complement Q1.15. Twiddle
components use the same representation and are quantized to nearest with ties
to even, then saturated to `-32768..32767`.

A butterfly keeps enough intermediate width for the complex product and both
add/subtract paths. Quantization occurs only at the documented stage-storage
boundary. Right shifts round to nearest with ties to even; narrowing saturates
rather than wraps.

With `FftScalingMode.FixedSchedule`, an implementation accepts one compile-time
shift decision per radix-2 stage. If the selected stages contain `S` total
single-bit shifts, the emitted result is the mathematical forward or
unnormalized inverse transform divided by `2^S`. Shifting every stage gives
`S = log2(N)` and prevents butterfly growth for full-range Q1.15 input.

For a forward/inverse round trip, unity gain requires the two schedules to
contain `log2(N)` shifts in total. This makes normalization and lost headroom
explicit at composition time.

With `FftScalingMode.BlockFloating`, the implementation determines a shared
right-shift exponent for the frame and uses
`IBlockFloatingComplexSampleStream<T>`. `scaleExponent` is constant throughout
the output frame and means that the represented value is the signed payload
multiplied by `2^scaleExponent`. Fixed-schedule and block-floating components
have distinct endpoint types so an exponent cannot be discarded accidentally.

## Architecture contract

Every concrete transform publishes these constants:

- `SAMPLE_COUNT`, `STAGES`, and the accepted input and output ordering;
- input and output lanes per transfer;
- owned sample-storage words and twiddle-storage words;
- nominal latency, initiation interval, and frame initiation interval.

A sequential in-place transform accepts one complete frame, computes it, and
then emits it. It does not accept another frame until the previous result has
been transferred. Output backpressure retains the complete output token and
prevents result-memory reuse. Reset cancels a partial input frame, an active
calculation, and an unread result.

Backpressure preserves payload, exponent, ordering, and frame markers. No
transform interface crosses clock or reset domains.

## Sequential Q1.15 implementation

`SequentialFftQ15<SAMPLES, DIRECTION, STAGE_SHIFT_MASK, INPUT_ORDER,
OUTPUT_ORDER>` is the area-oriented in-place implementation. It supports
power-of-two sizes from 8 through 4096 and owns `SAMPLES` complex sample words,
`SAMPLES / 2` complex twiddles, and one four-multiplier butterfly worker.

`STAGE_SHIFT_MASK = -1` shifts every stage. Otherwise, bit zero selects the
first radix-2 stage, bit one the second stage, and so on. Bits at or above
`STAGES` are ignored. Every selected stage adds one to the fixed scaling
exponent. Every stage narrows with nearest-even rounding and signed Q1.15
saturation, including stages that are not shifted.

The implementation publishes:

```text
BUTTERFLY_COUNT            = SAMPLES / 2 * STAGES
COMPUTE_CYCLES             = 2 * BUTTERFLY_COUNT
NOMINAL_FRAME_LATENCY      = SAMPLES + COMPUTE_CYCLES
OUTPUT_INITIATION_INTERVAL = 2
FRAME_INITIATION_INTERVAL  = 3 * SAMPLES + COMPUTE_CYCLES
```

These values assume continuous input and continuously ready output. Output
backpressure extends the frame interval and retains the blocked payload and
markers. The component cannot overlap loading, computation, and output.

An input frame must begin with `first` and contain exactly `SAMPLES` accepted
tokens. An early `last`, a missing final `last`, or data outside an active frame
pulses `frameLengthError` and discards the incomplete frame. A later `first`
starts a fresh frame. Reset cancels a partial input, active computation, and
unread output without requiring the sample RAM to be cleared.

ADC lane alignment, sample unpacking, and clock-domain crossing remain device
or I/O responsibilities.
