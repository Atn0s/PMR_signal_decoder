function report = prewarmClientRuntime(pool, protocolNames, varargin)
%PREWARMCLIENTRUNTIME Exercise client-side streaming orchestration once.
p = inputParser;
p.addParameter('TimeoutSec', 30);
p.addParameter('PoolType', 'auto');
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
        snapshot, [], 'Registry', probe, 'Mode', 'parallel', ...
        'NumWorkers', pool.NumWorkers, 'PoolType', p.Results.PoolType, ...
        'MaxInFlight', 1);
    [handle, status] = radio.stream.parallelProbeRaceCollect( ...
        handle, 'TimeoutSec', p.Results.TimeoutSec, ...
        'PollIntervalSec', 0.005);
    if ~handle.completed
        [handle, status] = radio.stream.parallelProbeRaceCancel( ...
            handle, 'Reason', 'client_runtime_prewarm_timeout'); %#ok<ASGLU>
        report.errorReason = 'client_runtime_prewarm_timeout';
    else
        if any(strcmp(protocolNames, 'NXDN'))
            prewarmNxdnLockedPath( ...
                pool, p.Results.PoolType, p.Results.TimeoutSec);
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

function prewarmNxdnLockedPath(pool, poolType, timeoutSec)
fs = 125000;
epoch = radio.stream.newEpoch(0, 0, 0, 0);
state = radio.stream.lockedDecoderInit( ...
    'NXDN', epoch, fs, 'LastProcessedEndSample', uint64(0));
buffer = radio.stream.ringBufferInit(fs, 0.30);
chunk = radio.stream.makeIqChunk( ...
    complex(zeros(round(0.25 * fs), 1, 'single')), fs, 0);
[buffer, ~] = radio.stream.ringBufferPush(buffer, chunk);
handle = radio.stream.lockedDecoderStart( ...
    state, buffer, 'Mode', 'parallel', ...
    'NumWorkers', pool.NumWorkers, 'PoolType', poolType);
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
