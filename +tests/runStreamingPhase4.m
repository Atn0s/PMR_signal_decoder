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
testStaleGenerationIsolation();
testCancellation();
testWarmParallelTiming();
testRealP25SerialParallelAgreement();
fprintf('Streaming phase-4 parallel race tests passed.\n');
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

function snapshot = fakeSnapshot()
snapshot = radio.stream.makeIqChunk( ...
    complex(zeros(48000, 1, 'single')), 48000, 0);
end
