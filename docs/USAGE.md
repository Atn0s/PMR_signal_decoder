# Usage

The simplest MATLAB workflow is to open one of the top-level scripts, edit the
configuration block at the top, and click Run.

## Script Entrypoints

- `scanner.m`: unified DMR/P25/dPMR/NXDN/TETRA scanner.
- `dmr_cli.m`: DMR-only scanner.
- `p25_cli.m`: P25-only scanner.
- `dpmr_cli.m`: dPMR-only scanner.
- `tetra_cli.m`: TETRA DMO control scanner.
- `nxdn96_cli.m`: standalone NXDN96 data-PDU diagnostic decoder.
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

For the offline five-protocol parallel race, the input must already contain one
channel near complex baseband:

```matlab
EXECUTION_MODE = 'parallel';
PROTOCOLS = {};           % races DMR/P25/dPMR/NXDN/TETRA
FREQ_LIST = [];           % already-centered baseband
BLIND_SEARCH = false;     % no PSD candidate search in this entry
```

For one known carrier in a wideband capture, use the tuned transition instead
of PFB discovery:

```matlab
EXECUTION_MODE = 'tuned-parallel';
PROTOCOLS = {};                           % races all five protocols
SAMPLE_RATE = [];                         % BVSP reads this from its header
WIDEBAND_CENTER_FREQUENCY_HZ = 0;         % BVSP reads its RF center too
FREQ_LIST = 1235200;                      % one relative offset in Hz
BLIND_SEARCH = false;
SHOW_FIGURE = false;
```

This path reads the wideband file in 10 ms blocks, performs stateful NCO down
conversion plus anti-alias filtering, decimates to 120 kS/s, and then uses the
existing multi-Epoch five-protocol race. The current phase accepts one carrier;
it does not perform carrier discovery or time cropping.

For streaming discovery in a wideband recording:

```matlab
EXECUTION_MODE = 'wideband';
PROTOCOLS = {};                         % race all five per active carrier
SAMPLE_RATE = 61.44e6;                  % actual SDR complex sample rate
FREQ_LIST = [];                         % wideband mode discovers carriers
BLIND_SEARCH = false;                   % legacy PSD blind search is not used
WIDEBAND_CENTER_FREQUENCY_HZ = 430e6;   % actual SDR tuning frequency
SHOW_FIGURE = false;                    % avoids whole-file loading
```

The wideband path reads 10 ms file chunks, runs a continuous 2x-oversampled
WOLA/PFB, tracks fine-frequency candidates, and creates one existing
`RaceCoordinator` per routed carrier. It is currently a correctness and file-
replay implementation. The MATLAB CPU PFB has not yet reached real time at
61.44 MS/s; see `docs/60MHz宽带实时IQ信道化与并行解码设计.md` for the measured
baseline and acceleration plan.

The parallel path first splits the centered file into independent RF Epochs.
Continuous power below the off threshold for `offHangSec` (300 ms by default)
closes the current Epoch; later activity always creates a new Epoch, even when
it decodes to the same transmitter. Each Epoch independently races the enabled
protocols and the winner decodes only that Epoch from its pre-trigger region.
PDU de-duplication is local to an Epoch, and no cross-Epoch Session is created.

A five-worker process pool is used because the current decoders include
MEX/toolbox operations that are not thread-pool safe. If a process pool cannot
be created, the report records `serial_fallback` rather than silently changing
the decoded result.

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
[pdus, report] = radio.scanFile('/path/to/centered_78125.rawiq', ...
    'ExecutionMode', 'parallel', ...
    'BlindSearch', false);
for k = 1:report.epochCount
    fprintf('Epoch %d: %s, samples [%d,%d), PDUs=%d\n', ...
        report.epochs(k).epochId, report.epochs(k).protocol, ...
        report.epochs(k).candidateStartSample, ...
        report.epochs(k).endSample, report.epochs(k).pduCount);
end
[tunedPdus, tunedReport] = radio.scanFile('/path/to/capture.bvsp', ...
    'ExecutionMode', 'tuned-parallel', ...
    'FreqList', 1235200, ...
    'ProtocolNames', {});
[widebandPdus, widebandReport] = radio.scanFile( ...
    '/path/to/capture_61440000.rawiq', ...
    'ExecutionMode', 'wideband', ...
    'SampleRate', 61.44e6, ...
    'CenterFrequencyHz', 430e6);
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
payload in a data PDU. `nxdn.spec` is registered in `radio.protocolRegistry`;
explicit, centered/default, known-frequency and blind-search scanner paths all
support NXDN through the native MATLAB backend.

TETRA is wired through `radio.scanFile` / `scanner.m` as a separate 72 kHz
windowed-IQ branch. Default wideband blind search still scans only the narrowband
DMR/P25/dPMR/NXDN branch; pass `ProtocolNames`, or pass `FreqList` for explicit
candidate offsets when TETRA should be considered.

Blind-search PSD detection integrates power across a 4.8 kHz modulation window
before selecting candidates. This prevents the multiple spectral lines of one
DMR/P25/dPMR/NXDN carrier from being decoded repeatedly as separate radios while
retaining separate candidates at the standard 6.25 kHz channel spacing.
`scanner.m` prints candidate progress; library calls remain quiet unless
`ShowProgress=true` is passed.

Current dispatch rules:

```text
BlindSearch=true, no ProtocolNames     -> DMR/P25/dPMR/NXDN
FreqList set, BlindSearch=false,
no ProtocolNames                       -> DMR/P25/dPMR/NXDN + TETRA
FreqList set, BlindSearch=true,
no ProtocolNames                       -> DMR/P25/dPMR/NXDN (current resolver precedence)
ProtocolNames contains 'nxdn'          -> run native MATLAB NXDN96 decoder
ProtocolNames contains 'tetra'         -> run TETRA unless unsupported
ProtocolNames contains 'tetra' and BlindSearch=true without FreqList
                                      -> error in the legacy serial scanIq path
ExecutionMode='wideband', FreqList=[] -> WOLA/PFB discovery, then all enabled
                                         protocols including TETRA race per carrier
ExecutionMode='tuned-parallel', one FreqList value
                                      -> known-carrier DDC to 120 kS/s, then all
                                         enabled protocols including TETRA
```

`tetra.scanFileWindows` remains the TETRA-only diagnostic entry point. It returns
window reports, envelope information, readable lines, and optional files under
`OutputDir`.

## Known-Frequency Protocol Race

The serial scanner remains the default compatibility baseline. The first
offline protocol-race integration is available through
`ExecutionMode='parallel'` for a single already-centered baseband file. A
single known carrier in a wideband file can now use
`ExecutionMode='tuned-parallel'`; nonzero single-element `FreqList` also routes
there automatically. Neither path performs PSD carrier discovery,
multiple-frequency scheduling, or direct SDR acquisition. The broader
streaming design and exact blind-search behavior
are recorded in:

```text
docs/已知频点多制式并行识别方案.md
docs/实时微批处理五制式并行识别架构设计.md
docs/离线基带并行接入scanner实现记录.md
docs/离线多Epoch识别与上报实现记录.md
docs/已知载频DDC过渡模块实现记录.md
docs/实时频谱选频与循环回放解码前端设计.md
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
