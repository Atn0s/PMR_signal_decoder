function runPersistentLockedDecoder()
%RUNPERSISTENTLOCKEDDECODER Verify state ownership inside one worker actor.
existing = gcp('nocreate');
ownsPool = isempty(existing);
if ownsPool
    pool = parpool('Processes', 1);
else
    pool = existing;
end
cleanup = onCleanup(@() cleanupPool(pool, ownsPool));
testActorStartAdmission();

fs = 1000;
epoch = radio.stream.newEpoch(1, 91, 1, 0);
state = radio.stream.lockedDecoderInit('DMR', epoch, fs, ...
    'LastProcessedEndSample', 0, ...
    'DecodeFcn', @tests.fakeLockedDecoder);
state.actor = [];
buffer = radio.stream.ringBufferInit(fs, 2);
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(300, 1)), fs, 0));
input = radio.stream.lockedDecoderPrepareInput(state, buffer);
actor = radio.stream.lockedDecoderActorStart(pool, state, input);
[actor, first] = waitForResult(actor, 15);
assert(first.completed && strcmp(first.state, 'completed'));
assert(first.output.newPduCount == 3);
assert(isempty(first.decoderState.incremental.nativeState));
workerTaskId = actor.workerTaskId;

shadow = first.decoderState;
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(100, 1)), fs, 300, ...
        'SequenceNumber', 1));
input = radio.stream.lockedDecoderPrepareInput(shadow, buffer);
actor = radio.stream.lockedDecoderActorSubmit(actor, input);
[actor, second] = waitForResult(actor, 15);
assert(second.completed && strcmp(second.state, 'completed'));
assert(second.output.newPduCount == 1, ...
    'Worker-local PDU ledger was not retained between actor requests.');
assert(actor.workerTaskId == workerTaskId && workerTaskId > 0);
actor = radio.stream.lockedDecoderActorStop(actor); %#ok<NASGU>
testIntegratedLegacyActors(pool);
testIntegratedNxdn(pool);
clear cleanup;
fprintf('Persistent locked-decoder worker tests passed.\n');
end

function testActorStartAdmission()
fs = 1000;
protocols = {'DMR', 'P25', 'dPMR'};
channels = cell(3, 1);
for k = 1:3
    epoch = radio.stream.newEpoch(k, k, 1, 0);
    state = radio.stream.lockedDecoderInit(protocols{k}, epoch, fs, ...
        'LastProcessedEndSample', 0);
    buffer = radio.stream.ringBufferInit(fs, 2);
    [buffer, ~] = radio.stream.ringBufferPush(buffer, ...
        radio.stream.makeIqChunk(complex(zeros(300, 1)), fs, 0));
    coordinator = struct('state', 'LOCKED', 'activeDecode', [], ...
        'decoderState', state, ...
        'channelController', struct('ringBuffer', buffer), ...
        'options', struct());
    channels{k} = struct('coordinator', coordinator);
end
scanner = struct('channelCount', 3, 'channels', {channels}, ...
    'maxPersistentActorStartsPerFeed', 1, 'feedCount', uint64(0), ...
    'nextPersistentActorStartFeed', uint64(0));
[mask, report] = radio.tuned.multiStreamLockedDecodeDeferrals(scanner);
assert(isequal(mask, logical([0; 1; 1])));
assert(isequal(report.admittedIndices, 1));

scanner.nextPersistentActorStartFeed = uint64(3);
[mask, report] = radio.tuned.multiStreamLockedDecodeDeferrals(scanner);
assert(all(mask) && strcmp(report.reason, 'actor_launch_cooldown'));
scanner.nextPersistentActorStartFeed = uint64(0);

scanner.channels{1}.coordinator.state = 'CATCHING_UP';
[mask, report] = radio.tuned.multiStreamLockedDecodeDeferrals(scanner);
assert(all(mask) && strcmp(report.reason, 'classification_priority'));
end

function testIntegratedLegacyActors(pool)
root = common.sampleDataRoot();
cases = { ...
    'DMR', fullfile(root, 'dmr_1_78125.rawiq'), 78125, 0.5, 1.5; ...
    'P25', fullfile(root, 'p25_1_78125.rawiq'), 78125, 0.0, 1.0; ...
    'dPMR', fullfile(root, 'dpmr_1_48000.rawiq'), 48000, 0.0, 1.5; ...
    'TETRA', fullfile(root, ...
        'tetra_dmo_20240413_430050000_baseband.wav'), 0, 5.0, 0.5};
