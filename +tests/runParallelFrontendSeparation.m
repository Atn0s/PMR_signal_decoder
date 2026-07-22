function runParallelFrontendSeparation()
%RUNPARALLELFRONTENDSEPARATION Verify producer/PSD/DDC/probe independence.
fs = 240000;
centerHz = 20e6;
offsetHz = 40000;
durationSec = 12.0;
count = round(durationSec * fs);
n = (0:count-1).';
iq = 0.35 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
path = [tempname, '.rawiq'];
fileCleanup = onCleanup(@() deleteIfPresent(path));
fid = fopen(path, 'wb'); assert(fid >= 0);
raw = int16(round(32760 .* [real(iq).'; imag(iq).']));
fwrite(fid, raw(:), 'int16'); fclose(fid);

streamCfg = radio.stream.defaultConfig();
streamCfg.ringBufferSec = 2;
streamCfg.lockedSuspectWindows = 1e6;
streamCfg.lockedLostWindows = 1e6;
streamCfg.activity.initialNoiseFloorDb = -50;
streamCfg.activity.minOnSec = 0.03;
streamCfg.activity.offHangSec = 0.06;
hooks = struct( ...
    'taskFcn', @tests.fakeParallelProbeTask, ...
    'taskContext', struct( ...
        'StatusByProtocol', struct('DMR', 'confirmed'), ...
        'DelaySecByProtocol', struct('DMR', 2.00)), ...
    'lockedDecodeFcn', @tests.fakeEmptyLockedDecoder);
app = radio_parallel_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', path, ...
    'SampleRate', fs, ...
    'CenterFrequencyHz', centerHz, ...
    'ReplayMode', 'once', ...
    'MaxLoops', 1, ...
    'ProtocolNames', {'DMR'}, ...
    'NumWorkers', 1, ...
    'StreamConfig', streamCfg, ...
    'TestHooks', hooks, ...
    'Deduplicate', true, ...
    'PrintToCommandWindow', false);
appCleanup = onCleanup(@() app.Close());

app.StartPreview('StartTimer', false);
app.SelectOffsetHz(offsetHz, 'Refine', false);
app.StartDecode();

token = tic;
before = app.GetState();
while toc(token) < 10
    pause(0.05);
    before = app.GetState();
    if strcmp(before.mode, 'ERROR')
        error('tests:parallelFrontendSeparation:Runtime', '%s', ...
            strjoin(before.log, ' | '));
    end
    if ~isempty(before.scanner) && ...
            strcmp(before.scanner.states{1}, 'CLASSIFYING') && ...
            before.spectrum.hasEstimate
        break;
    end
end
assert(before.ddcRingAttached);
assert(strcmp(before.scanner.states{1}, 'CLASSIFYING'));

pause(0.40);
mid = app.GetState();
assert(mid.sourceNextSample > before.sourceNextSample + ...
    uint64(round(0.15 * fs)), ...
    'The input producer waited for the protocol probe.');
assert(mid.spectrum.inputSampleCount > ...
    before.spectrum.inputSampleCount + uint64(round(0.08 * fs)), ...
    'The spectrum consumer waited for the protocol probe.');
assert(isempty(mid.scanner.selectedProtocols{1}));
assert(mid.decoderPipelineQueueSec < 1.0);

token = tic;
while toc(token) < 5
    pause(0.05);
    state = app.GetState();
    if strcmp(state.scanner.selectedProtocols{1}, 'DMR'), break; end
end
state = app.GetState();
assert(strcmp(state.scanner.selectedProtocols{1}, 'DMR'));
assert(state.spectrum.inputSampleCount > 0);
assert(state.meanCoordinatorSec > 0);
pool = gcp('nocreate');
assert(~isempty(pool) && pool.NumWorkers >= 2);

firstEnd = state.sourceNextSample;
app.ClearCarriers();
cleared = app.GetState();
assert(strcmp(cleared.mode, 'PREVIEW'));
assert(cleared.ddcReady && ~cleared.ddcRingAttached);
app.SelectOffsetHz(offsetHz, 'Refine', false);
app.StartDecode();
pause(0.25);
restarted = app.GetState();
assert(restarted.ddcRingAttached);
assert(restarted.sourceNextSample > firstEnd, ...
    'The second decoder attachment rewound or stopped the producer.');
assert(~strcmp(restarted.mode, 'ERROR'));

app.Stop();
stopped = app.GetState();
assert(strcmp(stopped.mode, 'STOPPED') && isempty(stopped.scanner));
app.Close();
clear appCleanup fileCleanup;
fprintf('Parallel frontend separation tests passed.\n');
end

function deleteIfPresent(path)
if exist(path, 'file') == 2, delete(path); end
end
