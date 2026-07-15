function [ready, newSampleCount, minimumSampleCount] = ...
        lockedDecoderReady(state, buffer)
%LOCKEDDECODERREADY Rate-limit bounded-history decoder submissions.
if buffer.sampleRateHz ~= state.sampleRateHz
    error('radio:stream:lockedDecoderReady:SampleRate', ...
        'Decoder state and ring-buffer sample rates differ.');
end
if buffer.startSample > state.lastProcessedEndSample
    ready = true; % Submit once so the ordered decoder reports the overrun.
    newSampleCount = uint64(0);
else
    newSampleCount = buffer.endSample - state.lastProcessedEndSample;
    minimumSampleCount = uint64(max(1, round( ...
        state.incremental.minAdvanceSec * state.sampleRateHz)));
    ready = newSampleCount >= minimumSampleCount;
end
minimumSampleCount = uint64(max(1, round( ...
    state.incremental.minAdvanceSec * state.sampleRateHz)));
end
