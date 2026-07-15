function chunk = lockedDecoderActorUnpackChunk(chunk, payload)
%LOCKEDDECODERACTORUNPACKCHUNK Restore complex-single IQ from CI16 payload.
count = double(payload.sampleCount);
if count == 0
    chunk.iq = complex(zeros(0, 1, 'single'));
    return;
end
values = single(payload.realImag) .* single(payload.scale);
chunk.iq = complex(values(:, 1), values(:, 2));
end
