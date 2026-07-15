function report = runNxdn96Streaming()
%RUNNXDN96STREAMING Validate causal NXDN state across arbitrary IQ chunks.
path = fullfile('signal_data', 'nxdn96_1_78125.rawiq');
if exist(path, 'file') ~= 2
    fprintf('[SKIP] NXDN96 streaming sample is not present.\n');
    report = struct('skipped', true);
    return;
end
fs = 78125;
iq = common.readRawIq(path);
cfg = nxdn.config();
timer = tic;
[offlinePdus, offlineReport] = nxdn.decodeIq(iq, fs, cfg);
offlineElapsed = toc(timer);

scheduleA = round(fs .* [0.037 0.083 0.211 0.059 0.127]);
scheduleB = round(fs .* [0.200 0.200 0.200]);
[streamA, stateA, elapsedA] = decodeChunks(iq, fs, cfg, scheduleA);
[streamB, stateB, elapsedB] = decodeChunks(iq, fs, cfg, scheduleB);

keysA = signatures(streamA);
keysB = signatures(streamB);
offlineKeys = signatures(offlinePdus);
assert(isequal(sort(keysA), sort(keysB)), ...
    'NXDN streaming PDU output changed with IQ chunk boundaries.');
assert(isequal(contentSignatures(streamA), contentSignatures(offlinePdus)), ...
    'NXDN streaming and offline decoders disagree on semantic PDU content.');
positionError = abs(pduPositions(streamA) - pduPositions(offlinePdus));
assert(max(positionError) <= cfg.samplesPerSymbol, ...
    'NXDN streaming frame positions differ from the offline reference.');
assert(stateA.maxDemodBufferSamples < uint64(round(0.40 * cfg.targetSampleRateHz)));
assert(stateB.maxDemodBufferSamples < uint64(round(0.40 * cfg.targetSampleRateHz)));
assert(double(stateA.frameState.validFrameCount) >= ...
    0.95 * offlineReport.validFrameCount);
assert(double(stateA.frameState.validChannelBlockCount) >= ...
    0.95 * offlineReport.validChannelBlockCount);

% The tuned 2.5 MHz path produces 125 kS/s baseband.  Exercise its pure
% MATLAB 48/125 polyphase converter with two unrelated chunk schedules.
tunedSourceCount = min(numel(iq), round(2.0 * fs));
tunedFs = 125000;
tunedIq = common.resampleTo(iq(1:tunedSourceCount), fs, tunedFs);
[tunedA, tunedStateA] = decodeChunks( ...
    tunedIq, tunedFs, cfg, round(tunedFs .* [0.041 0.097 0.203]));
[tunedB, tunedStateB] = decodeChunks( ...
    tunedIq, tunedFs, cfg, round(tunedFs .* [0.125 0.250]));
assert(~isempty(tunedA));
assert(isequal(signatures(tunedA), signatures(tunedB)), ...
    'The 125 kS/s NXDN polyphase path depends on chunk boundaries.');
assert(strcmp(tunedStateA.rateMode, 'polyphase_fir'));
assert(strcmp(tunedStateB.rateMode, 'polyphase_fir'));

report = struct( ...
    'skipped', false, ...
    'offlinePduCount', numel(offlinePdus), ...
    'streamPduCount', numel(streamA), ...
    'offlineValidFrames', offlineReport.validFrameCount, ...
    'streamValidFrames', double(stateA.frameState.validFrameCount), ...
    'offlineValidBlocks', offlineReport.validChannelBlockCount, ...
    'streamValidBlocks', double(stateA.frameState.validChannelBlockCount), ...
    'offlineElapsedSec', offlineElapsed, ...
    'streamElapsedSec', elapsedA, ...
    'secondScheduleElapsedSec', elapsedB, ...
    'streamRealtimeFactor', elapsedA / (numel(iq) / fs), ...
    'maxDemodBufferSamples', double(stateA.maxDemodBufferSamples));
fprintf(['NXDN96 streaming: offline=%d PDU, stream=%d PDU, ', ...
    'frames=%d/%d, blocks=%d/%d, RTF=%.3f.\n'], ...
    report.offlinePduCount, report.streamPduCount, ...
    report.streamValidFrames, report.offlineValidFrames, ...
    report.streamValidBlocks, report.offlineValidBlocks, ...
    report.streamRealtimeFactor);
end

function [pdus, state, elapsed] = decodeChunks(iq, fs, cfg, schedule)
state = nxdn.streamInit(fs, cfg, 'SourceSampleStart', uint64(0));
pdus = struct([]);
position = 1;
sequence = uint64(0);
scheduleIndex = 1;
timer = tic;
while position <= numel(iq)
    count = min(schedule(scheduleIndex), numel(iq) - position + 1);
    chunk = radio.stream.makeIqChunk( ...
        iq(position:position+count-1), fs, uint64(position-1), ...
        'SequenceNumber', sequence);
    [state, output] = nxdn.streamDecodeChunk(state, chunk);
    pdus = appendPdus(pdus, output.pdus);
    position = position + count;
    sequence = sequence + uint64(1);
    scheduleIndex = mod(scheduleIndex, numel(schedule)) + 1;
end
[state, output] = nxdn.streamFlush(state);
pdus = appendPdus(pdus, output.pdus);
elapsed = toc(timer);
pdus = nxdn.postprocess(pdus);
end

function keys = signatures(pdus)
keys = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    keys{k} = jsonencode(radio.dedupKey(pdus(k)));
end
end

function keys = contentSignatures(pdus)
keys = cell(numel(pdus), 1);
for k = 1:numel(pdus)
    if strcmp(pdus(k).type, 'NXDN_CALL')
        key = {'NXDN', 'CALL', ...
            radio.getNestedField(pdus(k), 'extra.ran', []), ...
            pdus(k).src, pdus(k).dst, pdus(k).flco, ...
            radio.getNestedField(pdus(k), 'extra.alias', '')};
    else
        key = radio.dedupKey(pdus(k));
    end
    keys{k} = jsonencode(key);
end
end

function positions = pduPositions(pdus)
positions = zeros(numel(pdus), 1);
for k = 1:numel(pdus)
    value = radio.getNestedField(pdus(k), 'extra.fs_start', []);
    if isempty(value)
        value = radio.getNestedField(pdus(k), 'extra.start_sample', 0);
    end
    positions(k) = double(value);
end
end

function out = appendPdus(arr, items)
if isempty(items)
    out = arr;
elseif isempty(arr)
    out = items;
else
    out = arr;
    out(end+1:end+numel(items)) = items;
end
end
