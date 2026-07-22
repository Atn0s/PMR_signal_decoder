# MATLAB Multi-Protocol Radio Decoder

Native MATLAB decoder for DMR, P25 Phase 1, dPMR, NXDN96, and TETRA DMO.
The production path is parallel-only: protocol probes run in a process pool,
known carriers use stateful DDC, and live multi-carrier replay uses a shared IQ
ring plus one fused DDC worker. There is no Python decoder bridge or serial
execution fallback.

Project guides, architecture notes, protocol references, and validation records
are organized in the [documentation index](docs/README.md).

## Supported Entrypoints

The real-time UI entry is:

```matlab
cd('/home/lzkj/lzkj_workspace/matlab_docs')
startup
radio_parallel_frontend
```

It replays BVSP, interleaved raw IQ, or stereo IQ WAV at 1x, displays live PSD,
accepts up to five carrier selections, and runs an independent five-protocol
race for every selected carrier.

The offline file entry is:

```matlab
[pdus, report] = radio.scanFile('/path/to/centered.rawiq', ...
    'ExecutionMode', 'parallel', ...
    'ProtocolNames', {});
```

Use `ExecutionMode='tuned-parallel'` plus one relative `FreqList` value for a
known carrier in wideband IQ, or `ExecutionMode='wideband'` for streaming
WOLA/PFB carrier discovery:

```matlab
[pdus, report] = radio.scanFile('/path/to/capture.bvsp', ...
    'ExecutionMode', 'tuned-parallel', ...
    'FreqList', 1235200);

[pdus, report] = radio.scanFile('/path/to/wideband.rawiq', ...
    'ExecutionMode', 'wideband', ...
    'SampleRate', 61.44e6, ...
    'CenterFrequencyHz', 430e6);
```

Protocol-specific diagnostics live under their packages and `examples/`;
`viz.analyzeFile` is an optional plotting helper rather than another decoder
entrypoint.

## Runtime Model

- A process pool is required; unavailable or undersized pools are reported as
  errors instead of changing execution semantics.
- `parallel` expects one already-centered complex baseband channel.
- `tuned-parallel` performs stateful NCO mixing, anti-alias filtering, and
  integer decimation before the protocol race.
- `wideband` performs streaming 2x-oversampled WOLA/PFB discovery and creates a
  protocol race for every active carrier.
- DMR/P25/dPMR/NXDN use their native 4FSK paths; TETRA uses its native
  pi/4-DQPSK path.

Programmatic live-frontend control is available for tests and automation:

```matlab
app = radio_parallel_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', '/path/to/capture.bvsp', ...
    'ReplayMode', 'once');
cleanup = onCleanup(@() app.Close());

app.StartPreview('StartTimer', false);
app.Step(8);
app.SelectOffsetHz(-300e3, 'Refine', false);
app.SelectOffsetHz(+150e3, 'Refine', false);
app.StartDecode('StartTimer', false);
state = app.Step(500);
```

`Visible='off'` hides the MATLAB view for automation; processing state is
implemented by the UI-independent `radio.live.parallelSession*` functions.

## Tests and Samples

Run the regression suite with:

```matlab
tests.runAll
```

Optional external IQ samples are located through `RADIO_SAMPLE_DATA_ROOT`.
The default is this repository's `signal_data/` directory.
Stored JSON files under `golden/` are historical reference vectors; generating
or decoding through the former Python project is no longer part of this repo.

The deterministic five-carrier stress fixture can be built with:

```matlab
synthesizeFiveSignal2p5MHz('Overwrite', true)
```

Run `tests.runFiveSignal2p5MHzAcceptance` for the corresponding opt-in
multi-carrier acceptance test.

## Layout

```text
+common/          IQ I/O, sample-rate detection, DSP helpers
+radio/           parallel pipeline, registry, PDU formatting and JSON output
+radio/+live/     shared-ring producer, spectrum/DDC actors, live sessions
+radio/+stream/   RF Epoch, protocol race, catch-up, locked decode
+radio/+tuned/    known-carrier DDC and multi-carrier scanner
+radio/+wideband/ WOLA/PFB discovery and fine-channel routing
+dmr/ +p25/ +dpmr/ +nxdn/ +tetra/  native protocol implementations
+viz/             optional MATLAB diagnostic visualization
+tests/           MATLAB regression and acceptance tests
examples/         example scripts
tools/            native MATLAB fixture utilities
docs/             guides, architecture, protocol and validation records
golden/           stored historical reference vectors
```
