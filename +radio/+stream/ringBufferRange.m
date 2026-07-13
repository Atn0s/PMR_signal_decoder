function chunk = ringBufferRange(buffer, startSample, endSample)
%RINGBUFFERRANGE Snapshot a zero-based, end-exclusive absolute sample range.
startSample = uint64(startSample);
endSample = uint64(endSample);
if endSample < startSample
    error('radio:stream:ringBufferRange:Range', ...
        'endSample must not precede startSample.');
end
if startSample < buffer.startSample || endSample > buffer.endSample
    error('radio:stream:ringBufferRange:Unavailable', ...
        'Requested range [%s, %s) is outside retained range [%s, %s).', ...
        string(startSample), string(endSample), ...
        string(buffer.startSample), string(buffer.endSample));
end

n = double(endSample - startSample);
if n == 0
    iq = complex(zeros(0, 1, 'single'));
else
    oldestPosition = mod(buffer.writePosition - buffer.count - 1, ...
        buffer.capacitySamples) + 1;
    offset = double(startSample - buffer.startSample);
    firstPosition = mod(oldestPosition - 1 + offset, ...
        buffer.capacitySamples) + 1;
    firstCount = min(n, buffer.capacitySamples - firstPosition + 1);
    iq = complex(zeros(n, 1, 'single'));
    iq(1:firstCount) = buffer.data(firstPosition:firstPosition+firstCount-1);
    if firstCount < n
        iq(firstCount+1:end) = buffer.data(1:n-firstCount);
    end
end

chunk = radio.stream.makeIqChunk(iq, buffer.sampleRateHz, startSample, ...
    'ChannelId', buffer.channelId, ...
    'SequenceNumber', buffer.lastSequenceNumber, ...
    'CenterFrequencyHz', buffer.centerFrequencyHz, ...
    'DroppedSourceSamples', buffer.droppedSourceSamples);
end
