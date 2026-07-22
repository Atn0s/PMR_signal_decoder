function report = runP25Streaming()
%RUNP25STREAMING Validate causal P25 state across arbitrary IQ chunks.
path = fullfile(common.sampleDataRoot(), ...
    'p25_1_78125.rawiq');
if exist(path, 'file') ~= 2
    fprintf('[SKIP] P25 streaming sample is not present.\n');
    report = struct('skipped', true);
    return;
end
fs = 78125;
iq = common.readRawIq(path);
iq = iq(1:min(numel(iq), round(3.0 * fs)));
cfg = p25.config();

timer = tic;
targetIq = common.resampleTo(iq, fs, cfg.targetSampleRateHz);
offlinePdus = p25.decode( ...
    p25.frontend(targetIq, cfg.targetSampleRateHz, cfg), cfg);
offlineElapsed = toc(timer);

scheduleA = round(fs .* [0.037 0.083 0.211 0.059 0.127]);
scheduleB = round(fs .* [0.200 0.200 0.200]);
[streamA, samplesA, stateA, elapsedA] = ...
    decodeChunks(iq, fs, cfg, scheduleA);
[streamB, samplesB, stateB, elapsedB] = ...
    decodeChunks(iq, fs, cfg, scheduleB);

keysA = signatures(streamA);
keysB = signatures(streamB);
offlineKeys = signatures(offlinePdus);
assert(isequal(keysA, keysB), ...
    'P25 streaming PDU output changed with IQ chunk boundaries.');
assert(isequal(samplesA, samplesB), ...
    'P25 streaming source positions changed with IQ chunk boundaries.');
assert(~isempty(keysA) && numel(offlineKeys) >= numel(keysA));
assert(isequal(keysA, offlineKeys(1:numel(keysA))), ...
    'P25 streaming content is not an ordered prefix of the offline decode.');
assert(all(arrayfun(@(item) logical(radio.getNestedField( ...
    item, 'extra.valid_bch', false)), streamA)));
assert(stateA.maxDemodBufferSamples < ...
    uint64(round(1.20 * cfg.targetSampleRateHz)));
assert(stateB.maxDemodBufferSamples < ...
    uint64(round(1.20 * cfg.targetSampleRateHz)));

% Exercise the normal 2.5 MHz DDC output rate with unrelated chunking.
tunedFs = 125000;
tunedSourceCount = min(numel(iq), round(2.0 * fs));
tunedIq = common.resampleTo(iq(1:tunedSourceCount), fs, tunedFs);
[tunedA, tunedSamplesA] = decodeChunks( ...
    tunedIq, tunedFs, cfg, round(tunedFs .* [0.041 0.097 0.203]));
[tunedB, tunedSamplesB] = decodeChunks( ...
    tunedIq, tunedFs, cfg, round(tunedFs .* [0.125 0.250]));
assert(~isempty(tunedA));
assert(isequal(signatures(tunedA), signatures(tunedB)));
assert(isequal(tunedSamplesA, tunedSamplesB));

report = struct( ...
    'skipped', false, ...
    'offlinePduCount', numel(offlinePdus), ...
    'streamPduCount', numel(streamA), ...
    'streamValidFrames', double(stateA.frameState.validFrameCount), ...
    'offlineElapsedSec', offlineElapsed, ...
    'streamElapsedSec', elapsedA, ...
    'secondScheduleElapsedSec', elapsedB, ...
    'streamRealtimeFactor', elapsedA / (numel(iq) / fs), ...
    'warmRealtimeFactor', elapsedB / (numel(iq) / fs), ...
    'maxDemodBufferSamples', double(stateA.maxDemodBufferSamples));
fprintf(['P25 streaming: offline=%d PDU, stream=%d PDU, ', ...
    'valid frames=%d, cold/warm RTF=%.3f/%.3f.\n'], ...
    report.offlinePduCount, report.streamPduCount, ...
    report.streamValidFrames, report.streamRealtimeFactor, ...
    report.warmRealtimeFactor);
end

function [pdus, sourceSamples, state, elapsed] = ...
        decodeChunks(iq, fs, cfg, schedule)
state = p25.streamInit(fs, cfg, 'SourceSampleStart', uint64(0));
pdus = struct([]);
sourceSamples = zeros(0, 1, 'uint64');
position = 1;
sequence = uint64(0);
scheduleIndex = 1;
timer = tic;
while position <= numel(iq)
    count = min(schedule(scheduleIndex), numel(iq) - position + 1);
    chunk = radio.stream.makeIqChunk( ...
        iq(position:position+count-1), fs, uint64(position-1), ...
        'SequenceNumber', sequence);
    [state, output] = p25.streamDecodeChunk(state, chunk);
    pdus = appendPdus(pdus, output.pdus);
    sourceSamples = [sourceSamples; output.sourceSamples(:)]; %#ok<AGROW>
    position = position + count;
    sequence = sequence + uint64(1);
    scheduleIndex = mod(scheduleIndex, numel(schedule)) + 1;
end
[state, output] = p25.streamFlush(state);
pdus = appendPdus(pdus, output.pdus);
sourceSamples = [sourceSamples; output.sourceSamples(:)];
elapsed = toc(timer);
pdus = p25.postprocess(pdus);
end

function keys = signatures(pdus)
keys = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    keys{k} = jsonencode({ ...
        pdus(k).type, ...
        radio.getNestedField(pdus(k), 'extra.nac', []), ...
        radio.getNestedField(pdus(k), 'extra.duid', []), ...
        pdus(k).src, pdus(k).dst, pdus(k).flco});
end
end

function value = appendPdus(value, items)
if isempty(items), return; end
if isempty(value)
    value = items;
else
    value(end+1:end+numel(items)) = items;
end
end
