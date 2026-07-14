function [state, outputChunk] = ddcFlush(state, varargin)
%DDCFLUSH Emit a short zero tail so the decimation filters can settle.
p = inputParser;
p.addParameter('TailDurationSec', state.config.filterFlushSec);
p.parse(varargin{:});
validateattributes(p.Results.TailDurationSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});

if isempty(state.expectedInputSample)
    outputChunk = [];
    return;
end
tailSamples = round(p.Results.TailDurationSec * state.inputSampleRateHz);
zeroCount = max(0, tailSamples);
remainder = mod(numel(state.pendingIq) + zeroCount, ...
    state.inputBlockSamples);
if remainder ~= 0
    zeroCount = zeroCount + state.inputBlockSamples - remainder;
end
if zeroCount == 0
    outputChunk = [];
    return;
end

actualInputEnd = uint64(state.expectedInputSample);
padding = radio.stream.makeIqChunk( ...
    complex(zeros(zeroCount, 1)), state.inputSampleRateHz, actualInputEnd, ...
    'ChannelId', state.channelId, ...
    'CenterFrequencyHz', state.inputCenterFrequencyHz);
[state, outputChunk] = radio.tuned.ddcFeed(state, padding);
if ~isempty(outputChunk)
    outputChunk.isFilterFlush = true;
    outputChunk.actualWidebandSourceSampleEnd = actualInputEnd;
    outputChunk.filterFlushInputSamples = uint64(zeroCount);
end
end
