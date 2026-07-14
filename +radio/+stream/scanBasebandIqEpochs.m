function [pdus, report] = scanBasebandIqEpochs(iq, sampleRateHz, varargin)
%SCANBASEBANDIQEPOCHS Identify and decode every independent RF activity epoch.
p = inputParser;
p.addParameter('ProtocolNames', {});
p.addParameter('Config', radio.stream.defaultConfig());
p.addParameter('RadioConfig', radio.defaultConfig());
p.addParameter('Mode', 'parallel');
p.addParameter('NumWorkers', 5);
p.addParameter('PoolType', 'processes');
p.addParameter('TimeoutSec', 120);
p.addParameter('DecoderBackend', 'matlab');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.addParameter('ShowProgress', false);
p.addParameter('ChannelId', 1);
p.addParameter('CenterFrequencyHz', 0);
p.addParameter('ProbeTaskFcn', []);
p.addParameter('ProbeTaskContext', struct());
p.addParameter('DecodeFcn', []);
p.parse(varargin{:});

validateattributes(sampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'sampleRateHz');
if ~isvector(iq) && ~isempty(iq)
    error('radio:stream:scanBasebandIqEpochs:IqShape', ...
        'IQ data must be a vector.');
end
iq = iq(:);
timerToken = tic;
[epochs, activityReport] = radio.stream.detectActivityEpochs( ...
    iq, sampleRateHz, ...
    'Config', p.Results.Config, ...
    'ChannelId', p.Results.ChannelId, ...
    'CenterFrequencyHz', p.Results.CenterFrequencyHz);

pdus = struct([]);
races = cell(0, 1);
fallbackReasons = cell(0, 1);
executionModes = cell(0, 1);
classificationElapsedSec = 0;
decodeElapsedSec = 0;
lastRace = [];

for k = 1:numel(epochs)
    epoch = epochs(k);
    decodeStart = epoch.decodeStartSample;
    decodeEnd = epoch.endSample;
    if decodeEnd <= decodeStart
        epoch.outcome = 'empty';
        epoch.classificationReport = struct('outcome', 'empty');
        epochs(k) = epoch;
        continue;
    end

    first = double(decodeStart) + 1;
    last = double(decodeEnd);
    epochIq = iq(first:last);
    identification = radio.stream.identifyBasebandIq( ...
        epochIq, sampleRateHz, ...
        'ProtocolNames', p.Results.ProtocolNames, ...
        'Config', p.Results.Config, ...
        'Mode', p.Results.Mode, ...
        'NumWorkers', p.Results.NumWorkers, ...
        'PoolType', p.Results.PoolType, ...
        'TimeoutSec', p.Results.TimeoutSec, ...
        'ShowProgress', p.Results.ShowProgress, ...
        'TaskFcn', p.Results.ProbeTaskFcn, ...
        'TaskContext', p.Results.ProbeTaskContext, ...
        'EpochId', epoch.epochId, ...
        'Generation', epoch.generation, ...
        'SourceSampleStart', decodeStart, ...
        'ChannelId', p.Results.ChannelId, ...
        'CenterFrequencyHz', p.Results.CenterFrequencyHz);

    epoch.outcome = identification.outcome;
    epoch.classificationStartSample = ...
        identification.classificationStartSample;
    epoch.classificationEndSample = identification.classificationEndSample;
    epoch.classificationElapsedSec = identification.classificationElapsedSec;
    epoch.executionMode = identification.executionMode;
    epoch.fallbackReason = identification.fallbackReason;
    epoch.classificationReport = identification;
    classificationElapsedSec = classificationElapsedSec + ...
        identification.classificationElapsedSec;
    executionModes = appendNonempty(executionModes, ...
        identification.executionMode);
    fallbackReasons = appendNonempty(fallbackReasons, ...
        identification.fallbackReason);
    for n = 1:numel(identification.races)
        races{end+1, 1} = identification.races{n}; %#ok<AGROW>
    end
    lastRace = identification.lastRace;

    if strcmp(identification.outcome, 'confirmed')
        epoch.protocol = identification.selectedProtocol;
        epoch.lockSample = identification.classificationEndSample;
        [epoch.confidence, epoch.frequencyOffsetHz] = ...
            winnerMetrics(identification.lastRace);
        decodeTimer = tic;
        epochPdus = decodeEpoch(epochIq, sampleRateHz, epoch.protocol, p.Results);
        epoch.decodeElapsedSec = toc(decodeTimer);
        decodeElapsedSec = decodeElapsedSec + epoch.decodeElapsedSec;
        snapshot = radio.stream.makeIqChunk( ...
            epochIq, sampleRateHz, decodeStart, ...
            'ChannelId', p.Results.ChannelId, ...
            'CenterFrequencyHz', p.Results.CenterFrequencyHz);
        epochPdus = radio.stream.stampStreamPdus( ...
            epochPdus, epoch.protocol, snapshot, epoch.epochId);
        firstPduIndex = numel(pdus) + 1;
        pdus = radio.appendPdus(pdus, epochPdus);
        epoch.pduCount = numel(epochPdus);
        if epoch.pduCount > 0
            epoch.pduStartIndex = uint64(firstPduIndex);
            epoch.pduEndIndex = uint64(numel(pdus));
            samples = arrayfun(@(item) radio.getNestedField( ...
                item, 'extra.stream.source_sample', uint64(0)), epochPdus);
            epoch.lastGoodSample = max(uint64(samples));
        else
            epoch.lastGoodSample = epoch.lockSample;
        end
    end
    epochs(k) = epoch;

    if p.Results.ShowProgress
        fprintf(['[radio.epoch] id=%d samples=[%d,%d) outcome=%s ', ...
            'protocol=%s pdus=%d close=%s\n'], ...
            epoch.epochId, epoch.candidateStartSample, epoch.endSample, ...
            epoch.outcome, valueOr(epoch.protocol, '-'), ...
            epoch.pduCount, epoch.closeReason);
    end
