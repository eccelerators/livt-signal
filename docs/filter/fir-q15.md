# Q1.15 FIR contract

This contract defines the numeric result, stream behavior, and hardware
architecture of Livt.Signal's finite impulse response filters. Fixed,
reloadable, and symmetric filters are separate public hardware choices.

## Fixed filter API

The fixed, full-throughput component is named:

```livt
FirQ15<TAPS, COEFFICIENT_BITS = 16, COEFFICIENT_FRACTION_BITS = 15>
```

`TAPS` must be positive. `COEFFICIENT_BITS` must be in `2..31`, and
`COEFFICIENT_FRACTION_BITS` must be in `0..COEFFICIENT_BITS-1`. The defaults
provide signed Q1.15 coefficients. Its constructor binds borrowed input and
output endpoints and exactly `TAPS` elaboration-time coefficients:

```livt
const LOW_PASS: int[5] = [2048, 8192, 12288, 8192, 2048]

fir = new FirQ15<5>(inputStream, outputStream, LOW_PASS)
```

Coefficient formats can be selected without changing the Q1.15 sample
interface. For example, Q2.14 represents positive one exactly:

```livt
const UNITY: int[1] = [16384]

fir = new FirQ15<1, 16, 14>(inputStream, outputStream, UNITY)
```

The constructor shape is:

```livt
new(inputStream: IQ15SampleStream,
	outputStream: flip IQ15SampleStream,
	coefficients: const int[TAPS])
```

Each coefficient is a signed raw integer in:

```text
-2^(COEFFICIENT_BITS-1) .. 2^(COEFFICIENT_BITS-1)-1
```

and represents `raw / 2^COEFFICIENT_FRACTION_BITS`. `coefficient[0]` multiplies
the newly accepted sample and increasing indices multiply increasingly older
samples. Invalid coefficient values fail during HDL elaboration rather than
being silently truncated.

The sized `const int[TAPS]` parameter makes the coefficient list
elaboration-time configuration and allows fixed instances to contain no
coefficient update machinery.

With the default Q1.15 format, positive `1.0` is not exactly representable; use
`32767` for its closest value. Select Q2.14 when exact unity or coefficients
between one and two are required, or select a wider format when coefficient
precision is more important than multiplier width.

## Numeric result

For signed raw input `x` and coefficient `b`, the result associated with input
sample `n` is:

```text
acc[n] = sum(x[n-k] * b[k]), k = 0..TAPS-1
y[n]   = saturateQ15(roundTiesToEven(
             acc[n] / 2^COEFFICIENT_FRACTION_BITS))
```

Each signed 16-by-`COEFFICIENT_BITS` multiplication produces an exact product
of

```text
PRODUCT_BITS = 16 + COEFFICIENT_BITS
ACCUMULATOR_BITS = PRODUCT_BITS + ceil(log2(TAPS))
```

bits. There is no product or intermediate-sum rounding. The only quantization
boundary divides the final exact sum by
`2^COEFFICIENT_FRACTION_BITS`, rounds to the nearest integer with ties to even
for both signs, then saturates to `-32768..32767`. Saturation therefore handles
coefficient sets whose absolute gain exceeds one without wrapping.

## Parallel direct-form architecture

`FirQ15` uses a fully parallel, pipelined direct form:

1. A delay line retains the previous `TAPS - 1` accepted samples.
2. `TAPS` signed 16-by-`COEFFICIENT_BITS` multipliers capture exact products.
3. A balanced, exact-width adder tree reduces the products, with one registered
   level per tree level.
4. A final registered stage rounds and saturates the result.

The architecture has `TAPS` multipliers, `TAPS - 1` adders, and `TAPS - 1`
signed-16 sample-delay elements. Its initiation interval is one accepted sample
per clock. With an accepting downstream, its nominal latency and token capacity
are both:

```text
2 + ceil(log2(TAPS))
```

