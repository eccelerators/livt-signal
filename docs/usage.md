# Livt.Signal usage

## Q1.15 sample stream

`Livt.Signal.Stream.IQ15SampleStream` transports one exact signed 16-bit
two's-complement Q1.15 sample per token. The mathematical value is the signed
raw value divided by 32768, giving the range `-1.0` through `32767 / 32768`.

The interface is declared from the consumer's point of view:

```livt
interface IQ15SampleStream
{
	sample: in logic[16]
	valid: in bool
	first: in bool
	last: in bool
	ready: out bool
}
```

A consumer accepts `IQ15SampleStream`. A producer accepts
`flip IQ15SampleStream`. One token transfers on an active clock edge when
`valid && ready` and reset is not asserted. The producer must hold `sample`,
`first`, `last`, and `valid` stable until that transfer occurs.

`first` and `last` mark the first and last samples of a non-empty frame. A
one-sample frame sets both. An unframed continuous stream keeps both low. The
markers have meaning only while `valid` is true and always stall with their
sample.

## Numeric conversion

Use `Q15SampleEncoding.Decode(sample)` to sign-extend a stream payload into a
raw Q1.15 `int`. This changes representation width without changing scale.

Use `Q15SampleEncoding.EncodeSaturating(value)` at a documented output
quantization boundary. It clamps through `Livt.Math.FixedPoint.Q15` before
returning the 16-bit two's-complement encoding. Scaling and arithmetic rounding
remain the responsibility of the processing component.

## Composition

The following component adds a three-stage alignment delay and a four-token
elastic buffer between borrowed endpoints:

```livt
namespace Example

using Livt.Signal.Stream

component BufferedSignalPath
{
	intermediate: IQ15SampleStream
	delay: Q15SampleDelay<3>
	buffer: Q15SampleFifo<4>

	new(inputStream: IQ15SampleStream,
		outputStream: flip IQ15SampleStream)
	{
		delay = new Q15SampleDelay<3>(inputStream, intermediate)
		buffer = new Q15SampleFifo<4>(intermediate, outputStream)
	}
}
```

Interface parameters are structural wiring. The component does not own the
input or output endpoint; it owns only the delay and FIFO instances.

## Moving statistics

`Livt.Signal.Statistics` operates on unscaled signed integers through
`IInt16SampleStream`, not through the numerically distinct Q1.15 interface.
Each component accepts a compile-time `WINDOW_SIZE` in `1..65535`:

- `MovingSumInt16` emits an exact signed-32 sum.
- `MovingMeanInt16` emits a signed-32 mean rounded to nearest, with ties to even.
- `MovingRmsInt16` emits `floor(sqrt(floor(sumSquares / WINDOW_SIZE)))`.
- `MovingVarianceInt16` emits floor population variance using the exact
  `WINDOW_SIZE * sumSquares - sum * sum` numerator.

The initial window fill produces no tokens. `fillCount` and `windowFull` expose
its progress; the transfer that fills the window produces the first result.
Thereafter every accepted sample evicts the oldest sample and produces one
result. The window continues across frame markers. A result carries the markers
of the input token that caused that result, while markers on fill-only tokens
are not replayed.

All four components have initiation interval one with an accepting downstream.
Read each component's `NOMINAL_LATENCY` and `CAPACITY` constants when aligning
parallel paths. A blocked result freezes its arithmetic pipeline and propagates
backpressure before another sample can be accepted. Reset empties the logical
window and cancels pending results without clearing sample-memory payloads.

## FIR filters

`FirQ15` binds a fixed coefficient array at elaboration and accepts one sample
per clock. Coefficient index zero multiplies the newly accepted sample:

```livt
namespace Example

using Livt.Signal.Filter
using Livt.Signal.Stream

component ThreeTapLowPass
{
	const COEFFICIENTS: int[3] = [8192, 16384, 8192]
	filter: FirQ15<3>

	new(inputStream: IQ15SampleStream,
		outputStream: flip IQ15SampleStream)
	{
		// Q1.15 coefficients: 0.25, 0.5, 0.25.
		filter = new FirQ15<3>(inputStream, outputStream, COEFFICIENTS)
	}
}
```

Use `SymmetricFirQ15` for an explicitly mirrored coefficient set when reducing
the multiplier count is worth one registered pre-adder stage. Configurable
coefficient formats, exact arithmetic, rounding, saturation, pipeline timing,
and reset behavior are specified in
[the Q1.15 FIR contract](filter/fir-q15.md).

Use `ReloadableFirQ15` when coefficients must change at runtime. Its separate
control interface loads every tap into an inactive bank, then atomically
activates the complete bank. A sample accepted with the commit still uses the
old bank; the next accepted sample uses the new bank.

## Biquad IIR filters

`BiquadQ15` implements one fixed-coefficient second-order section. Supply the
three numerator coefficients and the two denominator coefficients after
normalizing `a0` to one:

```livt
namespace Example

using Livt.Signal.Filter
using Livt.Signal.Stream

component LowPassSection
{
	// Q2.14: b0, b1, b2 and a1, a2.
	const B: int[3] = [4096, 8192, 4096]
	const A: int[2] = [-8192, 4096]
	filter: BiquadQ15

	new(inputStream: IQ15SampleStream,
		outputStream: flip IQ15SampleStream)
	{
		filter = new BiquadQ15(inputStream, outputStream, B, A)
	}
}
```

The implemented equation subtracts `a1*y[n-1]` and `a2*y[n-2]`, matching the
usual normalized SOS convention. Cascade sections through intermediate
`IQ15SampleStream` endpoints for higher-order filters. Each section rounds and
saturates independently. See [the biquad contract](filter/biquad-q15.md) for
numeric, stability, state, timing, and reset details.

