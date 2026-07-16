function [writer, sequence] = sharedIqRingWrite(writer, chunk)
%SHAREDIQRINGWRITE Commit one IQ block without sending it through the UI.
radio.stream.validateIqChunk(chunk);
descriptor = writer.descriptor;
if chunk.sampleRateHz ~= descriptor.sampleRateHz
    error('radio:live:sharedIqRingWrite:SampleRate', ...
        'IQ sample rate changed inside a shared ring.');
end
[packed, payload] = radio.stream.lockedDecoderActorPackChunk(chunk);
[writer, sequence] = radio.live.sharedIqRingWriteTransport( ...
    writer, packed, payload);
end
