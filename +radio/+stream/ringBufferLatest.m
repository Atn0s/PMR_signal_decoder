function chunk = ringBufferLatest(buffer, durationSec)
%RINGBUFFERLATEST Snapshot up to durationSec from the newest retained IQ.
validateattributes(durationSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
requested = min(buffer.count, round(durationSec * buffer.sampleRateHz));
startSample = buffer.endSample - uint64(requested);
chunk = radio.stream.ringBufferRange(buffer, startSample, buffer.endSample);
end
