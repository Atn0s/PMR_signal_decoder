function handle = parallelProbeRaceStart(snapshot, states, varargin)
%PARALLELPROBERACESTART Submit one generation of eligible protocol probes.
p = inputParser;
p.addParameter('EpochId', uint64(1));
p.addParameter('Generation', uint64(1));
p.addParameter('ProtocolNames', {});
p.addParameter('Registry', []);
p.addParameter('Mode', 'auto');
p.addParameter('NumWorkers', 5);
p.addParameter('PoolType', 'auto');
p.addParameter('AllowSerialFallback', true);
p.addParameter('TaskFcn', []);
p.addParameter('TaskContext', struct());
p.parse(varargin{:});
radio.stream.validateIqChunk(snapshot);

registry = p.Results.Registry;
if isempty(registry)
    registry = radio.stream.probeRegistry(p.Results.ProtocolNames);
end
if isempty(registry)
    error('radio:stream:parallelProbeRaceStart:Registry', ...
        'At least one protocol probe is required.');
end
states = initializeStates(states, registry, p.Results.EpochId, ...
    p.Results.Generation, snapshot.sourceSampleStart);

handle = makeHandle(snapshot, states, registry, p.Results);
mode = lower(char(p.Results.Mode));
if strcmp(mode, 'serial')
    handle = runSerial(handle, p.Results.TaskFcn, p.Results.TaskContext);
    return;
end
if ~any(strcmp(mode, {'auto', 'parallel'}))
    error('radio:stream:parallelProbeRaceStart:Mode', ...
        'Mode must be auto, parallel, or serial.');
end

[pool, poolInfo] = radio.stream.acquireParallelPool( ...
    'NumWorkers', p.Results.NumWorkers, ...
    'PoolType', p.Results.PoolType, ...
    'AllowCreate', true);
handle.poolInfo = poolInfo;
if isempty(pool)
    if p.Results.AllowSerialFallback
        handle.fallbackReason = poolInfo.reason;
        handle = runSerial(handle, p.Results.TaskFcn, p.Results.TaskContext);
        handle.executionMode = 'serial_fallback';
        handle.race.executionMode = 'serial_fallback';
        return;
    end
    error('radio:stream:parallelProbeRaceStart:PoolUnavailable', ...
        'Parallel pool is unavailable: %s', poolInfo.reason);
end

handle.executionMode = 'parallel';
for k = 1:numel(registry)
    [ready, reason] = radio.stream.probeReady(states(k), snapshot, registry(k));
    if ~ready
        handle.results(k) = localResult(states(k), snapshot, reason);
        handle.collected(k) = true;
        continue;
    end
    handle.futures{k} = parfeval(pool, @radio.stream.executeProbeTask, 2, ...
        states(k), snapshot, registry(k), p.Results.TaskFcn, p.Results.TaskContext);
    handle.submitted(k) = true;
end
if all(handle.collected)
    handle = finalizeHandle(handle);
end
end

function states = initializeStates(states, registry, epochId, generation, startSample)
if isempty(states)
    states = repmat(radio.stream.probeStateInit( ...
        registry(1), epochId, generation, startSample), numel(registry), 1);
    for k = 1:numel(registry)
        states(k) = radio.stream.probeStateInit( ...
            registry(k), epochId, generation, startSample);
    end
end
if numel(states) ~= numel(registry)
    error('radio:stream:parallelProbeRaceStart:StateCount', ...
        'Probe state count does not match registry count.');
end
for k = 1:numel(states)
    if states(k).epochId ~= uint64(epochId) || ...
            states(k).generation ~= uint64(generation)
        error('radio:stream:parallelProbeRaceStart:StaleState', ...
            'Probe state does not belong to the active epoch/generation.');
    end
end
end

function handle = makeHandle(snapshot, states, registry, options)
results = repmat(localResult(states(1), snapshot, 'not_submitted'), ...
    numel(registry), 1);
for k = 1:numel(registry)
    results(k) = localResult(states(k), snapshot, 'not_submitted');
end
handle = struct( ...
    'epochId', uint64(options.EpochId), ...
    'generation', uint64(options.Generation), ...
    'snapshot', snapshot, ...
    'registry', registry, ...
    'states', states, ...
    'results', results, ...
    'futures', {cell(numel(registry), 1)}, ...
    'submitted', false(numel(registry), 1), ...
    'collected', false(numel(registry), 1), ...
    'completed', false, ...
    'canceled', false, ...
    'executionMode', '', ...
    'fallbackReason', '', ...
    'poolInfo', struct(), ...
    'staleResultCount', 0, ...
    'taskErrorCount', 0, ...
    'timerToken', tic, ...
    'elapsedSec', 0, ...
    'race', []);
end

function handle = runSerial(handle, taskFcn, taskContext)
handle.executionMode = 'serial';
for k = 1:numel(handle.registry)
    [ready, reason] = radio.stream.probeReady( ...
        handle.states(k), handle.snapshot, handle.registry(k));
    if ~ready
        handle.results(k) = localResult( ...
            handle.states(k), handle.snapshot, reason);
    else
        try
            [newState, result] = radio.stream.executeProbeTask( ...
                handle.states(k), handle.snapshot, handle.registry(k), ...
                taskFcn, taskContext);
            [handle, accepted] = acceptResult(handle, k, newState, result);
            if ~accepted, handle.staleResultCount = handle.staleResultCount + 1; end
        catch ME
            handle.taskErrorCount = handle.taskErrorCount + 1;
            handle.results(k) = taskErrorResult( ...
                handle.states(k), handle.snapshot, ME);
        end
    end
    handle.collected(k) = true;
end
handle = finalizeHandle(handle);
end

function result = localResult(state, snapshot, reason)
if any(strcmp(state.status, {'confirmed', 'rejected'})) && ...
        ~isempty(state.lastResult)
    result = state.lastResult;
else
    result = radio.stream.makeProbeResult( ...
        state, 'pending', snapshot, 'Reason', reason);
end
end

function handle = finalizeHandle(handle)
handle.completed = true;
handle.elapsedSec = toc(handle.timerToken);
handle.race = radio.stream.summarizeProbeResults( ...
    handle.results, handle.epochId, handle.generation);
handle.race.executionMode = handle.executionMode;
handle.race.elapsedSec = handle.elapsedSec;
handle.race.staleResultCount = handle.staleResultCount;
handle.race.taskErrorCount = handle.taskErrorCount;
handle.race.canceled = handle.canceled;
handle.race.fallbackReason = handle.fallbackReason;
end

function [handle, accepted] = acceptResult(handle, index, newState, result)
accepted = result.epochId == handle.epochId && ...
    result.generation == handle.generation && ...
    newState.epochId == handle.epochId && ...
    newState.generation == handle.generation && ...
    strcmp(result.protocol, handle.registry(index).name) && ...
    strcmp(newState.protocol, handle.registry(index).name);
if accepted
    handle.states(index) = newState;
    handle.results(index) = result;
else
    handle.results(index) = radio.stream.makeProbeResult( ...
        handle.states(index), 'error', handle.snapshot, ...
        'Reason', 'stale_or_mismatched_worker_result_ignored');
end
end

function result = taskErrorResult(state, snapshot, exception)
result = radio.stream.makeProbeResult(state, 'error', snapshot, ...
    'Reason', sprintf('%s: %s', exception.identifier, exception.message));
end
