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
9. Infer DMO DSB/DNB slots from training-sequence offsets.
10. Confirm DMO fixed fields and extract BKN1/BKN2 payload blocks.
11. Decode DSB BKN1/SCH-S and assign FN/TN timing to confirmed bursts.

Entry point:

```matlab
examples/tetra/tetra_symbol_debug.m
```

Primary output directory:

```text
outputs/tetra_symbol_debug/interactive_latest
```

`tetra.symbolDebug` writes `summary.mat`, `summary.json`, `bits_preview.txt`,
`slots_preview.txt`, `dmo_payload_preview.txt`, `schs_preview.txt`, and
`frequency_correction_preview.txt` to the selected output directory.
The current interactive default is `ShowFigures=true` and `SaveFigures=false`,
so the example opens twelve processing-stage figure windows and does not save
PNG files by default.

To save the processing-stage figures as PNG files, call:

```matlab
tetra.symbolDebug(file, 'ShowFigures', true, 'SaveFigures', true)
```

The active-window length can be adjusted without editing `tetra.config`:

```matlab
tetra.symbolDebug(file, ...
    'ActivePrePadSec', 0.020, ...
    'ActivePostPadSec', 0.300, ...
    'ActiveMaxSec', 0.800)
```

The example script currently uses this longer post-window setting so the DMO
debug view includes the bursts immediately following the initial DSB sequence.

The DMO slot output uses EN 300 396-2 field positions, not a centered-training
shortcut:

```text
DSB sync training:    slot bit 249
DNB normal training: slot bit 265
DSB BKN1/SCH-S:      slot bits 129..248, 120 bits
DSB BKN2/SCH-H:      slot bits 287..502, 216 bits
DNB BKN1:            slot bits 49..264, 216 bits
DNB BKN2:            slot bits 287..502, 216 bits
```

The extracted BKN blocks are still scrambled/coded/interleaved physical payload
bits. They are suitable input for the next channel/data-link decoding stage.

For DSB `BKN1/SCH-S`, the debug path now performs the first channel decode:

```text
120 scrambled SCH/S bits
-> descramble with DSB zero colour-code seed
-> (120,11) deinterleave
-> RCPC rate 2/3 Viterbi decode
-> (76,60) block-code check + 4 tail-bit check
-> parse 60-bit DMAC-SYNC SCH/S fields
```

The parsed timing fields are `frameNumber` and `slotNumber`. `SCH/S` is layer-2
DMAC-SYNC information, so this step is beyond pure modulation recovery, but it
is still a narrow synchronization decode rather than full MAC/layer-3 decoding.

For the DSB frequency-correction field, `12_frequency_correction_check` compares
the observed differential-symbol frequency against the theoretical field pattern:

```text
4 symbols at -6.75 kHz
32 symbols at +2.25 kHz
4 symbols at -6.75 kHz
```

The text version is written to `frequency_correction_preview.txt`.
