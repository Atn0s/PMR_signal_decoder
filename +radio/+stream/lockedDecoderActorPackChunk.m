function [packed, payload] = lockedDecoderActorPackChunk(chunk)
%LOCKEDDECODERACTORPACKCHUNK Remove complex IQ and return a CI16 payload.
packed = chunk;
values = single(chunk.iq(:));
count = numel(values);
if count == 0
    payload = struct('sampleCount', uint64(0), ...
        'scale', single(1 / 32767), ...
        'realImag', zeros(0, 2, 'int16'));
else
    peak = max([max(abs(real(values))), max(abs(imag(values)))]);
    scale = max(single(1 / 32767), single(peak / 32760));
    realImag = int16(round([real(values), imag(values)] ./ scale));
    payload = struct('sampleCount', uint64(count), ...
        'scale', scale, 'realImag', realImag);
end
packed.iq = complex(zeros(0, 1, 'single'));
end
