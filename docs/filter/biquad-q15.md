# Q1.15 biquad contract

`BiquadQ15` is a fixed-coefficient second-order IIR section for Q1.15 sample
streams. It uses direct form I so all five coefficient products are parallel
and the recursive path contains one multiplier level.

## API and coefficient convention

```livt
BiquadQ15<COEFFICIENT_BITS = 16, COEFFICIENT_FRACTION_BITS = 14>
```

The constructor binds borrowed stream endpoints and one normalized SOS
coefficient set:

```livt
new(inputStream: IQ15SampleStream,
	outputStream: flip IQ15SampleStream,
	numerator: const int[3],
	denominator: const int[2])
```

The arrays contain:

```text
numerator   = [b0, b1, b2]
denominator = [a1, a2]
```

Normalize an external SOS row `[b0, b1, b2, a0, a1, a2]` by dividing every
coefficient by `a0` before quantization. `a0` is therefore exactly one and is
not stored. The implemented recurrence is:

```text
y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2]
     - a1*y[n-1] - a2*y[n-2]
```

This explicit subtraction matches the common normalized denominator
`1 + a1*z^-1 + a2*z^-2`. Do not pre-negate feedback coefficients unless the
source tool uses the opposite convention.

Each raw coefficient represents:

```text
raw / 2^COEFFICIENT_FRACTION_BITS
```

The Q2.14 default represents the range `-2.0 .. 1.99993896484375`, including
positive one exactly as `16384`. Wider coefficient formats can improve pole
placement without changing the Q1.15 sample interface.

## Numeric result

Inputs and retained outputs are signed 16-bit Q1.15 values. Five exact signed
products are accumulated without intermediate rounding:

```text
PRODUCT_BITS     = 16 + COEFFICIENT_BITS
ACCUMULATOR_BITS = PRODUCT_BITS + 3
```

The final sum is divided by `2^COEFFICIENT_FRACTION_BITS`, rounded to the
nearest integer with ties to even for both signs, and saturated to
`-32768..32767`. That quantized, saturated result is retained as the feedback
sample for the next accepted input.

Because feedback uses the observable Q1.15 result, reference models must apply
rounding and saturation after every sample rather than only at the end of a
frame.

## Architecture and timing

The direct-form-I architecture contains:

- five parallel signed multipliers;
- a balanced exact-width sum;
- two signed-16 input-history registers;
- two signed-16 output-history registers; and
- one elastic output register carrying the sample and frame markers.

Its public timing constants are:

```text
INITIATION_INTERVAL = 1
NOMINAL_LATENCY     = 1
CAPACITY            = 1
MULTIPLIER_COUNT    = 5
```

Synthesis may eliminate multiplication by constant zero, one, powers of two,
or other reducible values. Livt.Signal specifies the arithmetic structure but
does not promise a vendor-specific DSP mapping.

## Stream, state, and reset behavior

One output is produced for every accepted input. Both sample histories start at
zero. History changes only on an input transfer, and a blocked output freezes
the complete recursive state. Input bubbles do not advance state.

`first` and `last` remain aligned with the result caused by their input token.
They do not clear filter history: adjacent frames on one stream form one
continuous signal. Use reset or a separately controlled signal path when a new
frame must begin with zero state.

Reset clears both input and output histories and cancels a pending output.
Coefficient constants are elaboration-time configuration and do not require
reset storage.

## Stability and fixed-point behavior

The quantized denominator must satisfy the strict second-order Jury conditions:

```text
1 + a1 + a2 > 0
1 - a1 + a2 > 0
1 - a2      > 0
```

The implementation asserts these conditions using the raw coefficient scale,
catching a denominator whose quantized poles are not strictly inside the unit
circle. It also asserts that every coefficient fits the selected signed width.

These checks do not guarantee application-level headroom. A stable section can
still saturate for a large input or high passband gain. Quantized feedback can
also produce a bounded zero-input limit cycle instead of converging exactly to
zero. Consumers remain responsible for coefficient design, section ordering,
inter-section scaling, and acceptable saturation behavior.

## Cascades and coefficient updates

Build a higher-order filter by connecting multiple `BiquadQ15` sections with
intermediate `IQ15SampleStream` endpoints. Each section has an explicit Q1.15
quantization boundary, one clock of nominal latency, and normal valid/ready
backpressure.

`BiquadQ15` uses fixed elaboration-time coefficients and does not support
runtime coefficient updates. Fixed instances contain no coefficient bank,
write, selector, or commit interface.
