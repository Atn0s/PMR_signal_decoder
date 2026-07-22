function report = runDpmrStreaming()
%RUNDPMRSTREAMING Validate causal dPMR state across arbitrary IQ chunks.
path = fullfile(common.sampleDataRoot(), ...
    'dpmr_1_48000.rawiq');
if exist(path, 'file') ~= 2
    fprintf('[SKIP] dPMR streaming sample is not present.\n');
    report = struct('skipped', true);
    return;
end
fs = 48000;
allIq = common.readRawIq(path);
iq = allIq(1:min(numel(allIq), round(4.0 * fs)));
cfg = dpmr.config();

timer = tic;
targetIq = common.resampleTo(iq, fs, cfg.targetSampleRateHz);
offlinePdus = dpmr.decode( ...
    dpmr.frontend(targetIq, cfg.targetSampleRateHz, cfg), cfg);
offlineElapsed = toc(timer);

scheduleA = round(fs .* [0.037 0.083 0.211 0.059 0.127]);
scheduleB = round(fs .* [0.200 0.200 0.200]);
[streamA, samplesA, stateA, elapsedA] = ...
    decodeChunks(iq, fs, cfg, scheduleA);
[streamB, samplesB, stateB, elapsedB] = ...
    decodeChunks(iq, fs, cfg, scheduleB);
assert(isequal(signatures(streamA), signatures(streamB)), ...
    'dPMR streaming PDU output changed with IQ chunk boundaries.');
assert(isequal(samplesA, samplesB), ...
    'dPMR streaming source positions changed with IQ chunk boundaries.');
assert(~isempty(streamA) && stateA.frameState.crcValidPduCount > 0);
assert(isequal(sort(signatures(streamA)), sort(signatures(offlinePdus))), ...
    'dPMR streaming output differs semantically from offline decode.');
assert(stateA.maxDemodBufferSamples < ...
    uint64(round(1.50 * cfg.targetSampleRateHz)));
assert(stateB.maxDemodBufferSamples < ...
    uint64(round(1.50 * cfg.targetSampleRateHz)));

% Exercise the normal tuned-DDC output rate with unrelated chunking.
tunedFs = 125000;
tunedIq = common.resampleTo(iq, fs, tunedFs);
[tunedA, tunedSamplesA] = decodeChunks(tunedIq, tunedFs, cfg, ...
    round(tunedFs .* [0.041 0.097 0.203]));
[tunedB, tunedSamplesB] = decodeChunks(tunedIq, tunedFs, cfg, ...
    round(tunedFs .* [0.125 0.250]));
assert(~isempty(tunedA));
assert(isequal(signatures(tunedA), signatures(tunedB)));
assert(isequal(tunedSamplesA, tunedSamplesB));

durationSec = numel(iq) / fs;
report = struct( ...
    'skipped', false, ...
    'offlinePduCount', numel(offlinePdus), ...
    'streamPduCount', numel(streamA), ...
    'streamCrcValidPduCount', ...
        double(stateA.frameState.crcValidPduCount), ...
    'offlineElapsedSec', offlineElapsed, ...
    'streamElapsedSec', elapsedA, ...
    'secondScheduleElapsedSec', elapsedB, ...
    'streamRealtimeFactor', elapsedA / durationSec, ...
    'warmRealtimeFactor', elapsedB / durationSec, ...
    'maxDemodBufferSamples', double(stateA.maxDemodBufferSamples));
fprintf(['dPMR streaming: offline=%d PDU, stream=%d PDU, ', ...
    'CRC-valid=%d, cold/warm RTF=%.3f/%.3f.\n'], ...
    report.offlinePduCount, report.streamPduCount, ...
    report.streamCrcValidPduCount, report.streamRealtimeFactor, ...
    report.warmRealtimeFactor);
end

function [pdus, sourceSamples, state, elapsed] = ...
        decodeChunks(iq, fs, cfg, schedule)
state = dpmr.streamInit(fs, cfg, 'SourceSampleStart', uint64(0));
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
    [state, output] = dpmr.streamDecodeChunk(state, chunk);
    pdus = appendPdus(pdus, output.pdus);
    sourceSamples = [sourceSamples; output.sourceSamples(:)]; %#ok<AGROW>
    position = position + count;
    sequence = sequence + uint64(1);
    scheduleIndex = mod(scheduleIndex, numel(schedule)) + 1;
end
[state, output] = dpmr.streamFlush(state);
pdus = appendPdus(pdus, output.pdus);
sourceSamples = [sourceSamples; output.sourceSamples(:)];
elapsed = toc(timer);
pdus = dpmr.postprocess(pdus);
end

function keys = signatures(pdus)
keys = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    keys{k} = jsonencode({pdus(k).type, pdus(k).src, pdus(k).dst, ...
        pdus(k).flco, ...
        radio.getNestedField(pdus(k), 'extra.color_code', []), ...
        radio.getNestedField(pdus(k), 'extra.superframe_part', '')});
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
