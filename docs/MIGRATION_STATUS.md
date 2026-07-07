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

Implemented as native MATLAB decoders for the current DMR/P25/dPMR metadata
surface.

- `+dmr`, `+p25`, and `+dpmr` expose config, frontend, decode, postprocess, dedup, and formatter functions.
- Current golden samples run with `PipelineBackend='matlab'` and `DecoderBackend='matlab'`.
- Python fallback remains available for cross-checking and future protocol work.

## Stage 4: Docs, examples, and app wiring

Implemented.

- `README.md`
- `examples/runAnalyzeSample.m`
- `examples/runGoldenRegression.m`
- `docs/MIGRATION_STATUS.md`

## Stage 5: Golden vector regression

Implemented as tooling.

- `tools/build_golden_vectors.py`
- `tools/buildGoldenVectors.m`
- `tests.runAll`

Use Python-generated JSON baselines under `golden/current/` to compare future
native MATLAB protocol ports against the current Python behavior.
