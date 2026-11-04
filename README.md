# Livt.Signal

`Livt.Signal` provides reusable, hardware-oriented signal-processing components
for Livt projects. Version 0.1.0 includes signed Q1.15 sample streams, moving
statistics, filters, window functions, sample-rate conversion, FFT/IFFT,
oscillators, and mixers.

## 📦 Package

```toml
[dependencies]
Livt.Signal = "0.1.0"
```

`Livt.Signal` depends on `Livt.Base 1.2.0`, `Livt.Math 1.6.0`, and
`Livt.Collections 1.4.1`.

## Components

The `Livt.Signal.Stream` namespace provides the common stream contracts:

- `IQ15SampleStream` — signed Q1.15 samples with valid/ready flow control and
  `first`/`last` frame markers.
- `Q15SampleEncoding` — exact sign-extending decode and saturating encode at the
  stream/arithmetic boundary.
- `Q15SampleDelay<STAGES>` — a registered, globally stallable alignment
  pipeline with nominal latency `STAGES`, initiation interval one, and capacity
  `STAGES`.
- `Q15SampleFifo<CAPACITY>` — a bounded FIFO that preserves samples and frame
  markers under backpressure.
- `IInt16SampleStream`, `IInt32SampleStream`, and `IUInt32SampleStream` —
  explicitly scaled integer streams using the same flow-control contract.

The `Livt.Signal.Statistics` namespace provides exact full-window
`MovingSumInt16`, `MovingMeanInt16`, `MovingRmsInt16`, and
`MovingVarianceInt16` components. All accept one sample per clock after fill;
their fixed arithmetic latency and capacity are exposed as public constants.

The `Livt.Signal.Filter` namespace provides `FirQ15` and `SymmetricFirQ15` with
configurable signed coefficient formats, nearest-even output rounding,
saturation, and stall-safe timing. `ReloadableFirQ15` supports complete
coefficient-set loading and atomic activation. `BiquadQ15` provides a
fixed-coefficient IIR section using the normalized second-order-section
convention and quantized stability checks. See
[the FIR contract](docs/filter/fir-q15.md) and
[the biquad contract](docs/filter/biquad-q15.md).

The `Livt.Signal.Window` namespace provides arbitrary fixed `WindowQ15` tables
and symmetric or periodic Hann, Hamming, and Blackman components. Window
position follows the stream's frame markers and remains coherent under stalls.
See [the window contract](docs/window/windows-q15.md).

The `Livt.Signal.RateChange` namespace provides `CicDecimatorQ15` and
`CicInterpolatorQ15` for compile-time integer sample-rate changes. They expose
accumulator growth and output cadence, support automatic or explicit output
scaling, and preserve stream backpressure. See
[the CIC contract](docs/ratechange/cic-q15.md).

The `Livt.Signal.Transform` namespace defines complex sample streams and
explicit FFT/IFFT direction, ordering, and scaling contracts.
`SequentialFftQ15` supports power-of-two transform sizes from 8 through 4096.
See [the FFT/IFFT contract](docs/transform/fft-contract.md).

The `Livt.Signal.Oscillator` namespace provides `CordicNcoQ15`, a numerically
controlled oscillator with 16- through 32-bit modulo phase accumulation.
`Livt.Signal.Mixer` provides real and complex Q1.15 mixers. Their paired
valid/ready inputs keep oscillator phase coherent with samples under
backpressure. See
[the NCO and mixer contract](docs/oscillator/nco-mixer-q15.md).

A token transfers on an active clock edge when `valid && ready`. A producer
holds the complete token stable while stalled. All interfaces are single-clock;
crossing a clock or reset domain requires an explicit CDC component.

See [the usage guide](docs/usage.md) for numeric, framing, reset, timing, and
composition details.

## Package boundary

`Livt.Signal` owns reusable sample-stream processing. Scalar fixed-point
arithmetic, complex Q15 helpers, square root, and CORDIC remain in `Livt.Math`.
Protocol-specific transport, media framing, and application processing are
outside the package's scope.

## Build and test

```sh
livt sync
livt test
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
