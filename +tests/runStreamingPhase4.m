function runStreamingPhase4()
%RUNSTREAMINGPHASE4 Validate parallel race lifecycle and serial fallback.
testSerialScheduler();
[pool, info] = radio.stream.acquireParallelPool( ...
    'NumWorkers', 5, 'PoolType', 'processes');
if isempty(pool)
    fprintf('Streaming phase-4 parallel tests skipped: %s\n', info.reason);
    return;
end
testUniqueAndAmbiguousResults();
testBoundedFairShare();
testStrongWinnerEarlyFinish();
testDynamicCandidateNarrowing();
testStaleGenerationIsolation();
testCancellation();
testAsynchronousLockedDecoder();
testWarmParallelTiming();
testRealP25SerialParallelAgreement();
testWorkerProtocolPrewarm(pool);
testClientRuntimePrewarm(pool);
fprintf('Streaming phase-4 parallel race tests passed.\n');
end

function testDynamicCandidateNarrowing()
snapshot = fakeSnapshot();
context = struct( ...
    'StatusByProtocol', struct('TETRA', 'confirmed'), ...
    'DelaySecByProtocol', struct( ...
        'DMR', 0.50, 'P25', 0.50, 'dPMR', 0.50, ...
        'NXDN', 0.50, 'TETRA', 0.02));
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, 'MaxInFlight', 1, ...
    'EarlyConfirm', true, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
assert(handle.submitted(1));
mask = strcmp({handle.registry.name}, 'TETRA').';
handle = radio.stream.parallelProbeRaceApplyCandidateMask(handle, mask);
assert(handle.submitted(end));
[handle, race] = radio.stream.parallelProbeRaceCollect( ...
    handle, 'TimeoutSec', 10, 'PollIntervalSec', 0.005);
assert(handle.completed && strcmp(race.outcome, 'confirmed'));
assert(strcmp(race.winner.protocol, 'TETRA'));
assert(race.canceledTaskCount >= 1);
end

function testBoundedFairShare()
snapshot = fakeSnapshot();
context = struct('Status', 'rejected', 'DelaySec', 0.03);
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'MaxInFlight', 2, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
assert(nnz(handle.submitted & ~handle.collected) == 2);
[handle, race] = radio.stream.parallelProbeRaceCollect( ...
    handle, 'TimeoutSec', 10);
assert(handle.completed && strcmp(race.outcome, 'rejected_all'));
assert(race.maxInFlight == 2 && race.peakInFlight <= 2);
assert(nnz(handle.submitted) == 5 && all(handle.collected));
end

function testStrongWinnerEarlyFinish()
snapshot = fakeSnapshot();
context = struct( ...
    'StatusByProtocol', struct('DMR', 'confirmed'), ...
    'DelaySecByProtocol', struct( ...
        'DMR', 0.03, 'P25', 0.50, 'dPMR', 0.50, ...
        'NXDN', 0.50, 'TETRA', 0.50));
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'EarlyConfirm', true, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
[handle, race] = radio.stream.parallelProbeRaceCollect( ...
    handle, 'TimeoutSec', 10, 'PollIntervalSec', 0.005);
assert(handle.completed && strcmp(race.outcome, 'confirmed'));
assert(strcmp(race.winner.protocol, 'DMR'));
assert(race.earlyTerminated && race.canceledTaskCount >= 1);
assert(race.elapsedSec < 0.40);
end

function testAsynchronousLockedDecoder()
fs = 1000;
epoch = radio.stream.newEpoch(1, 81, 3, 0);
state = radio.stream.lockedDecoderInit('DMR', epoch, fs, ...
    'LastProcessedEndSample', 0, ...
    'DecodeFcn', @tests.fakeLockedDecoder, ...
    'SemanticDeduplicate', false);
buffer = radio.stream.ringBufferInit(fs, 2);
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(300, 1)), fs, 0));
handle = radio.stream.lockedDecoderStart(state, buffer, ...
    'Mode', 'parallel', 'NumWorkers', 5);
assert(~handle.completed);
submittedEnd = buffer.endSample;
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(100, 1)), fs, 300, ...
    'SequenceNumber', 1));
token = tic;
status = struct('state', 'running');
while toc(token) < 10
    [handle, status] = radio.stream.lockedDecoderPoll(handle);
    if handle.completed, break; end
    pause(0.01);
end
assert(handle.completed && strcmp(status.state, 'completed'));
assert(status.output.windowEndSample == submittedEnd);
assert(status.output.windowEndSample < buffer.endSample);
assert(status.output.newPduCount == 3);
end

function testSerialScheduler()
snapshot = fakeSnapshot();
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
assert(handle.completed);
assert(strcmp(handle.race.executionMode, 'serial'));
assert(strcmp(handle.race.outcome, 'confirmed'));
assert(strcmp(handle.race.winner.protocol, 'DMR'));
end

