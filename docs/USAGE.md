# Usage

The simplest MATLAB workflow is to open one of the top-level scripts, edit the
configuration block at the top, and click Run.

## Script Entrypoints

- `scanner.m`: unified DMR/P25/dPMR/TETRA scanner.
- `dmr_cli.m`: DMR-only scanner.
- `p25_cli.m`: P25-only scanner.
- `dpmr_cli.m`: dPMR-only scanner.
- `tetra_cli.m`: TETRA DMO control scanner.
- `examples/tetra/tetra_full_file_scan.m`: TETRA-only full-file multi-window scan.
- `open_radio_analyzer.m`: opens the interactive analyzer UI.

Typical edit:

```matlab
TARGET_FILE = '/path/to/signal.rawiq';
PROTOCOLS = {'dmr'};      % scanner.m only; use {'tetra'} for TETRA DMO
SAMPLE_RATE = [];         % infer from filename, or set 48000 / 78125 / etc.
BLIND_SEARCH = false;     % true for unknown wideband offsets
SHOW_FIGURE = true;
```

Then click Run. The scripts print decoded PDU lines in the Command Window and
show the diagnostic figure when `SHOW_FIGURE` is true.

The default backend is native MATLAB. The Python compatibility backend is still
available and uses the project conda environment by default:

```text
/home/lzkj/miniconda3/envs/DMR_demo/bin/python
```

If you need another interpreter, set `DMR_DEMO_PYTHON` before launching MATLAB
or pass `PythonExecutable` in programmatic calls.

## Programmatic Entrypoints

```matlab
pdus = radio.scanFile('/path/to/signal.rawiq', 'ProtocolNames', {'dmr'});
pdus = radio.scanFile('/path/to/tetra.wav', 'ProtocolNames', {'tetra'});

result = tetra.scanFileWindows('/path/to/tetra.wav', ...
    'OutputDir', 'outputs/tetra_full_file_scan/manual');

result = viz.analyzeFile('/path/to/signal.rawiq', ...
    'ProtocolNames', {'dmr'}, ...
    'CreateFigure', true);
```

`tetra.scanFileWindows` is a TETRA-only experiment entry point and is not wired
through `scanner.m` yet.

## Command-Line Smoke Test

```bash
/home/lzkj/matlab/bin/matlab -batch "cd('/home/lzkj/lzkj_workspace/matlab_docs'); startup; tests.runAll"
```
