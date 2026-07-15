function [packed, payload] = lockedDecoderActorPackInput(input)
%LOCKEDDECODERACTORPACKINPUT Quantize one actor IQ transfer to bounded CI16.
packed = input;
payload = [];
if ~isstruct(input.chunk), return; end
[packed.chunk, payload] = ...
    radio.stream.lockedDecoderActorPackChunk(input.chunk);
end
