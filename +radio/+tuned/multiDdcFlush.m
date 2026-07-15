function [state, outputChunks] = multiDdcFlush(state, varargin)
%MULTIDDCFLUSH Flush the shared matrix decimation filters.
p = inputParser;
p.addParameter('TailDurationSec', state.config.filterFlushSec);
p.parse(varargin{:});
if isempty(state.expectedInputSample)
    outputChunks = cell(0, 1);
    return;
end
zeroCount = max(0, round( ...
    p.Results.TailDurationSec * state.inputSampleRateHz));
remainder = mod(numel(state.pendingIq) + zeroCount, ...
    state.inputBlockSamples);
if remainder ~= 0
    zeroCount = zeroCount + state.inputBlockSamples - remainder;
end
if zeroCount == 0
    outputChunks = cell(0, 1);
    return;
end
actualInputEnd = uint64(state.expectedInputSample);
padding = radio.stream.makeIqChunk( ...
    complex(zeros(zeroCount, 1)), state.inputSampleRateHz, actualInputEnd, ...
    'CenterFrequencyHz', state.inputCenterFrequencyHz);
[state, outputChunks] = radio.tuned.multiDdcFeed(state, padding);
for k = 1:numel(outputChunks)
    outputChunks{k}.isFilterFlush = true;
    outputChunks{k}.actualWidebandSourceSampleEnd = actualInputEnd;
    outputChunks{k}.filterFlushInputSamples = uint64(zeroCount);
end
end