The implementation exposes these values as `NOMINAL_LATENCY` and `CAPACITY`.
All product, reduction, result, valid, and marker stages advance together. A
blocked output freezes the complete pipeline and propagates backpressure to the
input. This deliberately predictable global-stall contract matches the existing
Livt.Signal alignment pipeline.

Fixed coefficients require no coefficient memory, write interface, bank
selector, or commit logic. Synthesis may map constant multiplication to DSPs,
logic, or shifts according to the coefficient and target. Livt.Signal promises
the arithmetic structure, not a vendor-specific primitive mapping.

Symmetric coefficients are numerically supported but do not implicitly select a
pre-adder architecture.

## Symmetric architecture

`SymmetricFirQ15<TAPS, COEFFICIENT_BITS = 16,
COEFFICIENT_FRACTION_BITS = 15>` uses the same numeric and stream contract but
requires `coefficient[k] == coefficient[TAPS-1-k]`. A mismatch fails during HDL
elaboration.

The component pre-adds mirrored signed-16 samples in exact signed 17-bit
adders, then multiplies each pair once. An odd tap count sends its unpaired
center sample through the final multiplier with sign extension. Defining

```text
MULTIPLIER_COUNT = ceil(TAPS / 2)
```

the component uses `floor(TAPS / 2)` pre-adders, `MULTIPLIER_COUNT`
multipliers, `MULTIPLIER_COUNT - 1` reduction adders, and the same
`TAPS - 1` sample-delay elements as `FirQ15`. Its registered pre-adder stage
makes nominal latency and token capacity:

```text
3 + ceil(log2(MULTIPLIER_COUNT))
```

Its initiation interval remains one. Making symmetry explicit avoids silently
changing multiplier count, widths, latency, or DSP pre-adder mapping for an
ordinary `FirQ15` instance.

## Stream, frame, and reset behavior

Both endpoints use `Livt.Signal.Stream.IQ15SampleStream`. Every accepted input
produces exactly one output; the filter does not suppress startup results.
Missing samples before the first accepted sample are mathematically zero.

The sample delay line changes only on `inputStream.valid && inputStream.ready`.
A rejected input, an input bubble, or a downstream stall does not advance filter
history. `first` and `last` travel with the result caused by their input token.
They do not clear history: adjacent frames on one stream are filtered as one
continuous signal unless the owner resets or explicitly separates them.

Reset clears the logical sample history to zero and cancels every pending output
token. Product and sum payload registers need not reset because their valid bits
are cleared. Fixed coefficients are elaboration-time configuration and are not
resettable.

## Reloadable coefficients

Runtime coefficients use the separately named `ReloadableFirQ15<TAPS,
COEFFICIENT_BITS = 16, COEFFICIENT_FRACTION_BITS = 15>` and the
consumer-oriented `IFirQ15CoefficientControl` interface. They are not a mode of
`FirQ15`; fixed instances never pay for reload hardware.

Its constructor binds the two sample endpoints and a borrowed control endpoint:

```livt
new(inputStream: IQ15SampleStream,
	outputStream: flip IQ15SampleStream,
	control: IFirQ15CoefficientControl)
```

The reloadable architecture owns two coefficient banks. Processing reads the
active bank while accepted writes target the inactive bank. A write transfers
when `writeValid && writeReady`; `writeIndex` must be in `0..TAPS-1` and
`writeCoefficient` must fit the configured signed coefficient width.

Every tap must be written at least once after reset or the previous commit.
`commitReady` becomes true only when the complete inactive bank has been loaded
and no write is requested on that edge. A transfer on
`commitValid && commitReady` atomically swaps banks. A sample accepted on the
same edge uses the old active bank; the next accepted sample uses the new bank.
Products capture their active-bank values at sample acceptance, so an output
never combines coefficient sets.

After reset, `configured` is false and the sample input is not ready. Coefficient
payload storage need not reset. The first complete load and commit sets
`configured`; reset requires configuration to be loaded again. After each
commit, all taps of the now-inactive bank must be rewritten before another
commit, preventing stale values from silently reappearing during a partial
update.
