function [epochs, report] = detectActivityEpochs(iq, sampleRateHz, varargin)
%DETECTACTIVITYEPOCHS Split finite baseband IQ into independent RF epochs.
p = inputParser;
p.addParameter('Config', radio.stream.defaultConfig());
p.addParameter('ChannelId', 1);
p.addParameter('CenterFrequencyHz', 0);
p.parse(varargin{:});

validateattributes(sampleRateHz, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'}, mfilename, 'sampleRateHz');
if ~isvector(iq) && ~isempty(iq)
    error('radio:stream:detectActivityEpochs:IqShape', ...
        'IQ data must be a vector.');
end
iq = iq(:);
cfg = p.Results.Config;
required = {'chunkDurationSec', 'preTriggerSec', 'activity'};
missing = required(~isfield(cfg, required));
if ~isempty(missing)
    error('radio:stream:detectActivityEpochs:Config', ...
        'Streaming configuration is missing field: %s', missing{1});
end

chunkSamples = max(1, round(cfg.chunkDurationSec * sampleRateHz));
controller = radio.stream.channelControllerInit(sampleRateHz, ...
    'Config', cfg, ...
    'ChannelId', p.Results.ChannelId, ...
    'CenterFrequencyHz', p.Results.CenterFrequencyHz);
epochs = repmat(radio.stream.newEpoch( ...
    p.Results.ChannelId, 0, 0, 0), 0, 1);
lastCollectedEpochId = uint64(0);
activitySeen = false;

for first = 1:chunkSamples:numel(iq)
    last = min(numel(iq), first + chunkSamples - 1);
    chunk = radio.stream.makeIqChunk(iq(first:last), sampleRateHz, ...
        uint64(first - 1), ...
        'ChannelId', p.Results.ChannelId, ...
        'CenterFrequencyHz', p.Results.CenterFrequencyHz, ...
        'SequenceNumber', uint64(floor((first - 1) / chunkSamples)));
    [controller, output] = radio.stream.channelControllerFeed(controller, chunk);
    activitySeen = activitySeen || output.activity.isActive || ...
        strcmp(output.activity.phase, 'pending_on');
    [epochs, lastCollectedEpochId] = collectLastClosed( ...
        epochs, controller, lastCollectedEpochId);
end

[~, closedAtEof] = radio.stream.channelControllerFinalize( ...
    controller, uint64(numel(iq)), 'Reason', 'end_of_input');
if ~isempty(closedAtEof) && closedAtEof.epochId ~= lastCollectedEpochId
    epochs(end+1, 1) = closedAtEof;
end

preTriggerSamples = uint64(round(cfg.preTriggerSec * sampleRateHz));
previousEnd = uint64(0);
for k = 1:numel(epochs)
    if epochs(k).candidateStartSample >= preTriggerSamples
        desiredStart = epochs(k).candidateStartSample - preTriggerSamples;
    else
        desiredStart = uint64(0);
    end
    epochs(k).decodeStartSample = max(previousEnd, desiredStart);
    previousEnd = epochs(k).endSample;
end

report = struct( ...
    'sampleRateHz', double(sampleRateHz), ...
    'sourceSampleCount', uint64(numel(iq)), ...
    'chunkSamples', uint64(chunkSamples), ...
    'activitySeen', activitySeen, ...
    'epochCount', numel(epochs));
end

function [epochs, lastId] = collectLastClosed(epochs, controller, lastId)
closed = controller.lastClosedEpoch;
if isempty(closed) || closed.epochId == lastId
    return;
end
epochs(end+1, 1) = closed;
lastId = closed.epochId;
end
