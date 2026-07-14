function runStreamingPhase1()
%RUNSTREAMINGPHASE1 Deterministic tests for the streaming data skeleton.
testIqChunkContract();
testRawFileSource();
testRingBufferRanges();
testActivityAndController();
testDiscontinuityClosesEpoch();
fprintf('Streaming phase-1 tests passed.\n');
end

function testIqChunkContract()
iq = complex(single((1:5).'), single((6:10).'));
chunk = radio.stream.makeIqChunk(iq, 48000, uint64(100), ...
    'SequenceNumber', uint64(7), 'CenterFrequencyHz', 430e6);
assert(chunk.sourceSampleStart == uint64(100));
assert(chunk.sourceSampleEnd == uint64(105));
assert(chunk.sequenceNumber == uint64(7));
assert(chunk.timestampStartNs == uint64(round(100 / 48000 * 1e9)));
assert(isequal(chunk.iq, iq));

bad = chunk;
bad.sourceSampleEnd = bad.sourceSampleEnd + uint64(1);
assertThrows(@() radio.stream.validateIqChunk(bad), ...
    'radio:stream:validateIqChunk:SampleCount');
end

function testRawFileSource()
path = [tempname, '_1000.rawiq'];
fid = fopen(path, 'wb');
assert(fid >= 0);
fileCleanup = onCleanup(@() deleteIfPresent(path));
values = int16([100:109; -200:-191]);
interleaved = reshape(values, [], 1);
assert(fwrite(fid, interleaved, 'int16') == numel(interleaved));
fclose(fid);

source = radio.stream.fileSourceInit(path, ...
    'SampleRateHz', 1000, 'ChunkSamples', 4, 'DType', 'int16');
fidCleanup = onCleanup(@() closeIfOpen(source.fid));
allIq = complex(zeros(0, 1));
starts = uint64([]);
done = false;
while ~done
    [source, chunk, done] = radio.stream.fileSourceRead(source);
    starts(end+1) = chunk.sourceSampleStart; %#ok<AGROW>
    allIq = [allIq; chunk.iq]; %#ok<AGROW>
end
assert(isequal(starts, uint64([0, 4, 8])));
expected = complex(double(values(1, :)), double(values(2, :))).' ./ 32768;
assert(max(abs(allIq - expected)) < 1e-12);
[source, emptyChunk, done] = radio.stream.fileSourceRead(source);
assert(done && isempty(emptyChunk));
source = radio.stream.fileSourceClose(source);
clear fidCleanup fileCleanup;
end

function testRingBufferRanges()
buffer = radio.stream.ringBufferInit(10, 0.8);
chunk1 = radio.stream.makeIqChunk(complex((1:5).'), 10, 0);
chunk2 = radio.stream.makeIqChunk(complex((6:12).'), 10, 5, ...
    'SequenceNumber', 1);
[buffer, event1] = radio.stream.ringBufferPush(buffer, chunk1);
[buffer, event2] = radio.stream.ringBufferPush(buffer, chunk2);
assert(~event1.reset && ~event2.reset);
assert(buffer.startSample == uint64(4));
assert(buffer.endSample == uint64(12));
latest = radio.stream.ringBufferLatest(buffer, 1.0);
assert(isequal(double(latest.iq), complex((5:12).')));
middle = radio.stream.ringBufferRange(buffer, 6, 10);
assert(isequal(double(middle.iq), complex((7:10).')));

gap = radio.stream.makeIqChunk(complex((21:23).'), 10, 20, ...
    'SequenceNumber', 2);
[buffer, gapEvent] = radio.stream.ringBufferPush(buffer, gap);
assert(gapEvent.reset && gapEvent.gapSamples == int64(8));
assert(buffer.startSample == uint64(20) && buffer.endSample == uint64(23));
assert(isequal(double(radio.stream.ringBufferLatest(buffer, 1).iq), ...
    complex((21:23).')));
end

function testActivityAndController()
cfg = testConfig();
controller = radio.stream.channelControllerInit(100, 'Config', cfg);
noise = complex(1e-3 .* ones(3, 1));
signal = complex(ones(3, 1));

[controller, out] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(noise, 100, 0));
assert(strcmp(out.state, 'NO_SIGNAL'));
[controller, out] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(signal, 100, 3, 'SequenceNumber', 1));
assert(strcmp(out.state, 'ACTIVITY_PENDING'));
[controller, out] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(signal, 100, 6, 'SequenceNumber', 2));
assert(strcmp(out.state, 'CLASSIFYING'));
assert(controller.currentEpoch.candidateStartSample == uint64(3));
assert(controller.currentEpoch.epochId == uint64(1));
[controller, out] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(noise, 100, 9, 'SequenceNumber', 3));
assert(strcmp(out.state, 'CLASSIFYING'));
[controller, out] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(noise, 100, 12, 'SequenceNumber', 4));
assert(strcmp(out.state, 'NO_SIGNAL'));
assert(isempty(controller.currentEpoch));
assert(strcmp(controller.lastClosedEpoch.closeReason, ...
    'rf_activity_ended'));
end

function testDiscontinuityClosesEpoch()
cfg = testConfig();
controller = radio.stream.channelControllerInit(100, 'Config', cfg);
signal = complex(ones(3, 1));
[controller, ~] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(signal, 100, 0));
[controller, ~] = radio.stream.channelControllerFeed(controller, ...
    radio.stream.makeIqChunk(signal, 100, 3, 'SequenceNumber', 1));
oldEpochId = controller.currentEpoch.epochId;
discontinuous = radio.stream.makeIqChunk(signal, 100, 20, ...
    'SequenceNumber', 2, 'Discontinuity', true, ...
    'DroppedSourceSamples', 14);
[controller, out] = radio.stream.channelControllerFeed(controller, discontinuous);
assert(any(strcmp({out.events.type}, 'DISCONTINUITY')));
assert(strcmp(controller.lastClosedEpoch.closeReason, 'input_discontinuity'));
assert(controller.lastClosedEpoch.epochId == oldEpochId);
assert(strcmp(out.state, 'ACTIVITY_PENDING'));
assert(controller.ringBuffer.startSample == uint64(20));
assert(controller.ringBuffer.droppedSourceSamples == uint64(14));
end

function cfg = testConfig()
cfg = radio.stream.defaultConfig();
cfg.ringBufferSec = 1.0;
cfg.activity.initialNoiseFloorDb = -40;
cfg.activity.minOnSec = 0.05;
cfg.activity.offHangSec = 0.06;
cfg.activity.noiseUpdateAlpha = 0.05;
end

function assertThrows(fn, identifier)
didThrow = false;
try
    fn();
catch ME
    didThrow = strcmp(ME.identifier, identifier);
end
assert(didThrow);
end

function closeIfOpen(fid)
if isnumeric(fid) && isscalar(fid) && fid >= 0 && ~isempty(fopen(fid))
    fclose(fid);
end
end

function deleteIfPresent(path)
if exist(path, 'file') == 2
    delete(path);
end
end
