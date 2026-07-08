# TETRA Symbol Debug Phase

This phase is intentionally independent from `radio.protocolRegistry`.

Goal:

1. Read a TETRA IQ WAV file.
2. Resample to 72 kHz, giving 4 samples per 18 ksym/s symbol.
3. Select an active burst/window.
4. Apply coarse frequency correction.
5. Apply RRC matched filtering with alpha 0.35.
6. Search symbol timing phase by differential phase clustering.
7. Recover pi/4-DQPSK dibits and hard bits.
8. Search known TETRA training sequences as a sanity check.
9. Infer first-pass 510-bit slot candidates from training-sequence offsets.

Entry point:

```matlab
examples/tetra/tetra_symbol_debug.m
```

Primary output directory:

```text
outputs/tetra_symbol_debug/interactive_latest
```

`tetra.symbolDebug` writes `summary.mat`, `summary.json`, and
`bits_preview.txt`, and `slots_preview.txt` to the selected output directory.
The current interactive default is `ShowFigures=true` and `SaveFigures=false`,
so the example opens eleven processing-stage figure windows and does not save
PNG files by default.

To save the processing-stage figures as PNG files, call:

```matlab
tetra.symbolDebug(file, 'ShowFigures', true, 'SaveFigures', true)
```

The extra slot-boundary output is a first-pass debug aid. It assumes each known
training sequence is centered in a 510-bit slot, then uses the recovered
training-sequence bit offset to infer candidate slot start and end positions.