## Window functions

Use the periodic variants before a fixed-size FFT frame:

```livt
namespace Example

using Livt.Signal.Stream
using Livt.Signal.Window

component WindowedFftInput
{
	window: PeriodicHannWindowQ15<1024>

	new(inputStream: IQ15SampleStream,
		outputStream: flip IQ15SampleStream)
	{
		window = new PeriodicHannWindowQ15<1024>(inputStream, outputStream)
	}
}
```

`HannWindowQ15`, `HammingWindowQ15`, and `BlackmanWindowQ15` include both
finite-frame endpoints. Their `Periodic...` counterparts omit the duplicated
endpoint. Standard lengths are powers of two from 8 through 4096.

Use `WindowQ15<SAMPLES>` with an elaboration-time signed Q1.15 coefficient
array for another length or a custom window. See
[the window contract](window/windows-q15.md) for coefficient quantization,
framing, malformed-frame recovery, timing, and reset behavior.

## CIC rate change

`Livt.Signal.RateChange` provides separate multiplier-free decimation and
interpolation components. This example reduces the sample rate by eight with
five CIC stages and the default safe output shift:

```livt
namespace Example

using Livt.Signal.RateChange
using Livt.Signal.Stream

component AdcRateReduction
{
	decimator: CicDecimatorQ15<8, 5>

	new(inputStream: IQ15SampleStream,
		outputStream: flip IQ15SampleStream)
	{
		decimator = new CicDecimatorQ15<8, 5>(inputStream, outputStream)
	}
}
```

`OUTPUT_SHIFT = -1` selects automatic safe scaling. Supply a nonnegative final
generic argument when the surrounding signal chain has a different headroom or
gain plan. Decimator frame lengths must be multiples of the rate; a misaligned
`last` discards the partial group and pulses `frameAlignmentError`.

See [the CIC contract](ratechange/cic-q15.md) for gain equations, accumulator
growth, rounding, saturation, marker mapping, cadence, and compensation-filter
composition.

## FFT and IFFT composition

Finite-frame transforms use `Livt.Signal.Transform.IComplexSampleStream<T>`.
The payload type supports scalar or vector transport at compile time:

```livt
IComplexSampleStream<logic[16]>
IComplexSampleStream<logic[32, 16]>
```

`SequentialFftQ15` uses the scalar `logic[16]` form.

See [the FFT/IFFT contract](transform/fft-contract.md) for transform direction,
ordering, fixed and block-floating scaling, framing, and reset behavior.

`SequentialFftQ15` processes one scalar frame at a time:

```livt
namespace Example

using Livt.Signal.Transform

component SpectrumTransform
{
	fft: SequentialFftQ15<1024>

	new(inputStream: IComplexSampleStream<logic[16]>,
		outputStream: flip IComplexSampleStream<logic[16]>)
	{
		fft = new SequentialFftQ15<1024>(inputStream, outputStream)
	}
}
```

The default shifts every radix-2 stage and therefore emits the forward transform
divided by `SAMPLES`. Supply an explicit `STAGE_SHIFT_MASK` when the surrounding
gain plan provides known headroom. Natural input and output order are the
defaults; bit-reversed boundaries can avoid a permutation between compatible
transform stages.

## NCO and frequency translation

Compose a CORDIC NCO with a mixer when translating a real sample stream to
complex baseband:

```livt
namespace Example

using Livt.Signal.Mixer
using Livt.Signal.Oscillator
using Livt.Signal.Stream
using Livt.Signal.Transform

component DownConverter
{
	oscillatorStream: IComplexSampleStream<logic[16]>
	nco: CordicNcoQ15
	mixer: RealMixerQ15
	public frequencyControlWord: in logic[32]

	new(inputStream: IQ15SampleStream,
		outputStream: flip IComplexSampleStream<logic[16]>)
	{
		nco = new CordicNcoQ15(oscillatorStream)
		mixer = new RealMixerQ15(inputStream, oscillatorStream, outputStream)
	}

	process Configure[]()
	{
		nco.phaseIncrement = frequencyControlWord
	}
}
```

The frequency-control word is signed turns per accepted sample modulo 2^32.
Negative values generate negative frequencies. Backpressure freezes the sample
and oscillator phase together. See
[the Q1.15 NCO and mixer contract](oscillator/nco-mixer-q15.md).

## Delay contract

`Q15SampleDelay<STAGES>` requires `STAGES > 0`.

- Nominal latency: `STAGES` clock cycles with output `ready` continuously high.
- Initiation interval: one clock.
- Capacity: `STAGES` tokens.
- Backpressure: when the oldest valid token is blocked, every stage freezes and
  input `ready` becomes false.
- Reset: all stage-valid bits clear; payload registers need not be cleared.

The delay is intentionally globally stallable rather than bubble-compacting.
This gives alignment paths a simple, predictable registered implementation.

## FIFO contract

`Q15SampleFifo<CAPACITY>` requires `CAPACITY > 0`. It packs `sample`, `first`,
and `last` into one 18-bit FIFO word so all token fields share one ordering and
occupancy state.

- Nominal latency: one clock; the FIFO does not provide empty bypass.
- Initiation interval: one clock for pushes and pops.
- Capacity: exactly `CAPACITY` tokens.
- A full FIFO may accept a new token on the same edge that its current head is
  removed.
- Reset returns occupancy to empty without clearing payload storage.

## Clock and reset domains

Both components inherit their clock and reset context. They do not perform
clock-domain crossing or reset-domain synchronization. Insert an explicit CDC
component before connecting endpoints from different domains.
