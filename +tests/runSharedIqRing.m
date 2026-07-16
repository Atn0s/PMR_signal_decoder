function runSharedIqRing()
%RUNSHAREDIQRING Verify ordered commit, wrap detection, and terminal drain.
fs = 1000;
chunkSamples = 10;
descriptor = radio.live.sharedIqRingCreate( ...
    fs, chunkSamples, 'CenterFrequencyHz', 11e6, ...
    'CapacitySec', 0.03);
cleanup = onCleanup(@() radio.live.sharedIqRingDelete(descriptor));
writer = radio.live.sharedIqRingWriter(descriptor);
expected = cell(4, 1);
for k = 1:4
    values = complex(single((1:chunkSamples).' / (20 + k)), ...
        single(-(1:chunkSamples).' / (30 + k)));
    expected{k} = values;
    chunk = radio.stream.makeIqChunk(values, fs, (k - 1) * chunkSamples, ...
        'SequenceNumber', uint64(k - 1), ...
        'CenterFrequencyHz', descriptor.centerFrequencyHz, ...
        'Discontinuity', k == 3);
    [writer, sequence] = radio.live.sharedIqRingWrite(writer, chunk);
    assert(sequence == uint64(k));
end

reader = radio.live.sharedIqRingReader(descriptor, uint64(1));
[reader, chunk, status] = radio.live.sharedIqRingRead(reader); %#ok<ASGLU>
assert(isempty(chunk) && strcmp(status.state, 'overrun'));
assert(status.lostChunks == uint64(1));

reader = radio.live.sharedIqRingReader(descriptor, uint64(2));
for k = 2:4
    [reader, chunk, status] = radio.live.sharedIqRingRead(reader);
    assert(strcmp(status.state, 'chunk'));
    assert(chunk.sourceSampleStart == uint64((k - 1) * chunkSamples));
    assert(chunk.discontinuity == (k == 3));
    assert(max(abs(chunk.iq - expected{k})) < 1e-4);
end
writer = radio.live.sharedIqRingMarkTerminal(writer, false);
[reader, chunk, status] = radio.live.sharedIqRingRead(reader); %#ok<ASGLU>
assert(isempty(chunk) && strcmp(status.state, 'drained'));
snapshot = radio.live.sharedIqRingSnapshot(descriptor);
assert(snapshot.terminal && snapshot.writeSequence == uint64(4));
assert(snapshot.consumerSequence == uint64(4));
clear cleanup;
fprintf('Shared IQ ring tests passed.\n');
end
