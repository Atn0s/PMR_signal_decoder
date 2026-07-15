function runRealtimeFrontendPhase3()
%RUNREALTIMEFRONTENDPHASE3 Test streaming DDC-to-coordinator integration.
fs = 240000;
offsetHz = 40000;
centerHz = 10e6;
cfg = radio.tuned.defaultConfig();
streamCfg = radio.stream.defaultConfig();
streamCfg.ringBufferSec = 2;
streamCfg.activity.initialNoiseFloorDb = -40;
streamCfg.activity.minOnSec = 0.05;
streamCfg.activity.offHangSec = 0.06;
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
scanner = radio.tuned.streamScannerInit(fs, offsetHz, ...
    'InputCenterFrequencyHz', centerHz, ...
    'Config', cfg, ...
    'StreamConfig', streamCfg, ...
    'ProtocolNames', {'dmr'}, ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeLockedDecoder, ...
    'PrewarmDdc', true);
assert(scanner.warmupElapsedSec >= 0);

chunkSamples = round(0.010 * fs);
lockedSeen = false;
newPduCount = 0;
for k = 0:39
    n = (0:chunkSamples-1).' + k * chunkSamples;
    iq = 0.3 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
    chunk = radio.stream.makeIqChunk(iq, fs, uint64(k * chunkSamples), ...
        'SequenceNumber', uint64(k), ...
        'CenterFrequencyHz', centerHz);
    [scanner, output] = radio.tuned.streamScannerFeed(scanner, chunk);
    lockedSeen = lockedSeen || strcmp(output.state, 'LOCKED');
    newPduCount = newPduCount + numel(output.newPdus);
    if ~isempty(output.basebandChunk)
        assert(output.basebandChunk.sampleRateHz == 120000);
        assert(output.basebandChunk.centerFrequencyHz == centerHz + offsetHz);
    end
end
assert(lockedSeen);
assert(strcmp(scanner.lastSelectedProtocol, 'DMR'));
assert(newPduCount > 0 && ~isempty(scanner.pdus));
assert(isfield(scanner.pdus(1).extra, 'tuned'));
assert(scanner.pdus(1).extra.tuned.decimation_factor == 2);
assert(~scanner.pdus(1).extra.tuned.mapping_includes_filter_delay);

for k = 40:49
    chunk = radio.stream.makeIqChunk( ...
        complex(zeros(chunkSamples, 1)), fs, uint64(k * chunkSamples), ...
        'SequenceNumber', uint64(k), ...
        'CenterFrequencyHz', centerHz);
    [scanner, ~] = radio.tuned.streamScannerFeed(scanner, chunk);
end
[scanner, report] = radio.tuned.streamScannerFinalize( ...
    scanner, 'SilenceDurationSec', 0.10);
assert(scanner.finalized && report.finalized);
assert(strcmp(report.selectedProtocol, 'DMR'));
assert(report.epochCount >= 1);
assert(report.pduCount == numel(scanner.pdus));
assert(report.inputSampleCount == uint64(50 * chunkSamples));
assertThrows(@() radio.tuned.streamScannerFeed(scanner, ...
    radio.stream.makeIqChunk(complex(zeros(chunkSamples, 1)), ...
    fs, uint64(50 * chunkSamples), 'CenterFrequencyHz', centerHz)), ...
    'radio:tuned:streamScannerFeed:Finalized');

% A DMR-like 40 ms on / 20 ms off pattern never satisfies a 50 ms
% contiguous-on debounce when inspected as raw 10 ms DDC blocks. The tuned
% stream must therefore preserve the established 100 ms activity-window
% semantics by batching DDC output before the coordinator.
pulsed = radio.tuned.streamScannerInit(fs, offsetHz, ...
    'InputCenterFrequencyHz', centerHz, ...
    'Config', cfg, ...
    'StreamConfig', streamCfg, ...
    'ProtocolNames', {'dmr'}, ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeLockedDecoder, ...
    'PrewarmDdc', true);
assert(pulsed.coordinatorChunkSamples == round( ...
    streamCfg.chunkDurationSec * pulsed.basebandSampleRateHz));
pulsedLocked = false;
for k = 0:59
    n = (0:chunkSamples-1).' + k * chunkSamples;
    if mod(k, 6) < 4
        iq = 0.3 .* exp(1i .* 2 .* pi .* offsetHz .* n ./ fs);
    else
        iq = complex(zeros(chunkSamples, 1));
    end
    chunk = radio.stream.makeIqChunk(iq, fs, uint64(k * chunkSamples), ...
        'SequenceNumber', uint64(k), ...
        'CenterFrequencyHz', centerHz);
    [pulsed, pulsedOutput] = ...
        radio.tuned.streamScannerFeed(pulsed, chunk);
    if mod(k + 1, 10) == 0
        assert(pulsedOutput.coordinatorChunkCount == 1);
    else
        assert(pulsedOutput.coordinatorChunkCount == 0);
    end
    pulsedLocked = pulsedLocked || strcmp(pulsedOutput.state, 'LOCKED');
end
assert(pulsedLocked && strcmp(pulsed.lastSelectedProtocol, 'DMR'));
[pulsed, ~] = radio.tuned.streamScannerFinalize( ...
    pulsed, 'SilenceDurationSec', 0.10);
assert(pulsed.finalized);
fprintf('Realtime frontend phase-3 tuned-stream tests passed.\n');
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
