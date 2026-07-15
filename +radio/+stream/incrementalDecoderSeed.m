function state = incrementalDecoderSeed(state, snapshot)
%INCREMENTALDECODERSEED Seed retained history without decoding it again.
radio.stream.validateIqChunk(snapshot);
if snapshot.sampleRateHz ~= state.sampleRateHz
    error('radio:stream:incrementalDecoderSeed:SampleRate', ...
        'Seed and incremental decoder sample rates differ.');
end
if isfield(state, 'nativeStreaming') && state.nativeStreaming
    state.nativeSeed = snapshot;
    state.nativeState = [];
    state.historyIq = complex(zeros(0, 1, 'single'));
    state.historyStartSample = snapshot.sourceSampleStart;
    state.nextExpectedSample = snapshot.sourceSampleEnd;
    return;
end
values = single(snapshot.iq(:));
if numel(values) > state.historyCapacitySamples
    drop = numel(values) - state.historyCapacitySamples;
    values = values(drop+1:end);
    startSample = snapshot.sourceSampleStart + uint64(drop);
else
    startSample = snapshot.sourceSampleStart;
end
state.historyIq = values;
state.historyStartSample = startSample;
state.nextExpectedSample = snapshot.sourceSampleEnd;
end
