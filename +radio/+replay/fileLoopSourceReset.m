function source = fileLoopSourceReset(source)
%FILELOOPSOURCERESET Rewind replay and reset its logical timeline.
if ~source.closed
    source.fileSource = radio.stream.fileSourceClose(source.fileSource);
end
source.fileSource = radio.stream.fileSourceInit(source.path, ...
    'SampleRateHz', source.options.sampleRateHz, ...
    'ChunkSamples', source.options.chunkSamples, ...
    'DType', source.options.iqDType, ...
    'HeaderBytes', source.options.headerBytes, ...
    'ChannelId', source.options.channelId, ...
    'CenterFrequencyHz', source.options.centerFrequencyHz);
source.silenceSamplesRemaining = uint64(0);
source.globalNextSample = uint64(0);
source.nextSequenceNumber = uint64(0);
source.currentLoop = uint64(1);
source.completedLoops = uint64(0);
source.atLoopStart = true;
source.pendingLoopDiscontinuity = false;
source.terminal = false;
source.closed = false;
end
