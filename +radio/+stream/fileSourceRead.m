function [source, chunk, done] = fileSourceRead(source)
%FILESOURCEREAD Read the next IqChunk from an initialized FileSource.
if source.closed
    error('radio:stream:fileSourceRead:Closed', 'FileSource is closed.');
end
if source.nextSample >= source.totalSamples
    chunk = [];
    done = true;
    return;
end

count = min(uint64(source.chunkSamples), ...
    source.totalSamples - source.nextSample);
startSample = source.nextSample;
if source.isWav
    first = double(startSample) + 1;
    last = first + double(count) - 1;
    samples = audioread(source.path, [first, last]);
    iq = complex(samples(:, 1), samples(:, 2));
else
    data = fread(source.fid, double(2 * count), source.freadPrecision);
    actualCount = floor(numel(data) / 2);
    data = data(1:2 * actualCount);
    iq = complex(double(data(1:2:end)), double(data(2:2:end))) ./ source.scale;
    count = uint64(actualCount);
end

chunk = radio.stream.makeIqChunk(iq, source.sampleRateHz, startSample, ...
    'ChannelId', source.channelId, ...
    'SequenceNumber', source.nextSequenceNumber, ...
    'CenterFrequencyHz', source.centerFrequencyHz);
source.nextSample = startSample + count;
source.nextSequenceNumber = source.nextSequenceNumber + uint64(1);
done = source.nextSample >= source.totalSamples;
end
