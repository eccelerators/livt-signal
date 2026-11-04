# Changelog

All notable changes to this package are documented here.

## 0.1.0 - 2026-11-04

### Added

- `CordicNcoQ15` with configurable 16- through 32-bit modulo phase,
  backpressure-coherent advancement, and Q1.15 sine/cosine output.
- One-stage `RealMixerQ15` and `ComplexMixerQ15` pipelines with atomic paired
  inputs, nearest-even Q1.15 quantization, saturation, and aligned framing.
- Scalar and compile-time-vector complex stream contracts for FFT/IFFT
  composition, including explicit direction, ordering, fixed-schedule scaling,
  and block-floating frame exponents.
- `SequentialFftQ15`, an in-place radix-2 FFT/IFFT for power-of-two sizes 8
  through 4096 with one shared butterfly, fixed Q1.15 twiddles, configurable
  per-stage scaling, natural or bit-reversed boundaries, and retained
  backpressure-safe output.
- Q1.15-sample FIR numeric, streaming, reset, resource, and pipeline contract,
  including configurable coefficient formats and an explicit symmetric
  architecture.
- Full-throughput `FirQ15` with fixed elaboration-time coefficients and
  multiplier-reduced `SymmetricFirQ15` for mirrored coefficient sets.
- `ReloadableFirQ15` and `IFirQ15CoefficientControl` with double-buffered,
  complete-bank loading and atomic activation.
- `BiquadQ15`, a fixed-coefficient direct-form-I second-order IIR section with
  Q2.14 defaults, exact accumulation, quantized stability checks, nearest-even
  rounding, saturation, and stall-safe recursive state.
- `WindowQ15` and symmetric or periodic Hann, Hamming, and Blackman Q1.15
  windows for power-of-two lengths 8 through 4096, using fixed folded
  coefficient tables and one multiplier.
- `CicDecimatorQ15` and `CicInterpolatorQ15` for multiplier-free compile-time
  integer rate changes, with full-width registered state, automatic or explicit
  Q1.15 output scaling, deterministic framing, and stall-safe pipelines.
- Unscaled signed-16 and signed/unsigned 32-bit sample-stream interfaces.
- Exact full-window moving sum, nearest-even mean, floored RMS, and floor
  population variance components for signed-16 sample streams.
- One-sample-per-clock rolling state and globally stallable arithmetic pipelines
  with stable markers and outputs under backpressure.
- `IQ15SampleStream`, the consumer-oriented signed Q1.15 valid/ready contract
  with aligned `first` and `last` frame markers.
- `Q15SampleEncoding` helpers for exact stream decoding and saturating encoding.
- `Q15SampleDelay<STAGES>`, a registered stall-safe sample alignment pipeline.
- `Q15SampleFifo<CAPACITY>`, a bounded FIFO that preserves samples and frame
  markers under backpressure.
- Usage documentation covering composition, numeric representation,
  backpressure, latency, framing, reset, and CDC boundaries.

### Compatibility

- This is the first experimental release. Stream API compatibility is not
  guaranteed before `Livt.Signal 1.0.0`.
