function [writer, sequence] = sharedIqRingWriteTransport( ...
        writer, packedChunk, payload)
%SHAREDIQRINGWRITETRANSPORT Commit an already quantized CI16 transport.
descriptor = writer.descriptor;
count = double(payload.sampleCount);
if count > double(descriptor.chunkSamples)
    error('radio:live:sharedIqRingWriteTransport:ChunkSize', ...
        'IQ chunk has %d samples; ring slots hold at most %d.', ...
        count, descriptor.chunkSamples);
end
if packedChunk.sampleRateHz ~= descriptor.sampleRateHz || ...
        packedChunk.sourceSampleEnd - packedChunk.sourceSampleStart ~= ...
            uint64(count)
    error('radio:live:sharedIqRingWriteTransport:Descriptor', ...
        'Packed IQ metadata does not match the shared-ring descriptor.');
end

sequence = writer.nextSequence;
slot = mod(double(sequence - uint64(1)), ...
    double(descriptor.capacityChunks)) + 1;
mapping = writer.mapping;
mapping.Data.beginSequence(slot) = uint64(0);
mapping.Data.endSequence(slot) = uint64(0);

raw = reshape(payload.realImag.', [], 1);
mapping.Data.iqRealImag(1:numel(raw), slot) = raw;
mapping.Data.sourceSampleStart(slot) = ...
    uint64(packedChunk.sourceSampleStart);
mapping.Data.sourceSampleEndBySlot(slot) = ...
    uint64(packedChunk.sourceSampleEnd);
mapping.Data.chunkSequenceNumber(slot) = ...
    uint64(packedChunk.sequenceNumber);
mapping.Data.timestampStartNs(slot) = ...
    uint64(packedChunk.timestampStartNs);
mapping.Data.droppedSourceSamples(slot) = ...
    uint64(packedChunk.droppedSourceSamples);
mapping.Data.sampleCount(slot) = uint32(count);
mapping.Data.flags(slot) = uint32(logical(packedChunk.discontinuity));
mapping.Data.scale(slot) = single(payload.scale);

% Publish the slot first, then advance the global live edge.
mapping.Data.endSequence(slot) = sequence;
mapping.Data.beginSequence(slot) = sequence;
mapping.Data.sourceSampleEnd = uint64(packedChunk.sourceSampleEnd);
mapping.Data.writeSequence = sequence;
writer.nextSequence = sequence + uint64(1);
writer.writeCount = writer.writeCount + uint64(1);
end
