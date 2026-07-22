function runParallelFrontendLifecycle()
%RUNPARALLELFRONTENDLIFECYCLE Exercise the parallel-only UI lifecycle.
fs = 240000;
centerHz = 10e6;
offsetHz = 40000;
count = round(2.0 * fs);
n = (0:count-1).';
iq = 0.35 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
path = [tempname, '.rawiq'];
fileCleanup = onCleanup(@() deleteIfPresent(path));
fid = fopen(path, 'wb'); assert(fid >= 0);
raw = int16(round(32767 .* [real(iq).'; imag(iq).']));
fwrite(fid, raw(:), 'int16'); fclose(fid);

streamCfg = radio.stream.defaultConfig();
streamCfg.ringBufferSec = 2;
streamCfg.activity.initialNoiseFloorDb = -40;
streamCfg.activity.minOnSec = 0.03;
streamCfg.activity.offHangSec = 0.06;
spectrumCfg = radio.scope.defaultConfig();
spectrumCfg.nfft = 4096;
spectrumCfg.updateIntervalSec = 0.04;
spectrumCfg.maxDisplayBins = 1024;
hooks = struct( ...
    'taskFcn', @tests.fakeParallelProbeTask, ...
    'taskContext', struct( ...
        'StatusByProtocol', struct('DMR', 'confirmed')), ...
    'lockedDecodeFcn', @tests.fakeLockedDecoder);
app = radio_parallel_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', path, ...
    'SampleRate', fs, ...
    'CenterFrequencyHz', centerHz, ...
    'ReplayMode', 'once', ...
    'MaxLoops', 1, ...
    'ProtocolNames', {'DMR'}, ...
    'NumWorkers', 1, ...
    'SpectrumConfig', spectrumCfg, ...
    'StreamConfig', streamCfg, ...
    'TestHooks', hooks, ...
    'PrintToCommandWindow', false);
appCleanup = onCleanup(@() app.Close());

timers = timerfindall('Name', 'PMRParallelLiveReplay');
assert(~isempty(timers));
assert(any(strcmp(get(timers, 'ExecutionMode'), 'fixedRate')));
app.StartPreview('StartTimer', false);
preview = app.Step(35);
for attempt = 1:50
    if preview.spectrum.hasEstimate, break; end
    pause(0.01);
    preview = app.Step(1);
end
assert(preview.spectrum.hasEstimate, ...
    'The background spectrum actor did not publish an estimate.');
app.SelectOffsetHz(offsetHz, 'Refine', true);
app.StartDecode('StartTimer', false);
attached = app.GetState();
assert(attached.sourceNextSample == preview.sourceNextSample, ...
    'Starting decode must not reopen or rewind the source.');

app.Step(5);
beforeClear = app.GetState();
app.ClearCarriers();
cleared = app.GetState();
assert(isempty(cleared.selections) && isempty(cleared.scanner));
assert(strcmp(cleared.mode, 'PREVIEW'));
assert(cleared.sourceNextSample == beforeClear.sourceNextSample);
afterClear = app.Step(5);
assert(afterClear.sourceNextSample > cleared.sourceNextSample);

app.SelectOffsetHz(offsetHz, 'Refine', true);
beforeSecondRun = app.GetState();
app.StartDecode('StartTimer', false);
afterSecondRun = app.GetState();
assert(afterSecondRun.sourceNextSample == ...
    beforeSecondRun.sourceNextSample);
state = app.Step(100);
assert(strcmp(state.mode, 'COMPLETED'));
assert(state.scanner.channelCount == 1);
assert(strcmp(state.scanner.selectedProtocols{1}, 'DMR'));
assert(~isempty(state.pdus));
assert(state.pdus(1).extra.tuned.channel_id == uint64(1));
assert(state.decoderPipelineQueueSec == 0);

delete(app.Figure);
app.Close();
clear appCleanup fileCleanup;
fprintf('Parallel frontend lifecycle tests passed.\n');
end

function deleteIfPresent(path)
if exist(path, 'file') == 2, delete(path); end
end
