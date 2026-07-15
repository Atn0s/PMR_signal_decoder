function runRealtimeFrontendPhase1()
%RUNREALTIMEFRONTENDPHASE1 Test pull-based looping file replay.
path = makeRawFixture();
cleanup = onCleanup(@() deleteIfPresent(path));
testContinuousReplay(path);
testEpochReplay(path);
testGuards(path);
clear cleanup;
fprintf('Realtime frontend phase-1 replay-source tests passed.\n');
end

function testContinuousReplay(path)
source = radio.replay.fileLoopSourceInit(path, ...
    'SampleRate', 100, ...
    'ChunkSamples', 2, ...
    'ReplayMode', 'continuous-test', ...
    'MaxLoops', 3);
starts = uint64([]);
counts = [];
loops = uint64([]);
loopStarts = false(1, 0);
loopEnds = false(1, 0);
discontinuities = false(1, 0);
allIq = complex(zeros(0, 1));
done = false;
while ~done
    [source, chunk, done, event] = ...
        radio.replay.fileLoopSourceRead(source);
    assert(~isempty(chunk) && event.isData && ~event.isSilence);
    starts(end+1) = chunk.sourceSampleStart; %#ok<AGROW>
    counts(end+1) = numel(chunk.iq); %#ok<AGROW>
    loops(end+1) = chunk.replayLoopIndex; %#ok<AGROW>
    loopStarts(end+1) = event.loopStarted; %#ok<AGROW>
    loopEnds(end+1) = event.loopEnded; %#ok<AGROW>
    discontinuities(end+1) = chunk.discontinuity; %#ok<AGROW>
    allIq = [allIq; chunk.iq]; %#ok<AGROW>
end
assert(isequal(starts, uint64([0 2 4 5 7 9 10 12 14])));
assert(isequal(counts, [2 2 1 2 2 1 2 2 1]));
assert(isequal(loops, uint64([1 1 1 2 2 2 3 3 3])));
assert(isequal(find(loopStarts), [1 4 7]));
assert(isequal(find(loopEnds), [3 6 9]));
assert(~any(discontinuities));
assert(numel(allIq) == 15);
assert(source.completedLoops == uint64(3));
assert(source.globalNextSample == uint64(15));
assert(source.syntheticContinuousReplay);

source = radio.replay.fileLoopSourceReset(source);
[source, chunk, done, event] = radio.replay.fileLoopSourceRead(source);
assert(~done && event.loopStarted);
assert(chunk.sourceSampleStart == uint64(0));
assert(chunk.sequenceNumber == uint64(0));
source = radio.replay.fileLoopSourceClose(source);
assert(source.closed);
end

function testEpochReplay(path)
source = radio.replay.fileLoopSourceInit(path, ...
    'SampleRate', 100, ...
    'ChunkSamples', 2, ...
    'ReplayMode', 'epoch-repeat', ...
    'EpochSilenceSec', 0.03, ...
    'MaxLoops', 2);
chunks = cell(0, 1);
events = cell(0, 1);
done = false;
while ~done
    [source, chunk, done, event] = ...
        radio.replay.fileLoopSourceRead(source);
    chunks{end+1, 1} = chunk; %#ok<AGROW>
    events{end+1, 1} = event; %#ok<AGROW>
end
assert(numel(chunks) == 8);
assert(isequal([chunks{1}.sourceSampleStart, ...
    chunks{2}.sourceSampleStart, chunks{3}.sourceSampleStart], ...
    uint64([0 2 4])));
assert(chunks{4}.isReplaySilence && chunks{5}.isReplaySilence);
assert(isequal([numel(chunks{4}.iq), numel(chunks{5}.iq)], [2 1]));
assert(all(chunks{4}.iq == 0) && all(chunks{5}.iq == 0));
assert(chunks{6}.sourceSampleStart == uint64(8));
assert(chunks{6}.discontinuity);
assert(events{6}.loopStarted && events{6}.loopIndex == uint64(2));
assert(chunks{8}.sourceSampleEnd == uint64(13));
assert(source.completedLoops == uint64(2));
source = radio.replay.fileLoopSourceClose(source);
assert(source.closed);
end

function testGuards(path)
assertThrows(@() radio.replay.fileLoopSourceInit(path, ...
    'SampleRate', 100, 'ReplayMode', 'bad-mode'), ...
    'radio:replay:fileLoopSourceInit:ReplayMode');
assertThrows(@() radio.replay.fileLoopSourceInit(path, ...
    'SampleRate', 100, 'ReplayMode', 'epoch-repeat', ...
    'EpochSilenceSec', 0), ...
    'radio:replay:fileLoopSourceInit:EpochSilence');
end

function path = makeRawFixture()
path = [tempname, '.rawiq'];
fid = fopen(path, 'wb', 'ieee-le');
assert(fid >= 0);
values = int16([100:104; -200:-196]);
assert(fwrite(fid, values(:), 'int16') == 10);
fclose(fid);
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

function deleteIfPresent(path)
if exist(path, 'file') == 2
    delete(path);
end
end
