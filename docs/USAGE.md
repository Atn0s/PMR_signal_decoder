# Usage

The simplest MATLAB workflow is to open one of the top-level scripts, edit the
configuration block at the top, and click Run.

## Script Entrypoints

- `scanner.m`: unified DMR/P25/dPMR/TETRA scanner.
- `dmr_cli.m`: DMR-only scanner.
- `p25_cli.m`: P25-only scanner.
- `dpmr_cli.m`: dPMR-only scanner.
- `tetra_cli.m`: TETRA DMO control scanner.
- `nxdn96_cli.m`: standalone NXDN96 data-PDU decoder; it does not use scanner.
- `examples/tetra/tetra_full_file_scan.m`: TETRA-only full-file multi-window scan.
- `open_radio_analyzer.m`: opens the interactive analyzer UI.

Typical edit:

```matlab
TARGET_FILE = '/path/to/signal.rawiq';
PROTOCOLS = {'dmr'};      % scanner.m only; use {'tetra'} for TETRA DMO
SAMPLE_RATE = [];         % infer from filename, or set 48000 / 78125 / etc.
BLIND_SEARCH = false;     % true for unknown wideband offsets
SHOW_FIGURE = true;
DEDUPLICATE = true;       % false keeps duplicate decoded frames for debugging
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
rawPdus = radio.scanFile('/path/to/signal.rawiq', ...
    'ProtocolNames', {'dpmr'}, ...
    'Deduplicate', false);

result = tetra.scanFileWindows('/path/to/tetra.wav', ...
    'OutputDir', 'outputs/tetra_full_file_scan/manual');

result = viz.analyzeFile('/path/to/signal.rawiq', ...
    'ProtocolNames', {'dmr'}, ...
    'CreateFigure', true);
```

Standalone NXDN96 use:

```matlab
iq = common.readRawIq('signal_data/nxdn96_1_78125.rawiq');
[pdus, report] = nxdn.decodeIq(iq, 78125, nxdn.config());
displayPdus = nxdn.deduplicatePdus(pdus);
for k = 1:numel(displayPdus)
    fprintf('%s\n', nxdn.formatPdu(displayPdus(k)));
end
```

The NXDN96 decoder currently handles non-voice data and control channels. It
records whether VCH is present but does not decode AMBE audio or include VCH
payload in a data PDU. `nxdn.spec` is a dormant compatibility adapter only;
NXDN is not present in `radio.protocolRegistry` and does not change scanner or
blind-search behavior.

TETRA is wired through `radio.scanFile` / `scanner.m` as a separate 72 kHz
windowed-IQ branch. Default wideband blind search still scans only the narrowband
DMR/P25/dPMR branch; pass `ProtocolNames`, or pass `FreqList` for explicit
candidate offsets when TETRA should be considered.

Current dispatch rules:

```text
BlindSearch=true, no ProtocolNames     -> DMR/P25/dPMR only
FreqList set, BlindSearch=false,
no ProtocolNames                       -> DMR/P25/dPMR + TETRA
FreqList set, BlindSearch=true,
no ProtocolNames                       -> DMR/P25/dPMR only (current resolver precedence)
ProtocolNames contains 'tetra'         -> run TETRA unless unsupported
ProtocolNames contains 'tetra' and BlindSearch=true without FreqList
                                      -> error; wideband TETRA blind scan is not implemented
```

`tetra.scanFileWindows` remains the TETRA-only diagnostic entry point. It returns
window reports, envelope information, readable lines, and optional files under
`OutputDir`.

## Future Known-Frequency Protocol Race

The current serial scanner remains the compatibility baseline. The planned
known-frequency multi-protocol probe/race design, MATLAB-versus-Python decision,
branch strategy, and exact blind-search behavior are recorded in:

```text
docs/已知频点多制式并行识别方案.md
```

## JSON Output

`radio.writeJson` matches the Python default and omits `raw_bits` unless
explicitly requested:

```matlab
radio.writeJson(pdus, 'outputs/result.json');
radio.writeJson(pdus, 'outputs/result_with_bits.json', 'IncludeRawBits', true);
```

## Command-Line Smoke Test

```bash
/home/lzkj/matlab/bin/matlab -batch "cd('/home/lzkj/lzkj_workspace/matlab_docs'); startup; tests.runAll"
```

Run only NXDN96 unit and local-sample tests:

```bash
/home/lzkj/matlab/bin/matlab -batch "cd('/home/lzkj/lzkj_workspace/matlab_docs'); startup; tests.runNxdn96"
```

Run the smoke tests plus Python golden-vector comparison:

```bash
/home/lzkj/matlab/bin/matlab -batch "cd('/home/lzkj/lzkj_workspace/matlab_docs'); startup; runGoldenRegression"
```
