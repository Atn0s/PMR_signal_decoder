function runRealtimeFrontendPhase4()
%RUNREALTIMEFRONTENDPHASE4 Exercise the hidden UI controller end to end.
fs = 240000;
centerHz = 10e6;
offsetHz = 40000;
durationSec = 0.8;
path = [tempname, '.rawiq'];
writeSyntheticIq(path, fs, durationSec, offsetHz);
fileCleanup = onCleanup(@() deleteIfPresent(path));

spectrumCfg = radio.scope.defaultConfig();
spectrumCfg.nfft = 4096;
spectrumCfg.updateIntervalSec = 0.04;
spectrumCfg.maxWaterfallRows = 12;
spectrumCfg.maxDisplayBins = 1024;
streamCfg = radio.stream.defaultConfig();
streamCfg.ringBufferSec = 2;
streamCfg.activity.initialNoiseFloorDb = -40;
streamCfg.activity.minOnSec = 0.03;
streamCfg.activity.offHangSec = 0.06;
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));

app = radio_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', path, ...
    'SampleRate', fs, ...
    'CenterFrequencyHz', centerHz, ...
    'ReplayMode', 'once', ...
    'MaxLoops', 1, ...
    'ProtocolNames', {'dmr'}, ...
    'ParallelMode', 'serial', ...
    'PrewarmDdc', true, ...
    'WarmParallelPool', false, ...
    'ContinueAfterLockSec', 0.10, ...
    'MaxLogicalDurationSec', 1.0, ...
    'SpectrumConfig', spectrumCfg, ...
    'StreamConfig', streamCfg, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeLockedDecoder);
appCleanup = onCleanup(@() app.Close());

app.StartPreview('StartTimer', false);
preview = app.Step(15);
assert(preview.spectrum.hasEstimate);
assert(preview.spectrum.updateCount >= 1);
assert(~isempty(preview.spectrum.waterfallPsd));

selection = app.SelectFrequencyHz(centerHz + offsetHz, ...
    'Refine', true, 'BandwidthHz', 12500);
assert(abs(selection.offsetHz - offsetHz) < 1500);

app.RunIdentification('StartTimer', false);
decoded = app.Step(70);
assert(any(strcmp(decoded.mode, {'LOCKED','COMPLETED'})));
assert(strcmp(decoded.scanner.selectedProtocol, 'DMR'));
assert(decoded.scanner.feedCount > 0);
assert(~isempty(decoded.pdus));
assert(strcmp(decoded.pdus(1).protocol, 'DMR'));
assert(abs(decoded.pdus(1).extra.tuned.frequency_offset_hz - ...
    selection.offsetHz) < 1e-9);

app.Stop();
stopped = app.GetState();
assert(strcmp(stopped.mode, 'STOPPED'));
clear appCleanup fileCleanup;
fprintf('Realtime frontend phase-4 UI integration tests passed.\n');
end

function writeSyntheticIq(path, sampleRateHz, durationSec, offsetHz)
count = round(sampleRateHz * durationSec);
n = (0:count-1).';
rngState = rng;
rng(4021);
iq = 0.45 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ sampleRateHz) + ...
    0.01 .* (randn(count, 1) + 1i .* randn(count, 1));
rng(rngState);
interleaved = zeros(2 * count, 1, 'int16');
interleaved(1:2:end) = int16(max(-1, min(1, real(iq))) .* 32767);
interleaved(2:2:end) = int16(max(-1, min(1, imag(iq))) .* 32767);
fid = fopen(path, 'wb');
if fid < 0
    error('tests:runRealtimeFrontendPhase4:Open', ...
        'Unable to create temporary IQ capture.');
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, interleaved, 'int16');
clear cleanup;
end

function deleteIfPresent(path)
if exist(path, 'file') == 2, delete(path); end
end
