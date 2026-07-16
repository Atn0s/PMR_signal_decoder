function [reader, chunk, status] = sharedIqRingRead(reader)
%SHAREDIQRINGREAD Read the next committed slot or report bounded overrun.
chunk = [];
mapping = reader.mapping;
descriptor = reader.descriptor;
expected = reader.nextSequence;
writeSequence = uint64(mapping.Data.writeSequence);
sourceSampleEnd = uint64(mapping.Data.sourceSampleEnd);
terminal = logical(mapping.Data.terminal);
capacity = uint64(descriptor.capacityChunks);

earliest = uint64(1);
if writeSequence >= capacity
    earliest = writeSequence - capacity + uint64(1);
end
if expected < earliest
    lost = earliest - expected;
    mapping.Data.overrunCount = mapping.Data.overrunCount + uint64(1);
    status = makeStatus('overrun', expected, writeSequence, ...
        sourceSampleEnd, terminal, lost);
    return;
end
if expected > writeSequence
    state = 'empty';
    if terminal, state = 'drained'; end
    status = makeStatus(state, expected, writeSequence, ...
        sourceSampleEnd, terminal, uint64(0));
    return;
end

slot = mod(double(expected - uint64(1)), ...
    double(descriptor.capacityChunks)) + 1;
beginBefore = uint64(mapping.Data.beginSequence(slot));
if beginBefore ~= expected
    status = makeStatus('pending_commit', expected, writeSequence, ...
        sourceSampleEnd, terminal, uint64(0));
    return;
end
count = double(mapping.Data.sampleCount(slot));
if count < 0 || count > double(descriptor.chunkSamples)
    status = makeStatus('torn_read', expected, writeSequence, ...
        sourceSampleEnd, terminal, uint64(0));
    return;
end
raw = mapping.Data.iqRealImag(1:2 * count, slot);
startSample = uint64(mapping.Data.sourceSampleStart(slot));
endSample = uint64(mapping.Data.sourceSampleEndBySlot(slot));
chunkSequence = uint64(mapping.Data.chunkSequenceNumber(slot));
timestampStartNs = uint64(mapping.Data.timestampStartNs(slot));
droppedSamples = uint64(mapping.Data.droppedSourceSamples(slot));
flags = uint32(mapping.Data.flags(slot));
scale = single(mapping.Data.scale(slot));
endAfter = uint64(mapping.Data.endSequence(slot));
beginAfter = uint64(mapping.Data.beginSequence(slot));
if beginAfter ~= expected || endAfter ~= expected || ...
        beginBefore ~= beginAfter
    status = makeStatus('torn_read', expected, writeSequence, ...
        sourceSampleEnd, terminal, uint64(0));
    return;
end

realImag = reshape(raw, 2, count).';
iq = complex(single(realImag(:, 1)), single(realImag(:, 2))) .* scale;
chunk = radio.stream.makeIqChunk(iq, descriptor.sampleRateHz, ...
    startSample, 'SequenceNumber', chunkSequence, ...
    'TimestampStartNs', timestampStartNs, ...
    'CenterFrequencyHz', descriptor.centerFrequencyHz, ...
    'Discontinuity', bitand(flags, uint32(1)) ~= 0, ...
    'DroppedSourceSamples', droppedSamples);
if chunk.sourceSampleEnd ~= endSample
    error('radio:live:sharedIqRingRead:SampleRange', ...
        'Committed shared-ring metadata has an invalid sample range.');
end
reader.nextSequence = expected + uint64(1);
reader.readCount = reader.readCount + uint64(1);
reader.lastSourceSampleEnd = endSample;
mapping.Data.consumerSequence = expected;
status = makeStatus('chunk', expected, writeSequence, ...
    sourceSampleEnd, terminal, uint64(0));
end

function status = makeStatus(state, sequence, writeSequence, ...
        sourceSampleEnd, terminal, lostChunks)
status = struct( ...
    'state', state, ...
    'sequence', uint64(sequence), ...
    'writeSequence', uint64(writeSequence), ...
    'sourceSampleEnd', uint64(sourceSampleEnd), ...
    'terminal', logical(terminal), ...
    'lostChunks', uint64(lostChunks));
end
