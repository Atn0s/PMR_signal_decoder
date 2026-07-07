# TETRA Phase 1 Status

Last updated: 2026-07-07

## Project Context

The project has migrated from the Python DMR/P25/dPMR decoder prototype to the
MATLAB engineering workspace:

```text
/home/lzkj/lzkj_workspace/matlab_docs
```

The previously mentioned path below is not the active project path and currently
does not exist:

```text
/home/lzkj/lzkj_workspace/matlab_dcos
```

Current MATLAB project layout:

```text
+common       IQ reading, sample-rate detection, resampling, DSP utilities
+radio        scan chain, protocol registry, PDU output
+dmr          DMR protocol
+p25          P25 protocol
+dpmr         dPMR protocol
+viz          visualization
examples     example scripts
docs         project documentation
outputs      runtime outputs
```

## Phase 1 Scope

TETRA phase 1 is a visual signal experiment only. It does not implement full
MAC, voice decoding, or protocol-plugin integration yet.

Current processing chain:

```text
IQ -> 72 kHz -> RRC matched filter -> symbol timing ->
pi/4-DQPSK differential decisions -> bit stream ->
training-sequence-assisted sanity check
```

## Added TETRA Files

Directories:

```text
+tetra
examples/tetra
docs/tetra
```

Main functions:

```text
+tetra/config.m
+tetra/rrcTaps.m
+tetra/activeWindow.m
+tetra/coarseFrequencyOffset.m
+tetra/timingSearch.m
+tetra/pi4dqpskDecision.m
+tetra/trainingSequences.m
+tetra/findTrainingSequences.m
+tetra/symbolDebug.m
```

Experiment entry point:

```text
examples/tetra/tetra_symbol_debug.m
```

Run from MATLAB:

```matlab
cd('/home/lzkj/lzkj_workspace/matlab_docs')
startup
run('examples/tetra/tetra_symbol_debug.m')
```

## Visualization Mode

`tetra.symbolDebug` currently defaults to:

```text
ShowFigures=true
SaveFigures=false
```

Running the example script opens ten processing-stage figure windows and does
not save PNG files by default.

To save figures:

```matlab
tetra.symbolDebug(file, 'ShowFigures', true, 'SaveFigures', true)
```

Important interpretation note: `07_symbol_constellation` can appear ring-shaped
when the active window contains multiple bursts, because absolute phase may
drift or reset. For synchronization and decision quality, focus on:

```text
06_timing_metric
08_diff_constellation
10_training_sequence_check
```

## Sample Files

Default DMO sample:

```text
/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/tetra_dmo_20240413_430050000_baseband.wav
```

TMO comparison sample:

```text
/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/TETRA IQ.wav
```

## DMO Acceptance Result

For `tetra_dmo_20240413_430050000_baseband.wav`:

```text
input sample rate:     50000 Hz
processing sample rate: 72000 Hz
active window:         5.177 s - 5.458 s
coarse offset:         +187.9 Hz
residual correction:   +200.0 Hz
best timing phase:     0.75 samples
timing median error:   0.0345 rad
recovered symbols:     5058
recovered bits:        10114
decision variant:      standard
training candidates:   5
good hits:             4
```

Training-sequence observations:

```text
normal_1   0/22 exact hits
normal_2   4/22 candidate hits
normal_3   3/22 good
extended   5/30 good
sync       0/38 exact hits
```

## TMO Comparison Result

For `TETRA IQ.wav`:

```text
timing median error: 0.0498 rad
decision variant:    conjugate
training candidates: 5
good hits:           5
```

## Suggested Next Step

Move into burst and slot boundary detection:

1. Use training-sequence offsets to infer burst starts.
2. Slice 510-bit slot blocks.
3. Distinguish DNB/DSB and normal training sequence 1/2.
4. Prioritize `normal_2` stealing/STCH data.
