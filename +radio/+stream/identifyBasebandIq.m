function report = identifyBasebandIq(iq, sampleRateHz, varargin)
%IDENTIFYBASEBANDIQ Identify one centered/baseband channel by protocol race.
% This offline adapter feeds the shared activity detector in small chunks,
% but waits for each protocol generation before advancing the file.  It
% therefore preserves the protocol-parallel semantics without allowing
% disk-speed acquisition to outrun the asynchronous workers.
p = inputParser;
p.addParameter('ProtocolNames', {});
p.addParameter('Config', radio.stream.defaultConfig());
p.addParameter('NumWorkers', 5);
p.addParameter('TimeoutSec', 120);
p.addParameter('ShowProgress', false);
p.addParameter('TaskFcn', []);
p.addParameter('TaskContext', struct());
p.addParameter('EpochId', uint64(1));
p.addParameter('Generation', uint64(1));
p.addParameter('SourceSampleStart', uint64(0));
p.addParameter('ChannelId', 1);
p.addParameter('CenterFrequencyHz', 0);
p.parse(varargin{:});

validateattributes(sampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'sampleRateHz');
if ~isvector(iq) && ~isempty(iq)
    error('radio:stream:identifyBasebandIq:IqShape', ...
        'IQ data must be a vector.');
end
iq = iq(:);
registry = radio.stream.probeRegistry(p.Results.ProtocolNames);
if isempty(registry)
    error('radio:stream:identifyBasebandIq:Protocols', ...
        'At least one supported protocol must be enabled.');
end

cfg = p.Results.Config;
validateConfig(cfg);
% Retain at least one complete maximum probe window.  This protects custom
% configurations from silently truncating the TETRA six-second probe.
cfg.ringBufferSec = max(cfg.ringBufferSec, ...
    max([registry.maxWindowSec]) + cfg.chunkDurationSec);
chunkSamples = max(1, round(cfg.chunkDurationSec * sampleRateHz));
requestedGeneration = uint64(p.Results.Generation);
if requestedGeneration == 0
    initialGeneration = uint64(0);
else
    initialGeneration = requestedGeneration - uint64(1);
end
controller = radio.stream.channelControllerInit(sampleRateHz, ...
    'Config', cfg, ...
    'ChannelId', p.Results.ChannelId, ...
    'CenterFrequencyHz', p.Results.CenterFrequencyHz, ...
    'NextEpochId', uint64(p.Results.EpochId), ...
    'InitialGeneration', initialGeneration);

timerToken = tic;
races = cell(0, 1);
states = [];
activeEpochId = uint64(0);
terminalEpochId = uint64(0);
lastRace = [];
activitySeen = false;
executionMode = 'parallel';
outcome = 'no_signal';
selectedProtocol = '';
classificationStartSample = uint64(0);
classificationEndSample = uint64(0);

for first = 1:chunkSamples:numel(iq)
    last = min(numel(iq), first + chunkSamples - 1);
    absoluteStart = uint64(p.Results.SourceSampleStart) + uint64(first - 1);
    chunk = radio.stream.makeIqChunk(iq(first:last), sampleRateHz, ...
        absoluteStart, ...
        'ChannelId', p.Results.ChannelId, ...
        'CenterFrequencyHz', p.Results.CenterFrequencyHz, ...
        'SequenceNumber', uint64(floor((first - 1) / chunkSamples)));
    [controller, channelOutput] = ...
        radio.stream.channelControllerFeed(controller, chunk);
    if channelOutput.activity.isActive
        activitySeen = true;
    end

    epoch = controller.currentEpoch;
    if isempty(epoch)
        continue;
    end
    if activeEpochId ~= epoch.epochId
        activeEpochId = epoch.epochId;
        terminalEpochId = uint64(0);
        states = [];
        classificationStartSample = epoch.candidateStartSample;
    end
    if terminalEpochId == epoch.epochId
        continue;
    end

    buffer = controller.ringBuffer;
    snapshotStart = max(buffer.startSample, epoch.candidateStartSample);
    if snapshotStart >= buffer.endSample
        continue;
    end
    snapshot = radio.stream.ringBufferRange( ...
        buffer, snapshotStart, buffer.endSample);
    handle = radio.stream.parallelProbeRaceStart(snapshot, states, ...
        'EpochId', epoch.epochId, ...
        'Generation', epoch.generation, ...
        'Registry', registry, ...
        'NumWorkers', p.Results.NumWorkers, ...
        'TaskFcn', p.Results.TaskFcn, ...
        'TaskContext', p.Results.TaskContext);
    [handle, race] = radio.stream.parallelProbeRaceCollect(handle, ...
        'TimeoutSec', p.Results.TimeoutSec);
    if ~handle.completed
        [handle, race] = radio.stream.parallelProbeRaceCancel(handle, ...
            'Reason', 'offline_probe_timeout'); %#ok<ASGLU>
        outcome = 'timeout';
        lastRace = race;
        races{end+1, 1} = race; %#ok<AGROW>
        classificationEndSample = snapshot.sourceSampleEnd;
        break;
    end

    states = handle.states;
    lastRace = race;
    races{end+1, 1} = race; %#ok<AGROW>
    executionMode = race.executionMode;
    classificationEndSample = snapshot.sourceSampleEnd;
    if p.Results.ShowProgress && any(handle.submitted)
        fprintf('[radio.parallel] epoch=%d window=%.3f s outcome=%s\n', ...
            epoch.epochId, numel(snapshot.iq) / sampleRateHz, race.outcome);
    end

    switch race.outcome
        case 'confirmed'
            outcome = 'confirmed';
            selectedProtocol = race.winner.protocol;
        case 'ambiguous'
            outcome = 'ambiguous';
        case 'rejected_all'
            outcome = 'rejected_all';
            terminalEpochId = epoch.epochId;
        case 'error'
            outcome = 'error';
            terminalEpochId = epoch.epochId;
        otherwise
            outcome = 'classifying';
    end
    if any(strcmp(outcome, {'confirmed', 'ambiguous', 'timeout'}))
        break;
    end
end

if ~activitySeen && ~strcmp(outcome, 'timeout')
    outcome = 'no_signal';
elseif strcmp(outcome, 'classifying')
    outcome = 'insufficient_data';
end

report = struct( ...
    'outcome', outcome, ...
    'selectedProtocol', selectedProtocol, ...
    'protocolNames', {reshape({registry.name}, 1, [])}, ...
    'executionMode', executionMode, ...
    'sampleRateHz', double(sampleRateHz), ...
    'sourceSampleStart', uint64(p.Results.SourceSampleStart), ...
    'sourceSampleCount', uint64(numel(iq)), ...
    'activitySeen', activitySeen, ...
    'epochId', activeEpochId, ...
    'classificationStartSample', classificationStartSample, ...
    'classificationEndSample', classificationEndSample, ...
    'classificationElapsedSec', toc(timerToken), ...
    'raceCount', numel(races), ...
    'lastRace', lastRace, ...
    'races', {races});
end

function validateConfig(cfg)
required = {'chunkDurationSec', 'ringBufferSec', 'activity'};
missing = required(~isfield(cfg, required));
if ~isempty(missing)
    error('radio:stream:identifyBasebandIq:Config', ...
        'Streaming configuration is missing field: %s', missing{1});
end
validateattributes(cfg.chunkDurationSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
validateattributes(cfg.ringBufferSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
end
