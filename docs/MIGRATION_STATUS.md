# Migration Status

## Stage 1: MATLAB visualization with Python backend

Implemented.

- Python scanner compatibility backend remains available.
- `pybackend.scanFile` and `tools/python_scan_json.py` return MATLAB structs through JSON.
- `viz.analyzeFile` decodes and plots IQ, PSD, frontend output, and PDU text.
- `+apps/RadioAnalyzer.m` provides a programmatic MATLAB UI.

## Stage 2: Common MATLAB DSP layer

Implemented for the offline path.

- `common.readRawIq`
- `common.detectSampleRate`
- `common.welchPsd`
- `common.resampleTo`
- `common.fskFrontend`
- `radio.psdBlindSearch`
- `radio.processCandidate`
- `radio.processBaseband`

## Stage 3: Protocol package boundary

Implemented as native MATLAB decoders for the current DMR/P25/dPMR/NXDN metadata
surface.

- `+dmr`, `+p25`, `+dpmr`, and `+nxdn` expose config, frontend, decode,
  postprocess, dedup, and formatter functions.
- NXDN96 supports explicit, centered/default, known-frequency and blind-search
  native MATLAB dispatch. The Python compatibility backend does not support NXDN.
- Current golden samples run with `PipelineBackend='matlab'` and `DecoderBackend='matlab'`.
- Python fallback remains available for cross-checking and future protocol work.

## Stage 4: Docs, examples, and app wiring

Implemented.

- `README.md`
- `examples/runAnalyzeSample.m`
- `examples/runGoldenRegression.m`
- `docs/MIGRATION_STATUS.md`

## Stage 5: Golden vector regression

Implemented as field-level regression.

- `tools/build_golden_vectors.py`
- `tools/buildGoldenVectors.m`
- `+tests/goldenRegression.m`
- `examples/runGoldenRegression.m`

Use Python-generated JSON baselines under `golden/current/` to compare native
MATLAB output against the current Python behavior. `golden/raw/` keeps optional
no-dedup Python baselines for debugging duplicate frame recovery.

## 2026-07-09 Incremental Sync

Implemented from the Python `docs/MATLAB增量迁移方案.md` offline scope.

- Added `Deduplicate` through `scanner.m`, protocol CLI scripts, `radio.scanFile`,
  `radio.scanIq`, candidate/baseband decode paths, and the Python fallback bridge.
- Aligned P25 and dPMR semantic dedup keys with Python behavior.
- Added DMR and dPMR call summary PDUs: `DMR_CALL` and `dPMR_CALL`.
- Aligned dPMR stable color filtering, including quality-aware filtering and
  `stable_color_repeats`.
- Added dPMR FS1 header decode path and Python-compatible global sync dedup.
  The current golden dPMR sample has no valid FS1 header output, so this path is
  implemented but still needs broader sample coverage.
- Aligned MATLAB JSON output with Python default behavior by omitting `raw_bits`
  unless `IncludeRawBits=true`.
- Regenerated Python baselines and verified:
  `tests.runAll` plus `tests.goldenRegression()` both pass.

Still outside this migration slice:

- Python `realtime/`, SDR source, channelizer, worker, and realtime aggregator.
- Full okdmr-equivalent DMR FEC/CSBK/link-control coverage.
