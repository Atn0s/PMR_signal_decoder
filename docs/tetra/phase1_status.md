# TETRA Phase 1 Status

Last updated: 2026-07-09

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
training-sequence-assisted sanity check ->
DMO DSB/DNB burst confirmation -> BKN1/BKN2 payload extraction
-> SCH/S + SCH/H channel decode -> full DMAC-SYNC parse
-> FN/TN timing assignment -> DCC context
-> normal_2 STCH decode -> normal_1 SCH/F attempt or TCH candidate
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
+tetra/slotLayouts.m
+tetra/inferSlotCandidates.m
+tetra/dmoBurstDefinitions.m
+tetra/classifyDmoBurst.m
+tetra/extractDmoPayload.m
+tetra/scramblingSequence.m
+tetra/blockInterleave.m
+tetra/blockDeinterleave.m
+tetra/dmoBlockCodeParity.m
+tetra/rcpcDecodeRate23.m
+tetra/intToBits.m
+tetra/dmoDcc.m
+tetra/decodeDmoSignallingBlock.m
+tetra/parseDmacSyncSchS.m
+tetra/parseDmacSync.m
+tetra/parseDmoMessageElements.m
+tetra/parseDmoMacPdu.m
+tetra/pdusFromSlotReport.m
+tetra/spec.m
+tetra/frontend.m
+tetra/decode.m
+tetra/postprocess.m
+tetra/dedupKey.m
+tetra/formatPdu.m
+tetra/decodeSchS.m
+tetra/inferDmoBursts.m
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

Running the example script opens thirteen processing-stage figure windows and does
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
11_slot_candidates
12_frequency_correction_check
13_transition_validity
```

`11_slot_candidates` now shows confirmed DMO bursts and extracted BKN payload
regions. In the longer debug window it also includes a full-window burst
overview so the next synchronization sequence and later DNB payloads are visible.
The filename is kept for compatibility with earlier debug output.
`12_frequency_correction_check` verifies the DSB frequency-correction field by
comparing observed differential-symbol frequencies against the expected
`-6.75 kHz / +2.25 kHz / -6.75 kHz` pattern.
`13_transition_validity` validates the Fig8 low-energy mask against confirmed
burst spans. In the current DMO long-window sample, 96.2 % of transitions inside
confirmed bursts are timing-valid, while only 0.2 % outside confirmed bursts are
timing-valid.

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
active window:         5.177 s - 7.638 s
long debug span:       2.461 s
coarse offset:         +320.8 Hz
residual correction:   +100.0 Hz
best timing phase:     0.75 samples
timing median error:   0.0554 rad
recovered symbols:     44298 in long debug window
recovered bits:        88594 in long debug window
decision variant:      standard
training candidates:   5
good hits:             5
DMO candidates:        434
complete candidates:   430
confirmed DMO bursts:  62
confirmed DSB:         38
confirmed DNB:         24
payload blocks:        124
SCH/S decoded:         38
SCH/H decoded:         38
DMAC-SYNC decoded:     38
DCC contexts:          38
MAC blocks:            28
STCH decoded:          6
SCH/F decoded:         0
radio.scanFile PDUs:   68 TETRA events/sessions
timing assigned:       62
frequency correction:  38 DSB fields, median abs error 59.1 Hz
```

Decoded SCH/S timing in the default DMO sample:

```text
first DSB run:   FN6 TN1 through FN9 TN4
following DNBs:  normal_1 at FN10 TN1, FN11 TN1, FN12 TN1
then:            DSB at FN12 TN3, DNB normal_2 at FN13 TN1
then:            DNB normal_1 at FN14 TN1 through FN17 TN1
FN18 area:       DSB at FN18 TN1 and FN18 TN3, then DNB across FN1/FN2/FN3/FN4
next DSB run:    FN15 TN1 through FN18 TN4
later DNBs:      normal_1/normal_2 continue after the second DSB run
SCH/S PDU: DMAC-SYNC, direct MS-MS, channel A normal mode, DM-1 no AI encryption
SCH/S checks: blockErr=0, tailErr=0, RCPC metric=0 for all 38 decoded DSBs
SCH/H checks: blockErr=0, tailErr=0, RCPC metric=0 for all 38 decoded DSBs
complete DMAC-SYNC: DM-SETUP, DM-OCCUPIED, and DM-RELEASE observed
DCC: generated from MNI low 6 bits plus source address for each valid DSB
normal_2 STCH: decoded DM-INFO and DM-RELEASE examples
normal_1 SCH/F: attempted; current sample normal_1 blocks fail SCH/F checks and
therefore remain TCH candidates
unified output: radio.scanFile(..., 'ProtocolNames', {'tetra'}) prints
TETRA_DMAC_SYNC, TETRA_STCH, TETRA_TCH_CANDIDATE, and TETRA_SESSION records
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

## Current Decode Boundary

`tetra.inferDmoBursts` currently uses DMO training offsets and fixed DMO field
checks to confirm DSB/DNB slots, then performs DMO control-channel decoding:

1. `sync` implies a DSB hypothesis with the synchronization training sequence at
   slot bit 249.
2. `normal_1` and `normal_2` imply DNB hypotheses with the normal training
   sequence at slot bit 265.
3. Confirmed DSB blocks export `BKN1/SCH-S` with 120 bits and `BKN2/SCH-H`
   with 216 bits.
4. Confirmed DNB blocks export `BKN1` and `BKN2`, each 216 bits. `normal_1`
   hints `TCH or SCH/F`; `normal_2` hints `STCH` in block 1 and `TCH or STCH`
   in block 2.
5. Confirmed DSB `BKN1/SCH-S` and `BKN2/SCH-H` are decoded through
   descrambling, block deinterleaving, RCPC rate 2/3 Viterbi decoding,
   block-code checking, and type-1 bit extraction.
6. SCH/S + SCH/H are combined into the full DMAC-SYNC PDU. The parser extracts
   communication type, AB usage, frame/slot, encryption state, source and
   destination addressing, MNI, message type, frame countdown, common
   message-dependent fields, and retained DM-SDU raw bits.
7. A 30-bit DCC is generated as `MNI low 6 bits + source address 24 bits`.
8. Confirmed DNB `normal_2` BKN1 is decoded as STCH. If its MAC header says the
   second half slot is stolen, BKN2 is also decoded as STCH; otherwise BKN2 is
   retained as a TCH candidate.
9. Confirmed DNB `normal_1` combines BKN1+BKN2 and attempts SCH/F decoding. If
   SCH/F block/tail checks fail, the burst is retained as a TCH candidate and is
   not misreported as SCH/F.

TCH/VOICE decoding is intentionally not implemented in this phase. TCH payload
collection, speech/data channel decode, encryption handling, and codec payload
extraction remain the next boundary.

Next technical step:

1. Add a DMO call-state layer that groups DM-SETUP, DM-OCCUPIED, STCH, release,
   and TCH candidates into one traffic session.
2. Extend active-window processing to scan multiple active segments or a longer
   continuous interval once timing assignment is stable.
3. After the control path is stable, add TCH/VOICE payload collection and decode.

Detailed current workflow documentation:

```text
docs/tetra/current_decode_workflow.md
```

TETRA documentation index:

```text
docs/tetra/README.md
```

Link-layer decode plan:

```text
docs/tetra/link_layer_decode_plan.md
```
