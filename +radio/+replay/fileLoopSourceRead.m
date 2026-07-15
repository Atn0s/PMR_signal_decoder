function [source, chunk, done, event] = fileLoopSourceRead(source)
%FILELOOPSOURCEREAD Pull one globally-timestamped replay chunk.
if source.closed
    error('radio:replay:fileLoopSourceRead:Closed', ...
        'Replay source is closed.');
end
event = emptyEvent(source);
if source.terminal
    chunk = [];
    done = true;
    event.terminal = true;
    return;
end

if source.silenceSamplesRemaining > 0
    [source, chunk, event] = makeSilenceChunk(source, event);
    done = false;
    return;
end

[source.fileSource, localChunk, fileDone] = ...
    radio.stream.fileSourceRead(source.fileSource);
if isempty(localChunk)
    error('radio:replay:fileLoopSourceRead:UnexpectedEof', ...
        'The underlying source reached EOF without a terminal data chunk.');
end

loopStarted = source.atLoopStart;
discontinuity = source.pendingLoopDiscontinuity;
chunk = rebaseChunk(localChunk, source.globalNextSample, ...
    source.nextSequenceNumber, discontinuity, source);
source.globalNextSample = chunk.sourceSampleEnd;
source.nextSequenceNumber = source.nextSequenceNumber + uint64(1);
source.atLoopStart = false;
source.pendingLoopDiscontinuity = false;

event.type = 'data';
event.isData = true;
event.loopStarted = loopStarted;
event.loopIndex = source.currentLoop;
event.discontinuity = discontinuity;
event.sourceSampleStart = chunk.sourceSampleStart;
event.sourceSampleEnd = chunk.sourceSampleEnd;

if fileDone
    source.completedLoops = source.completedLoops + uint64(1);
    event.loopEnded = true;
    event.completedLoops = source.completedLoops;
    if double(source.completedLoops) >= source.maxLoops
        source.terminal = true;
        done = true;
        event.terminal = true;
        event.boundary = 'terminal';
    else
        source = reopenForNextLoop(source);
        if strcmp(source.replayMode, 'epoch-repeat')
            source.silenceSamplesRemaining = source.epochSilenceSamples;
            event.boundary = 'epoch-silence';
        else
            event.boundary = 'continuous-loop';
        end
        done = false;
    end
else
    done = false;
end
end

function [source, chunk, event] = makeSilenceChunk(source, event)
count = min(uint64(source.options.chunkSamples), ...
    source.silenceSamplesRemaining);
chunk = radio.stream.makeIqChunk( ...
    complex(zeros(double(count), 1)), source.metadata.sampleRateHz, ...
    source.globalNextSample, ...
    'ChannelId', source.options.channelId, ...
    'SequenceNumber', source.nextSequenceNumber, ...
    'CenterFrequencyHz', source.metadata.centerFrequencyHz);
chunk.replayLoopIndex = source.currentLoop - uint64(1);
chunk.replayMode = source.replayMode;
chunk.isReplaySilence = true;
chunk.syntheticContinuousReplay = source.syntheticContinuousReplay;
source.globalNextSample = chunk.sourceSampleEnd;
source.nextSequenceNumber = source.nextSequenceNumber + uint64(1);
source.silenceSamplesRemaining = ...
    source.silenceSamplesRemaining - count;
event.type = 'silence';
event.isSilence = true;
event.loopIndex = source.currentLoop - uint64(1);
event.completedLoops = source.completedLoops;
event.sourceSampleStart = chunk.sourceSampleStart;
event.sourceSampleEnd = chunk.sourceSampleEnd;
if source.silenceSamplesRemaining == 0
    source.pendingLoopDiscontinuity = true;
    event.boundary = 'epoch-silence-complete';
end
end

function source = reopenForNextLoop(source)
source.fileSource = radio.stream.fileSourceClose(source.fileSource);
source.fileSource = radio.stream.fileSourceInit(source.path, ...
    'SampleRateHz', source.options.sampleRateHz, ...
    'ChunkSamples', source.options.chunkSamples, ...
    'DType', source.options.iqDType, ...
    'HeaderBytes', source.options.headerBytes, ...
    'ChannelId', source.options.channelId, ...
    'CenterFrequencyHz', source.options.centerFrequencyHz);
source.currentLoop = source.completedLoops + uint64(1);
source.atLoopStart = true;
end

function chunk = rebaseChunk(localChunk, startSample, sequenceNumber, ...
        discontinuity, source)
chunk = radio.stream.makeIqChunk( ...
    localChunk.iq, localChunk.sampleRateHz, startSample, ...
    'ChannelId', localChunk.channelId, ...
    'SequenceNumber', sequenceNumber, ...
    'CenterFrequencyHz', localChunk.centerFrequencyHz, ...
    'Discontinuity', discontinuity, ...
    'DroppedSourceSamples', localChunk.droppedSourceSamples);
chunk.fileSampleStart = localChunk.sourceSampleStart;
chunk.fileSampleEnd = localChunk.sourceSampleEnd;
chunk.replayLoopIndex = source.currentLoop;
chunk.replayMode = source.replayMode;
chunk.isReplaySilence = false;
chunk.syntheticContinuousReplay = source.syntheticContinuousReplay;
end

function event = emptyEvent(source)
event = struct( ...
    'type', 'none', ...
    'isData', false, ...
    'isSilence', false, ...
    'loopStarted', false, ...
    'loopEnded', false, ...
    'loopIndex', source.currentLoop, ...
    'completedLoops', source.completedLoops, ...
    'boundary', '', ...
    'discontinuity', false, ...
    'terminal', false, ...
    'sourceSampleStart', source.globalNextSample, ...
    'sourceSampleEnd', source.globalNextSample);
end
