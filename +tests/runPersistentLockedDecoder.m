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
testIntegratedNxdn(pool);
clear cleanup;
fprintf('Persistent locked-decoder worker tests passed.\n');
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
    'Mode', 'parallel', 'NumWorkers', pool.NumWorkers, ...
    'PoolType', 'processes');
assert(strcmp(handle.mode, 'background_worker'));
[handle, status] = waitForHandle(handle, 30);
assert(strcmp(status.state, 'completed'));
assert(isempty(status.decoderState.actor));
assert(~isempty(status.decoderState.incremental.nativeState));
allPduCount = status.output.newPduCount;
while status.decoderState.lastProcessedEndSample < buffer.endSample
    handle = radio.stream.lockedDecoderStart(status.decoderState, buffer, ...
        'Mode', 'parallel', 'NumWorkers', pool.NumWorkers, ...
        'PoolType', 'processes');
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
    'Mode', 'parallel', 'NumWorkers', pool.NumWorkers, ...
    'PoolType', 'processes');
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
