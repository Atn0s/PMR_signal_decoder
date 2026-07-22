function report = runDmrStreaming()
%RUNDMRSTREAMING Validate causal DMR state across arbitrary IQ chunks.
path = fullfile(common.sampleDataRoot(), ...
    'dmr_1_78125.rawiq');
if exist(path, 'file') ~= 2
    fprintf('[SKIP] DMR streaming sample is not present.\n');
    report = struct('skipped', true);
    return;
end
fs = 78125;
allIq = common.readRawIq(path);
base = round(0.5 * fs);
iq = allIq(base+1:min(numel(allIq), base + round(3.0 * fs)));
cfg = dmr.config();

timer = tic;
targetIq = common.resampleTo(iq, fs, cfg.targetSampleRateHz);
offlinePdus = dmr.decode( ...
    dmr.frontend(targetIq, cfg.targetSampleRateHz, cfg), cfg);
offlineElapsed = toc(timer);

scheduleA = round(fs .* [0.037 0.083 0.211 0.059 0.127]);
scheduleB = round(fs .* [0.200 0.200 0.200]);
[streamA, samplesA, stateA, elapsedA] = ...
    decodeChunks(iq, fs, uint64(base), cfg, scheduleA);
[streamB, samplesB, stateB, elapsedB] = ...
    decodeChunks(iq, fs, uint64(base), cfg, scheduleB);
assert(isequal(signatures(streamA), signatures(streamB)), ...
    'DMR streaming PDU output changed with IQ chunk boundaries.');
assert(isequal(samplesA, samplesB), ...
    'DMR streaming source positions changed with IQ chunk boundaries.');
assert(~isempty(streamA) && stateA.frameState.strongPduCount > 0);
assert(~isempty(intersect(unique(signatures(streamA)), ...
    unique(signatures(offlinePdus)))), ...
    'DMR streaming output has no semantic overlap with the offline decode.');
assert(stateA.maxDemodBufferSamples < ...
    uint64(round(1.50 * cfg.targetSampleRateHz)));
assert(stateB.maxDemodBufferSamples < ...
    uint64(round(1.50 * cfg.targetSampleRateHz)));

tunedFs = 125000;
tunedIq = common.resampleTo(iq, fs, tunedFs);
[tunedA, tunedSamplesA] = decodeChunks(tunedIq, tunedFs, ...
    uint64(0), cfg, round(tunedFs .* [0.041 0.097 0.203]));
[tunedB, tunedSamplesB] = decodeChunks(tunedIq, tunedFs, ...
    uint64(0), cfg, round(tunedFs .* [0.125 0.250]));
assert(~isempty(tunedA));
assert(isequal(signatures(tunedA), signatures(tunedB)));
assert(isequal(tunedSamplesA, tunedSamplesB));

durationSec = numel(iq) / fs;
report = struct( ...
    'skipped', false, ...
    'offlinePduCount', numel(offlinePdus), ...
    'streamPduCount', numel(streamA), ...
    'streamStrongPduCount', double(stateA.frameState.strongPduCount), ...
    'offlineElapsedSec', offlineElapsed, ...
    'streamElapsedSec', elapsedA, ...
    'secondScheduleElapsedSec', elapsedB, ...
    'streamRealtimeFactor', elapsedA / durationSec, ...
    'warmRealtimeFactor', elapsedB / durationSec, ...
    'maxDemodBufferSamples', double(stateA.maxDemodBufferSamples));
fprintf(['DMR streaming: offline=%d PDU, stream=%d PDU, ', ...
    'strong=%d, cold/warm RTF=%.3f/%.3f.\n'], ...
    report.offlinePduCount, report.streamPduCount, ...
    report.streamStrongPduCount, report.streamRealtimeFactor, ...
    report.warmRealtimeFactor);
end

function [pdus, sourceSamples, state, elapsed] = ...
        decodeChunks(iq, fs, sourceStart, cfg, schedule)
state = dmr.streamInit(fs, cfg, 'SourceSampleStart', sourceStart);
pdus = struct([]);
sourceSamples = zeros(0, 1, 'uint64');
position = 1;
sequence = uint64(0);
scheduleIndex = 1;
timer = tic;
while position <= numel(iq)
    count = min(schedule(scheduleIndex), numel(iq) - position + 1);
    chunk = radio.stream.makeIqChunk( ...
        iq(position:position+count-1), fs, ...
        sourceStart + uint64(position-1), ...
        'SequenceNumber', sequence);
    [state, output] = dmr.streamDecodeChunk(state, chunk);
    pdus = appendPdus(pdus, output.pdus);
    sourceSamples = [sourceSamples; output.sourceSamples(:)]; %#ok<AGROW>
    position = position + count;
    sequence = sequence + uint64(1);
    scheduleIndex = mod(scheduleIndex, numel(schedule)) + 1;
end
[state, output] = dmr.streamFlush(state);
pdus = appendPdus(pdus, output.pdus);
sourceSamples = [sourceSamples; output.sourceSamples(:)];
elapsed = toc(timer);
pdus = dmr.postprocess(pdus);
end

function keys = signatures(pdus)
keys = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    keys{k} = jsonencode({pdus(k).type, pdus(k).src, pdus(k).dst, ...
        pdus(k).flco, pdus(k).fid});
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
