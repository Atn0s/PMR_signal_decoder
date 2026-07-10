# MATLAB Multi-Protocol Radio Decoder

This directory is a staged MATLAB migration of the existing Python radio
decoder project at:

```text
/home/lzkj/lzkj_workspace/python_docs/DMR_demo
```

The current default path is native MATLAB for IQ loading, sample-rate detection,
PSD candidate search, DDC/resampling, FSK frontends, and DMR/P25/dPMR/NXDN metadata
decode. The proven Python decoders remain available as an explicit fallback.

## Quick Start

From MATLAB:

```matlab
cd('/home/lzkj/lzkj_workspace/matlab_docs')
startup
scanner
```

For the click-to-run workflow, open one of these top-level scripts, edit
`TARGET_FILE`, then click Run:

```text
scanner.m
dmr_cli.m
p25_cli.m
dpmr_cli.m
nxdn96_cli.m
open_radio_analyzer.m
```

The scanner scripts print decoded PDU lines in the Command Window and show a
diagnostic figure when `SHOW_FIGURE = true`.

Programmatic use:

```matlab

result = viz.analyzeFile('/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/dmr_1_78125.rawiq', ...
    'ProtocolNames', {'dmr'});

pdus = radio.scanFile('/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/p25_1_78125.rawiq', ...
    'ProtocolNames', {'p25'});
```

To open the programmatic UI:

```matlab
apps.RadioAnalyzer
```

To run the MATLAB smoke/regression entry point:

```matlab
tests.runAll
```

## Backend Model

`radio.scanFile(...)` defaults to `PipelineBackend='matlab'` and
`DecoderBackend='matlab'`.

`radio.scanFile(..., 'PipelineBackend', 'python')` delegates the whole decode
flow to the current Python scanner as a compatibility fallback.

Native MATLAB protocol frontends are available through:

```matlab
y = dmr.frontend(iq, 48000);
y = p25.frontend(iq, 48000);
y = dpmr.frontend(iq, 48000);
```

NXDN96 is available through both its standalone data-only decoder and the
unified scanner:

```matlab
iq = common.readRawIq('signal_data/nxdn96_1_78125.rawiq');
[pdus, report] = nxdn.decodeIq(iq, 78125, nxdn.config());

pdus = radio.scanFile('signal_data/nxdn96_1_78125.rawiq', ...
    'ProtocolNames', {'nxdn'});
```

Open `nxdn96_cli.m` for the click-to-run entry. It decodes LICH, SACCH,
FACCH1, CAC, UDCH/FACCH2 and Layer-3 data; VCH voice payload is not decoded or
emitted as a data PDU.

Native protocol decode is implemented behind each protocol package. Python
fallback remains useful when comparing behavior while adding new protocols.

## Python Bridge

The bridge uses `tools/python_scan_json.py` and the Python executable from:

1. The `PythonExecutable` option, if provided.
2. The `DMR_DEMO_PYTHON` environment variable.
3. `/home/lzkj/miniconda3/envs/DMR_demo/bin/python`, when present.
4. `python3`.

The Python project root is resolved from:

1. The `PythonRoot` option, if provided.
2. The `DMR_DEMO_PYTHON_ROOT` environment variable.
3. `/home/lzkj/lzkj_workspace/python_docs/DMR_demo`.

## Layout

```text
+common/      IQ IO, sample-rate detection, DSP helpers
+radio/       pipeline, registry, PDU formatting and JSON output
+dmr/         DMR config/frontend/formatting adapter
+p25/         P25 config/frontend/formatting adapter
+dpmr/        dPMR config/frontend/formatting adapter
+nxdn/        NXDN96 non-voice decoder and scanner adapter
+pybackend/   Python compatibility backend
+viz/         MATLAB visualization workflow
+tests/       MATLAB regression/smoke tests
+apps/        Programmatic MATLAB UI
examples/      Example scripts
tools/         Python and MATLAB helper scripts
docs/          Migration notes
golden/        Generated Python baseline vectors
```
