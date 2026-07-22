function runStreamingPhase4()
%RUNSTREAMINGPHASE4 Validate the parallel race lifecycle.
[pool, info] = radio.stream.acquireParallelPool( ...
    'NumWorkers', 5);
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
testRealP25Parallel();
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
    'NumWorkers', 5, 'MaxInFlight', 1, ...
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
    'NumWorkers', 5, ...
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
    'NumWorkers', 5, ...
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
    'NumWorkers', 5);
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

function testUniqueAndAmbiguousResults()
snapshot = fakeSnapshot();
uniqueContext = struct( ...
    'StatusByProtocol', struct('DMR', 'confirmed'), ...
    'DelaySec', 0.02);
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'NumWorkers', 5, ...
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
    'NumWorkers', 5, ...
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
    'NumWorkers', 5, ...
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
    'NumWorkers', 5, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
pause(0.05);
[handle, race] = radio.stream.parallelProbeRaceCancel( ...
    handle, 'Reason', 'test_generation_closed');
assert(handle.completed && handle.canceled && race.canceled);
assert(isempty(race.confirmedProtocols));
assert(all(strcmp({race.results.status}, 'error')));
end

function testRealP25Parallel()
path = fullfile(common.sampleDataRoot(), 'p25_1_78125.rawiq');
if exist(path, 'file') ~= 2
    return;
end
fs = 78125;
iq = common.readRawIq(path);
count = min(numel(iq), ceil(1 * fs));
snapshot = radio.stream.makeIqChunk(iq(1:count), fs, 0);

coldParallel = radio.stream.parallelProbeRaceStart( ...
    snapshot, [], 'NumWorkers', 5);
[coldParallel, coldRace] = radio.stream.parallelProbeRaceCollect( ...
    coldParallel, 'TimeoutSec', 30);
parallel = radio.stream.parallelProbeRaceStart( ...
    snapshot, [], 'NumWorkers', 5);
[parallel, race] = radio.stream.parallelProbeRaceCollect( ...
    parallel, 'TimeoutSec', 30);
assert(coldParallel.completed && parallel.completed);
assert(strcmp(coldRace.outcome, 'confirmed'));
assert(strcmp(race.outcome, coldRace.outcome));
assert(strcmp(race.winner.protocol, 'P25'));
assert(isequal({race.results.status}, {coldRace.results.status}));
fprintf('Real P25 race: cold %.3f s, warm %.3f s.\n', ...
    coldParallel.elapsedSec, parallel.elapsedSec);
end

function testWorkerProtocolPrewarm(pool)
report = radio.stream.prewarmProtocolWorkers({'P25'}, ...
    'Pool', pool, 'DurationSec', 0.02, 'TimeoutSec', 60);
assert(report.success);
assert(report.numWorkers == pool.NumWorkers);
end

function testClientRuntimePrewarm(pool)
report = radio.stream.prewarmClientRuntime( ...
    pool, {'P25'}, 'TimeoutSec', 60);
assert(report.success && strcmp(report.protocol, 'P25'));
end

function snapshot = fakeSnapshot()
snapshot = radio.stream.makeIqChunk( ...
    complex(zeros(48000, 1, 'single')), 48000, 0);
end
