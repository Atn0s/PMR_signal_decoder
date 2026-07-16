function runRealtimeFrontendPhase7()
%RUNREALTIMEFRONTENDPHASE7 Verify independent producer/PSD/decode consumers.
fs = 240000;
centerHz = 20e6;
offsetHz = 40000;
durationSec = 12.0;
count = round(durationSec * fs);
n = (0:count-1).';
iq = 0.35 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
path = [tempname, '.rawiq'];
cleanup = onCleanup(@() deleteIfPresent(path));
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
context = struct( ...
    'StatusByProtocol', struct('DMR', 'confirmed'), ...
    'DelaySecByProtocol', struct('DMR', 2.00));
app = radio_live_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', path, ...
    'SampleRate', fs, ...
    'CenterFrequencyHz', centerHz, ...
    'ReplayMode', 'once', ...
    'MaxLoops', 1, ...
    'ProtocolNames', {'DMR'}, ...
    'ParallelMode', 'parallel', ...
    'NumWorkers', 1, ...
    'FrontendWorkerReserve', 1, ...
    'StreamConfig', streamCfg, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeEmptyLockedDecoder, ...
    'Deduplicate', true, ...
    'PrintToCommandWindow', false);
appCleanup = onCleanup(@() app.Close());

app.StartPreview('StartTimer', false);
app.AddOffsetHz(offsetHz, 'Refine', false);
app.RunIdentification();

% Wait for the deliberately slow classification to start.  Actor startup
% is intentionally not assigned a fixed cold-start deadline.
token = tic;
before = app.GetState();
while toc(token) < 10
    pause(0.05);
    before = app.GetState();
    if strcmp(before.mode, 'ERROR')
        error('tests:realtimeFrontendPhase7:Runtime', '%s', ...
            strjoin(before.log, ' | '));
    end
    if ~isempty(before.scanner) && ...
            strcmp(before.scanner.states{1}, 'CLASSIFYING') && ...
            before.spectrum.hasEstimate
        break;
    end
end
assert(before.asyncFrontend);
assert(before.sharedIqRing && before.ddcRingAttached, ...
    'The decoder did not attach to the cross-process IQ ring.');
assert(before.producerQueueSec == 0, ...
    'Wideband IQ is still being relayed through the UI/client queue.');
assert(strcmp(before.scanner.states{1}, 'CLASSIFYING'), ...
    ['Decoder=%s, source=%.3f s, spectrum=%.3f s, feeds=%d, ', ...
     'DDC pending=%.3f s, ready=%d, processed=%d, terminal=%d.'], ...
    before.scanner.states{1}, ...
    double(before.sourceNextSample) / fs, ...
    double(before.spectrum.inputSampleCount) / fs, ...
    double(before.scanner.feedCount), before.decoderQueueSec, ...
    before.ddcReady, before.ddcProcessedSamples, ...
    before.sourceTerminal);

% The only protocol worker is now occupied for two seconds.  File
% production and PSD must nevertheless keep advancing while no winner
% exists.
pause(0.40);
mid = app.GetState();
assert(mid.sourceNextSample > before.sourceNextSample + ...
    uint64(round(0.15 * fs)), ...
    'The input producer waited for the protocol probe.');
assert(mid.spectrum.inputSampleCount > ...
    before.spectrum.inputSampleCount + uint64(round(0.08 * fs)), ...
    'The spectrum consumer waited for the protocol probe.');
assert(isempty(mid.scanner.selectedProtocols{1}), ...
    'The delayed probe unexpectedly completed before separation was tested.');
assert(mid.producerQueueSec == 0 && mid.decoderQueueSec < 1.0, ...
    'The separated consumers accumulated an unexpected client IQ queue.');

token = tic;
while toc(token) < 5
    pause(0.05);
    state = app.GetState();
    if strcmp(state.scanner.selectedProtocols{1}, 'DMR'), break; end
end
state = app.GetState();
assert(strcmp(state.scanner.selectedProtocols{1}, 'DMR'));
assert(state.spectrum.inputSampleCount > 0);
assert(state.meanAsyncCoordinatorSec > 0);
pool = gcp('nocreate');
assert(~isempty(pool) && pool.NumWorkers >= 2, ...
    'The async frontend did not reserve a DDC process worker.');

% Clearing a carrier detaches and resets the same prewarmed DDC actor.  A
% second Run must attach at the current live edge without cold rebuilding,
% rewinding, or reintroducing the client IQ relay.
firstEnd = state.sourceNextSample;
app.ClearCarriers();
cleared = app.GetState();
assert(strcmp(cleared.mode, 'PREVIEW') && cleared.ddcReady && ...
    ~cleared.ddcRingAttached);
app.AddOffsetHz(offsetHz, 'Refine', false);
app.RunIdentification();
pause(0.25);
restarted = app.GetState();
assert(restarted.ddcRingAttached && restarted.producerQueueSec == 0);
assert(restarted.sourceNextSample > firstEnd, ...
    'The second decoder attachment rewound or stopped the producer.');
assert(~strcmp(restarted.mode, 'ERROR'), ...
    'The reusable DDC actor failed during second attachment.');

app.Stop();
stopped = app.GetState();
assert(strcmp(stopped.mode, 'STOPPED') && isempty(stopped.scanner));
app.Close();
clear appCleanup cleanup;
fprintf('Realtime frontend phase-7 separated pipeline tests passed.\n');
end

function deleteIfPresent(path)
if exist(path, 'file') == 2, delete(path); end
end