for k = 1:size(cases, 1)
    protocol = cases{k, 1};
    path = cases{k, 2};
    if exist(path, 'file') ~= 2, continue; end
    fs = cases{k, 3};
    if fs == 0, fs = common.detectSampleRate(path); end
    iq = common.readRawIq(path);
    base = floor(cases{k, 4} * fs);
    count = ceil(cases{k, 5} * fs);
    buffer = radio.stream.ringBufferInit(fs, 3);
    [buffer, ~] = radio.stream.ringBufferPush(buffer, ...
        radio.stream.makeIqChunk(iq(base+1:base+count), fs, uint64(base)));
    epoch = radio.stream.newEpoch(1, 100 + k, 1, uint64(base));
    state = radio.stream.lockedDecoderInit(protocol, epoch, fs, ...
        'LastProcessedEndSample', uint64(base));
    handle = radio.stream.lockedDecoderStart(state, buffer, ...
        'NumWorkers', pool.NumWorkers);
    assert(strcmp(handle.mode, 'persistent_worker'), ...
        '%s did not enter its persistent process actor.', protocol);
    [handle, status] = waitForHandle(handle, 60);
    assert(strcmp(status.state, 'completed'), ...
        '%s actor failed: %s', protocol, status.errorReason);
    allPduCount = status.output.newPduCount;
    nextInput = base + count;
    while ~strcmp(status.output.health.status, 'confirmed') && ...
            nextInput < numel(iq)
        extraCount = min(round(0.25 * fs), numel(iq) - nextInput);
        [buffer, ~] = radio.stream.ringBufferPush(buffer, ...
            radio.stream.makeIqChunk( ...
                iq(nextInput+1:nextInput+extraCount), fs, ...
                uint64(nextInput)));
        handle = radio.stream.lockedDecoderStart( ...
            status.decoderState, buffer, ...
            'NumWorkers', pool.NumWorkers);
        [handle, status] = waitForHandle(handle, 60);
        assert(strcmp(status.state, 'completed'), ...
            '%s actor continuation failed: %s', ...
            protocol, status.errorReason);
        allPduCount = allPduCount + status.output.newPduCount;
        nextInput = nextInput + extraCount;
        if nextInput >= base + count + round(0.75 * fs), break; end
    end
    assert(strcmp(status.output.health.status, 'confirmed'), ...
        '%s actor produced %s evidence.', protocol, ...
        status.output.health.status);
    assert(allPduCount > 0, '%s actor emitted no PDU.', protocol);
    diagnostics = status.output.diagnostics; %#ok<NASGU>
    diagnosticsInfo = whos('diagnostics');
    assert(diagnosticsInfo.bytes < 64 * 1024, ...
        '%s actor returned an oversized diagnostics payload.', protocol);
    assert(radio.getNestedField(diagnostics, ...
        'streamCompacted', false));
    retainedDiagnostics = ...
        status.decoderState.incremental.lastDiagnostics; %#ok<NASGU>
    retainedInfo = whos('retainedDiagnostics');
    assert(retainedInfo.bytes < 64 * 1024, ...
        '%s actor shadow retained oversized diagnostics.', protocol);
    status.decoderState = ...
        radio.stream.lockedDecoderStateRelease(status.decoderState);
end
end

function testIntegratedNxdn(pool)
path = fullfile('signal_data', 'nxdn96_1_78125.rawiq');
if exist(path, 'file') ~= 2, return; end
sourceFs = 78125;
fs = 120000;
sourceIq = common.readRawIq(path);
sourceIq = sourceIq(1:min(numel(sourceIq), round(2.0 * sourceFs)));
iq = common.resampleTo(sourceIq, sourceFs, fs);
base = floor(0.5 * fs);
firstCount = round(1.0 * fs);
secondCount = round(0.2 * fs);
buffer = radio.stream.ringBufferInit(fs, 3);
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk( ...
        iq(base+1:base+firstCount), fs, uint64(base)));
epoch = radio.stream.newEpoch(1, 92, 1, uint64(base));
state = radio.stream.lockedDecoderInit('NXDN', epoch, fs, ...
    'LastProcessedEndSample', uint64(base));
handle = radio.stream.lockedDecoderStart(state, buffer, ...
    'NumWorkers', pool.NumWorkers);
assert(strcmp(handle.mode, 'background_worker'));
[handle, status] = waitForHandle(handle, 30);
assert(strcmp(status.state, 'completed'));
assert(isempty(status.decoderState.actor));
assert(~isempty(status.decoderState.incremental.nativeState));
allPduCount = status.output.newPduCount;
while status.decoderState.lastProcessedEndSample < buffer.endSample
    handle = radio.stream.lockedDecoderStart(status.decoderState, buffer, ...
        'NumWorkers', pool.NumWorkers);
    [handle, status] = waitForHandle(handle, 30);
    assert(strcmp(status.state, 'completed'));
    allPduCount = allPduCount + status.output.newPduCount;
end
assert(allPduCount > 0);

start = base + firstCount;
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk( ...
        iq(start+1:start+secondCount), fs, uint64(start), ...
        'SequenceNumber', 1));
handle = radio.stream.lockedDecoderStart(status.decoderState, buffer, ...
    'NumWorkers', pool.NumWorkers);
[handle, status] = waitForHandle(handle, 30);
assert(strcmp(status.state, 'completed'));
assert(strcmp(handle.mode, 'background_worker'));
assert(status.decoderState.lastProcessedEndSample == ...
    uint64(start + secondCount));
status.decoderState = ...
    radio.stream.lockedDecoderStateRelease(status.decoderState);
assert(isempty(status.decoderState.actor));
end

function [handle, status] = waitForHandle(handle, timeoutSec)
token = tic;
status = struct('state', 'running');
while toc(token) < timeoutSec
    [handle, status] = radio.stream.lockedDecoderPoll(handle);
    if handle.completed, return; end
    pause(0.01);
end
error('tests:runPersistentLockedDecoder:HandleTimeout', ...
    'Integrated persistent decoder did not return before timeout.');
end

function [actor, event] = waitForResult(actor, timeoutSec)
token = tic;
event = struct('completed', false);
while toc(token) < timeoutSec
    [actor, event] = radio.stream.lockedDecoderActorPoll(actor);
    if event.completed, return; end
    pause(0.01);
end
error('tests:runPersistentLockedDecoder:Timeout', ...
    'Persistent decoder actor did not return before timeout.');
end

function cleanupPool(pool, ownsPool)
if ownsPool && ~isempty(pool)
    delete(pool);
end
end
