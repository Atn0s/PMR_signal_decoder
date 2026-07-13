function [buffer, event] = ringBufferPush(buffer, chunk)
%RINGBUFFERPUSH Append an IqChunk, resetting the continuous range on gaps.
radio.stream.validateIqChunk(chunk);
if chunk.sampleRateHz ~= buffer.sampleRateHz
    error('radio:stream:ringBufferPush:SampleRate', ...
        'Chunk and ring buffer sample rates differ.');
end
if ~isequal(chunk.channelId, buffer.channelId)
    error('radio:stream:ringBufferPush:ChannelId', ...
        'Chunk and ring buffer channel IDs differ.');
end

hasGap = buffer.count > 0 && chunk.sourceSampleStart ~= buffer.endSample;
mustReset = chunk.discontinuity || chunk.droppedSourceSamples > 0 || hasGap;
event = struct( ...
    'reset', logical(mustReset), ...
    'gapSamples', int64(0), ...
    'continuityGeneration', buffer.continuityGeneration, ...
    'retainedStartSample', chunk.sourceSampleStart, ...
    'retainedEndSample', chunk.sourceSampleEnd);
if hasGap
    event.gapSamples = sampleDifference(chunk.sourceSampleStart, buffer.endSample);
end
if mustReset
    buffer.writePosition = 1;
    buffer.count = 0;
    buffer.startSample = chunk.sourceSampleStart;
    buffer.endSample = chunk.sourceSampleStart;
    buffer.continuityGeneration = buffer.continuityGeneration + uint64(1);
    buffer.discontinuityCount = buffer.discontinuityCount + uint64(1);
end
buffer.droppedSourceSamples = buffer.droppedSourceSamples + ...
    chunk.droppedSourceSamples;
buffer.centerFrequencyHz = chunk.centerFrequencyHz;
buffer.lastSequenceNumber = chunk.sequenceNumber;

iq = chunk.iq(:);
nOriginal = numel(iq);
if nOriginal == 0
    event.continuityGeneration = buffer.continuityGeneration;
    event.retainedStartSample = buffer.startSample;
    event.retainedEndSample = buffer.endSample;
    return;
end
if nOriginal > buffer.capacitySamples
    iq = iq(end-buffer.capacitySamples+1:end);
    buffer.writePosition = 1;
    buffer.count = 0;
    buffer.startSample = chunk.sourceSampleEnd - uint64(numel(iq));
    buffer.endSample = buffer.startSample;
end

n = numel(iq);
oldCount = buffer.count;
if oldCount == 0
    buffer.startSample = chunk.sourceSampleEnd - uint64(n);
end
firstCount = min(n, buffer.capacitySamples - buffer.writePosition + 1);
buffer.data(buffer.writePosition:buffer.writePosition+firstCount-1) = ...
    single(iq(1:firstCount));
remaining = n - firstCount;
if remaining > 0
    buffer.data(1:remaining) = single(iq(firstCount+1:end));
end
buffer.writePosition = mod(buffer.writePosition - 1 + n, ...
    buffer.capacitySamples) + 1;

overflow = max(0, oldCount + n - buffer.capacitySamples);
buffer.startSample = buffer.startSample + uint64(overflow);
buffer.count = min(buffer.capacitySamples, oldCount + n);
buffer.endSample = chunk.sourceSampleEnd;

event.continuityGeneration = buffer.continuityGeneration;
event.retainedStartSample = buffer.startSample;
event.retainedEndSample = buffer.endSample;
end

function delta = sampleDifference(a, b)
if a >= b
    magnitude = a - b;
    delta = int64(min(magnitude, uint64(intmax('int64'))));
else
    magnitude = b - a;
    delta = -int64(min(magnitude, uint64(intmax('int64'))));
end
end
