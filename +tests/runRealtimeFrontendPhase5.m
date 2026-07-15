function runRealtimeFrontendPhase5()
%RUNREALTIMEFRONTENDPHASE5 Verify one input fans out to three carrier paths.
fs = 1.2e6;
offsets = [-300e3; 0; 300e3];
durationSec = 0.9;
count = round(durationSec * fs);
n = (0:count-1).';
savedRng = rng;
rng(5091);
iq = 0.003 .* (randn(count, 1) + 1i .* randn(count, 1));
for k = 1:numel(offsets)
    iq = iq + 0.16 .* exp(1i .* 2 .* pi .* offsets(k) .* n ./ fs);
end
rng(savedRng);

tunedCfg = radio.tuned.defaultConfig();
streamCfg = radio.stream.defaultConfig();
streamCfg.ringBufferSec = 2;
streamCfg.activity.initialNoiseFloorDb = -50;
streamCfg.activity.minOnSec = 0.03;
streamCfg.activity.offHangSec = 0.06;
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
scanner = radio.tuned.multiStreamScannerInit(fs, offsets, ...
    'Config', tunedCfg, ...
    'StreamConfig', streamCfg, ...
    'ProtocolNames', {'DMR'}, ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeLockedDecoder, ...
    'Deduplicate', false, ...
    'PrewarmDdc', true);

chunkSamples = round(tunedCfg.chunkDurationSec * fs);
for first = 1:chunkSamples:count
    last = min(count, first + chunkSamples - 1);
    chunk = radio.stream.makeIqChunk(iq(first:last), fs, first - 1, ...
        'SequenceNumber', floor((first - 1) / chunkSamples));
    [scanner, output] = radio.tuned.multiStreamScannerFeed(scanner, chunk); %#ok<ASGLU>
end
[scanner, report] = radio.tuned.multiStreamScannerFinalize(scanner);

assert(scanner.finalized && report.finalized);
assert(report.channelCount == 3);
assert(isequal(report.frequencyOffsetsHz, offsets));
assert(all(strcmp(report.selectedProtocols, 'DMR')));
assert(numel(scanner.closedEpochs) == 3);
assert(~isempty(scanner.pdus));
channelIds = arrayfun(@(item) ...
    item.extra.tuned.channel_id, scanner.pdus);
assert(isequal(unique(channelIds), uint64(1:3).'));
for k = 1:3
    mask = channelIds == uint64(k);
    assert(any(mask));
    tuned = scanner.pdus(find(mask, 1)).extra.tuned;
    assert(tuned.frequency_offset_hz == offsets(k));
end
fprintf('Realtime frontend phase-5 multi-carrier fan-out tests passed.\n');
end
