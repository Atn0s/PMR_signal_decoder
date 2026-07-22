function report = prewarmClientRuntime(pool, protocolNames, varargin)
%PREWARMCLIENTRUNTIME Exercise client-side streaming orchestration once.
p = inputParser;
p.addParameter('TimeoutSec', 30);
p.parse(varargin{:});
token = tic;
report = struct('success', false, 'elapsedSec', 0, ...
    'protocol', '', 'raceOutcome', '', 'errorReason', '');
try
    % Warm the periodic noise-floor FFT and the modulation-family gate on
    % the client, where both execute during live acquisition.
    fs = 125000;
    activity = radio.stream.activityDetectorInit(fs);
    quiet = radio.stream.makeIqChunk( ...
        complex(zeros(round(0.10 * fs), 1, 'single')), fs, 0);
    radio.stream.activityDetectorFeed(activity, quiet);
    n = (0:round(0.20 * fs)-1).';
    gateIq = single(exp(1i .* 2 .* pi .* 1200 .* n ./ fs));
    gateSnapshot = radio.stream.makeIqChunk(gateIq, fs, 0);
    radio.stream.protocolCandidateGate( ...
        gateSnapshot, radio.stream.probeRegistry());

    registry = radio.stream.probeRegistry(protocolNames);
    if isempty(registry)
        registry = radio.stream.probeRegistry({'P25'});
    end
    preferred = find(strcmp({registry.name}, 'P25'), 1);
    if isempty(preferred), preferred = 1; end
    probe = registry(preferred);
    count = max(256, ceil(probe.initialWindowSec * ...
        probe.targetSampleRateHz));
    phase = (0:count-1).';
    iq = single(1e-3 .* exp(1i .* 2 .* pi .* phase ./ 97));
    snapshot = radio.stream.makeIqChunk( ...
        iq, probe.targetSampleRateHz, 0);
    handle = radio.stream.parallelProbeRaceStart( ...
        snapshot, [], 'Registry', probe, ...
        'NumWorkers', pool.NumWorkers, ...
        'MaxInFlight', 1);
    [handle, status] = radio.stream.parallelProbeRaceCollect( ...
        handle, 'TimeoutSec', p.Results.TimeoutSec, ...
        'PollIntervalSec', 0.005);
    if ~handle.completed
        [handle, status] = radio.stream.parallelProbeRaceCancel( ...
            handle, 'Reason', 'client_runtime_prewarm_timeout'); %#ok<ASGLU>
        report.errorReason = 'client_runtime_prewarm_timeout';
    else
        prewarmPersistentActorWorkers(pool, p.Results.TimeoutSec);
        if any(strcmp(protocolNames, 'NXDN'))
            prewarmNxdnLockedPath(pool, p.Results.TimeoutSec);
        end
        report.success = true;
        report.protocol = probe.name;
        report.raceOutcome = status.outcome;
    end
catch ME
    report.errorReason = sprintf('%s: %s', ME.identifier, ME.message);
end
report.elapsedSec = toc(token);
end

function prewarmPersistentActorWorkers(pool, timeoutSec)
% Occupy every process worker once so actor-loop JIT, queue handshakes, and
% task placement are paid before preview starts rather than after LOCKED.
count = pool.NumWorkers;
actors = cell(count, 1);
for k = 1:count
    epoch = radio.stream.newEpoch(k, 0, 0, 0);
    state = radio.stream.lockedDecoderInit( ...
        'DMR', epoch, 1000, 'LastProcessedEndSample', uint64(0));
    input = struct('chunk', [], 'availableEndSample', uint64(0), ...
        'targetEndSample', uint64(0), 'overrunSamples', uint64(0));
    actors{k} = radio.stream.lockedDecoderActorStart(pool, state, input);
end
completed = false(count, 1);
token = tic;
while ~all(completed) && toc(token) < timeoutSec
    for k = 1:count
        if completed(k), continue; end
        [actors{k}, event] = ...
            radio.stream.lockedDecoderActorPoll(actors{k});
        completed(k) = event.completed && strcmp(event.state, 'completed');
    end
    if ~all(completed), pause(0.005); end
end
if ~all(completed)
    stopActors(actors);
    error('radio:stream:prewarmClientRuntime:ActorFleetTimeout', ...
        'Persistent actor fleet prewarm timed out.');
end
taskIds = cellfun(@(actor) actor.workerTaskId, actors);
if numel(unique(taskIds(taskIds > 0))) ~= count
    stopActors(actors);
    error('radio:stream:prewarmClientRuntime:ActorFleetPlacement', ...
        'Persistent actor prewarm did not visit every process worker.');
end
stopActors(actors);
token = tic;
while toc(token) < min(5, timeoutSec)
    finished = cellfun(@(actor) ...
        strcmp(char(actor.future.State), 'finished'), actors);
    if all(finished), return; end
    pause(0.005);
end
error('radio:stream:prewarmClientRuntime:ActorFleetStop', ...
    'Persistent actor fleet did not release all process workers.');
end

function stopActors(actors)
for k = 1:numel(actors)
    if ~isempty(actors{k})
        actors{k} = radio.stream.lockedDecoderActorStop(actors{k});
    end
end
end

function prewarmNxdnLockedPath(pool, timeoutSec)
fs = 125000;
epoch = radio.stream.newEpoch(0, 0, 0, 0);
state = radio.stream.lockedDecoderInit( ...
    'NXDN', epoch, fs, 'LastProcessedEndSample', uint64(0));
buffer = radio.stream.ringBufferInit(fs, 0.30);
chunk = radio.stream.makeIqChunk( ...
    complex(zeros(round(0.25 * fs), 1, 'single')), fs, 0);
[buffer, ~] = radio.stream.ringBufferPush(buffer, chunk);
handle = radio.stream.lockedDecoderStart( ...
    state, buffer, ...
    'NumWorkers', pool.NumWorkers);
token = tic;
while ~handle.completed && toc(token) < timeoutSec
    [handle, status] = radio.stream.lockedDecoderPoll(handle); %#ok<ASGLU>
    if ~handle.completed, pause(0.005); end
end
if ~handle.completed
    [handle, ~] = radio.stream.lockedDecoderCancel(handle);
    error('radio:stream:prewarmClientRuntime:ActorTimeout', ...
        'Persistent NXDN actor prewarm timed out.');
end
[handle, status] = radio.stream.lockedDecoderPoll(handle); %#ok<ASGLU>
if ~strcmp(status.state, 'completed') || ...
        isempty(status.decoderState)
    error('radio:stream:prewarmClientRuntime:ActorFailed', ...
        'Persistent NXDN actor prewarm failed: %s', status.errorReason);
end
if isfield(status.decoderState, 'actor') && ...
        ~isempty(status.decoderState.actor)
    actor = status.decoderState.actor;
    status.decoderState = ...
        radio.stream.lockedDecoderStateRelease(status.decoderState); %#ok<NASGU>
    stopToken = tic;
    while ~strcmp(char(actor.future.State), 'finished') && ...
            toc(stopToken) < min(2, timeoutSec)
        pause(0.005);
    end
end
end