function testUniqueAndAmbiguousResults()
snapshot = fakeSnapshot();
uniqueContext = struct( ...
    'StatusByProtocol', struct('DMR', 'confirmed'), ...
    'DelaySec', 0.02);
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', uniqueContext);
assert(~handle.completed && nnz(handle.submitted) == 5);
[handle, race] = radio.stream.parallelProbeRaceCollect( ...
    handle, 'TimeoutSec', 30);
assert(handle.completed && strcmp(race.outcome, 'confirmed'));
assert(strcmp(race.winner.protocol, 'DMR'));

ambiguousContext = struct('StatusByProtocol', ...
    struct('DMR', 'confirmed', 'P25', 'confirmed'));
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', ambiguousContext);
[handle, race] = radio.stream.parallelProbeRaceCollect( ...
    handle, 'TimeoutSec', 10);
assert(handle.completed && strcmp(race.outcome, 'ambiguous'));
assert(isempty(race.winner));
assert(isequal(race.confirmedProtocols, {'DMR', 'P25'}));
end

function testStaleGenerationIsolation()
snapshot = fakeSnapshot();
context = struct( ...
    'StatusByProtocol', struct('DMR', 'confirmed'), ...
    'GenerationDelta', -1);
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'EpochId', 4, 'Generation', 9, ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
[handle, race] = radio.stream.parallelProbeRaceCollect( ...
    handle, 'TimeoutSec', 10);
assert(handle.completed);
assert(race.staleResultCount == 5);
assert(strcmp(race.outcome, 'error'));
assert(isempty(race.confirmedProtocols));
assert(all([race.results.generation] == uint64(9)));
end

function testCancellation()
snapshot = fakeSnapshot();
context = struct('Status', 'confirmed', 'DelaySec', 2.0);
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
pause(0.05);
[handle, race] = radio.stream.parallelProbeRaceCancel( ...
    handle, 'Reason', 'test_generation_closed');
assert(handle.completed && handle.canceled && race.canceled);
assert(isempty(race.confirmedProtocols));
assert(all(strcmp({race.results.status}, 'error')));
end

function testWarmParallelTiming()
snapshot = fakeSnapshot();
context = struct( ...
    'StatusByProtocol', struct('DMR', 'confirmed'), ...
    'DelaySec', 0.25);
serial = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
parallel = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Mode', 'parallel', 'NumWorkers', 5, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
[parallel, race] = radio.stream.parallelProbeRaceCollect( ...
    parallel, 'TimeoutSec', 10);
assert(parallel.completed && strcmp(race.outcome, serial.race.outcome));
assert(isequal({race.results.status}, {serial.race.results.status}));
assert(parallel.elapsedSec < serial.elapsedSec);
fprintf('Warm fake race: serial %.3f s, parallel %.3f s.\n', ...
    serial.elapsedSec, parallel.elapsedSec);
end

function testRealP25SerialParallelAgreement()
path = fullfile(pybackend.defaultPythonRoot(), 'data', 'p25_1_78125.rawiq');
if exist(path, 'file') ~= 2
    return;
end
fs = 78125;
iq = common.readRawIq(path);
count = min(numel(iq), ceil(1 * fs));
snapshot = radio.stream.makeIqChunk(iq(1:count), fs, 0);

serial = radio.stream.parallelProbeRaceStart( ...
    snapshot, [], 'Mode', 'serial');
coldParallel = radio.stream.parallelProbeRaceStart( ...
    snapshot, [], 'Mode', 'parallel', 'NumWorkers', 5);
[coldParallel, coldRace] = radio.stream.parallelProbeRaceCollect( ...
    coldParallel, 'TimeoutSec', 30);
parallel = radio.stream.parallelProbeRaceStart( ...
    snapshot, [], 'Mode', 'parallel', 'NumWorkers', 5);
[parallel, race] = radio.stream.parallelProbeRaceCollect( ...
    parallel, 'TimeoutSec', 30);
assert(coldParallel.completed && parallel.completed);
assert(strcmp(serial.race.outcome, 'confirmed'));
assert(strcmp(coldRace.outcome, serial.race.outcome));
assert(strcmp(race.outcome, serial.race.outcome));
assert(strcmp(race.winner.protocol, 'P25'));
assert(isequal({race.results.status}, {serial.race.results.status}));
fprintf(['Real P25 race: serial %.3f s, cold parallel %.3f s, ', ...
    'warm parallel %.3f s.\n'], ...
    serial.elapsedSec, coldParallel.elapsedSec, parallel.elapsedSec);
end

function testWorkerProtocolPrewarm(pool)
report = radio.stream.prewarmProtocolWorkers({'P25'}, ...
    'Pool', pool, 'DurationSec', 0.02, 'TimeoutSec', 60);
assert(report.success);
assert(report.numWorkers == pool.NumWorkers);
end

function testClientRuntimePrewarm(pool)
report = radio.stream.prewarmClientRuntime( ...
    pool, {'P25'}, 'PoolType', 'processes', 'TimeoutSec', 60);
assert(report.success && strcmp(report.protocol, 'P25'));
end

function snapshot = fakeSnapshot()
snapshot = radio.stream.makeIqChunk( ...
    complex(zeros(48000, 1, 'single')), 48000, 0);
end
