function runRealtimeFrontendPhase6()
%RUNREALTIMEFRONTENDPHASE6 Exercise the lean multi-carrier UI controller.
fs = 240000;
centerHz = 10e6;
offsetHz = 40000;
count = round(2.0 * fs);
n = (0:count-1).';
iq = 0.35 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
path = [tempname, '.rawiq'];
cleanup = onCleanup(@() deleteIfPresent(path));
fid = fopen(path, 'wb'); assert(fid >= 0);
raw = int16(round(32767 .* [real(iq).'; imag(iq).']));
fwrite(fid, raw(:), 'int16'); fclose(fid);

streamCfg = radio.stream.defaultConfig();
streamCfg.ringBufferSec = 2;
streamCfg.activity.initialNoiseFloorDb = -40;
streamCfg.activity.minOnSec = 0.03;
streamCfg.activity.offHangSec = 0.06;
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
app = radio_live_frontend('Visible', 'off', 'DefaultFile', path, ...
    'SampleRate', fs, 'CenterFrequencyHz', centerHz, ...
    'ReplayMode', 'once', 'MaxLoops', 1, ...
    'ProtocolNames', {'DMR'}, 'ParallelMode', 'serial', ...
    'StreamConfig', streamCfg, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeLockedDecoder, ...
    'WarmParallelPool', false, ...
    'PrintToCommandWindow', false);
appCleanup = onCleanup(@() app.Close());
app.StartPreview('StartTimer', false);
previewState = app.Step(35);
app.AddOffsetHz(offsetHz, 'Refine', true);
app.RunIdentification('StartTimer', false);
runState = app.GetState();
assert(runState.sourceNextSample == previewState.sourceNextSample, ...
    'Run Decode must attach without reopening or rewinding the file source.');
app.Step(5);
beforeClear = app.GetState();
app.ClearCarriers();
afterClear = app.GetState();
assert(isempty(afterClear.selections) && isempty(afterClear.scanner));
assert(strcmp(afterClear.mode, 'PREVIEW'));
assert(afterClear.sourceNextSample == beforeClear.sourceNextSample);
afterClearStep = app.Step(5);
assert(afterClearStep.sourceNextSample > afterClear.sourceNextSample, ...
    'Clearing carriers must leave spectrum replay able to continue.');

app.AddOffsetHz(offsetHz, 'Refine', true);
beforeSecondRun = app.GetState();
app.RunIdentification('StartTimer', false);
afterSecondRun = app.GetState();
assert(afterSecondRun.sourceNextSample == beforeSecondRun.sourceNextSample);
state = app.Step(100);
assert(strcmp(state.mode, 'COMPLETED'));
assert(state.scanner.channelCount == 1);
assert(strcmp(state.scanner.selectedProtocols{1}, 'DMR'));
assert(~isempty(state.pdus));
assert(state.pdus(1).extra.tuned.channel_id == uint64(1));
delete(app.Figure); % DeleteFcn must clean the timer without CloseRequestFcn.
app.Close();         % Closing an already deleted/stale figure is idempotent.
clear appCleanup cleanup;
fprintf('Realtime frontend phase-6 lean UI tests passed.\n');
end

function deleteIfPresent(path)
if exist(path, 'file') == 2, delete(path); end
end