end

pdus = radio.normalizePdus(pdus);
detectedProtocols = uniqueStable(nonemptyValues({epochs.protocol}));
confirmedCount = sum(strcmp({epochs.outcome}, 'confirmed'));
outcome = aggregateOutcome(epochs, confirmedCount);
selectedProtocol = '';
if numel(detectedProtocols) == 1
    selectedProtocol = detectedProtocols{1};
end
executionMode = aggregateText(executionModes, 'mixed');
fallbackReason = strjoin(uniqueStable(fallbackReasons), '; ');

classificationStartSample = uint64(0);
classificationEndSample = uint64(0);
epochId = uint64(0);
if ~isempty(epochs)
    classificationStartSample = epochs(1).classificationStartSample;
    classificationEndSample = epochs(end).classificationEndSample;
    epochId = epochs(end).epochId;
end

registry = radio.stream.probeRegistry(p.Results.ProtocolNames);
report = struct( ...
    'outcome', outcome, ...
    'selectedProtocol', selectedProtocol, ...
    'protocolsDetected', {detectedProtocols}, ...
    'protocolNames', {reshape({registry.name}, 1, [])}, ...
    'requestedMode', char(p.Results.Mode), ...
    'executionMode', executionMode, ...
    'executionModes', {uniqueStable(executionModes)}, ...
    'fallbackReason', fallbackReason, ...
    'sampleRateHz', double(sampleRateHz), ...
    'sourceSampleStart', uint64(0), ...
    'sourceSampleCount', uint64(numel(iq)), ...
    'activitySeen', activityReport.activitySeen, ...
    'epochId', epochId, ...
    'epochCount', numel(epochs), ...
    'confirmedEpochCount', confirmedCount, ...
    'epochs', epochs, ...
    'classificationStartSample', classificationStartSample, ...
    'classificationEndSample', classificationEndSample, ...
    'classificationElapsedSec', classificationElapsedSec, ...
    'decodeElapsedSec', decodeElapsedSec, ...
    'totalElapsedSec', toc(timerToken), ...
    'raceCount', numel(races), ...
    'lastRace', lastRace, ...
    'races', {races}, ...
    'pduCount', numel(pdus), ...
    'activityReport', activityReport);
end

function pdus = decodeEpoch(iq, sampleRateHz, protocol, options)
if isempty(options.DecodeFcn)
    pdus = radio.scanIq(iq, sampleRateHz, ...
        'ProtocolNames', {protocol}, ...
        'FreqList', [], ...
        'BlindSearch', false, ...
        'RadioConfig', options.RadioConfig, ...
        'DecoderBackend', options.DecoderBackend, ...
        'PythonRoot', options.PythonRoot, ...
        'PythonExecutable', options.PythonExecutable, ...
        'Deduplicate', options.Deduplicate, ...
        'ShowProgress', options.ShowProgress);
else
    pdus = options.DecodeFcn(iq, sampleRateHz, protocol);
    pdus = radio.normalizePdus(pdus);
    if options.Deduplicate
        pdus = radio.deduplicatePdus(pdus);
    end
end
end

function [confidence, frequencyOffsetHz] = winnerMetrics(race)
confidence = 0;
frequencyOffsetHz = 0;
if isempty(race) || ~isstruct(race) || ~isfield(race, 'winner') || ...
        isempty(race.winner)
    return;
end
confidence = radio.getField(race.winner, 'confidence', 0);
frequencyOffsetHz = radio.getField(race.winner, 'frequencyOffsetHz', 0);
end

function outcome = aggregateOutcome(epochs, confirmedCount)
if isempty(epochs)
    outcome = 'no_signal';
elseif confirmedCount == numel(epochs)
    outcome = 'confirmed';
elseif confirmedCount > 0
    outcome = 'partial';
elseif any(strcmp({epochs.outcome}, 'ambiguous'))
    outcome = 'ambiguous';
elseif any(strcmp({epochs.outcome}, 'timeout'))
    outcome = 'timeout';
elseif any(strcmp({epochs.outcome}, 'error'))
    outcome = 'error';
else
    outcome = 'unclassified';
end
end

function values = appendNonempty(values, value)
if ~isempty(value)
    values{end+1, 1} = char(value);
end
end

function values = nonemptyValues(values)
values = values(~cellfun(@isempty, values));
end

function values = uniqueStable(values)
if isempty(values), return; end
[~, indices] = unique(values, 'stable');
values = values(sort(indices));
end

function value = aggregateText(values, mixedValue)
values = uniqueStable(values);
if isempty(values)
    value = '';
elseif numel(values) == 1
    value = values{1};
else
    value = mixedValue;
end
end

function value = valueOr(value, fallback)
if isempty(value), value = fallback; end
end
