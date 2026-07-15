function input = lockedDecoderPrepareInput(state, buffer)
%LOCKEDDECODERPREPAREINPUT Extract only undecoded IQ before worker transfer.
if buffer.sampleRateHz ~= state.sampleRateHz
    error('radio:stream:lockedDecoderPrepareInput:SampleRate', ...
        'Decoder state and ring-buffer sample rates differ.');
end
availableEndSample = buffer.endSample;
overrunSamples = uint64(0);
if buffer.startSample > state.lastProcessedEndSample
    overrunSamples = buffer.startSample - state.lastProcessedEndSample;
end
if availableEndSample <= state.lastProcessedEndSample || overrunSamples > 0
    chunk = [];
    targetEndSample = state.lastProcessedEndSample;
else
    maxAdvanceSamples = uint64(max(1, round( ...
        state.incremental.maxAdvanceSec * state.sampleRateHz)));
    targetEndSample = min(availableEndSample, ...
        state.lastProcessedEndSample + maxAdvanceSamples);
    chunk = radio.stream.ringBufferRange(buffer, ...
        state.lastProcessedEndSample, targetEndSample);
end
input = struct( ...
    'chunk', chunk, ...
    'availableEndSample', availableEndSample, ...
    'targetEndSample', targetEndSample, ...
    'overrunSamples', overrunSamples);
end
