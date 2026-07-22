function runStreamingPhase10()
%RUNSTREAMINGPHASE10 Test wideband PFB, tracking, and channel hand-off.
testProductionRateGeometry();
testPfbChunkContinuity();
testOversampledBoundaryCoverage();
testTwoCarriersInsideOneCoarseBand();
testCandidateLifecycle();
testInputDiscontinuityResetsState();
testWidebandScannerIntegration();
testWidebandFileDispatch();
fprintf('Streaming phase-10 wideband front-end tests passed.\n');
end

function testProductionRateGeometry()
state = radio.wideband.channelizerInit(61.44e6);
assert(state.numChannels == 1024);
assert(state.hopSamples == 512);
assert(abs(state.subbandSampleRateHz - 120000) < 1e-9);
assert(abs(median(diff(state.binCenterOffsetHz)) - 60000) < 1e-9);
end

function testPfbChunkContinuity()
fs = 16000;
cfg = smallPfbConfig(fs);
n = (0:3199).';
iq = exp(1i .* 2 .* pi .* 3000 .* n ./ fs);

whole = radio.wideband.channelizerInit(fs, 'Config', cfg);
chunk = radio.stream.makeIqChunk(iq, fs, 0);
[whole, wholeBatch] = radio.wideband.channelizerFeed(whole, chunk); %#ok<ASGLU>

split = radio.wideband.channelizerInit(fs, 'Config', cfg);
first = radio.stream.makeIqChunk(iq(1:1700), fs, 0);
[split, batch1] = radio.wideband.channelizerFeed(split, first);
second = radio.stream.makeIqChunk(iq(1701:end), fs, 1700);
[split, batch2] = radio.wideband.channelizerFeed(split, second); %#ok<ASGLU>
splitIq = [batch1.iq, batch2.iq];

assert(isequal(size(splitIq), size(wholeBatch.iq)));
assert(max(abs(double(splitIq(:) - wholeBatch.iq(:)))) < 1e-6);
[~, peak] = max(mean(abs(splitIq).^2, 2));
assert(batch2.binCenterOffsetHz(peak) == 3000);
assert(max(abs(splitIq(peak, :) - 1)) < 1e-4);
end

function testOversampledBoundaryCoverage()
fs = 16000;
cfg = smallPfbConfig(fs);
cfg.channelizer.tapsPerChannel = 8;
state = radio.wideband.channelizerInit(fs, 'Config', cfg);
n = (0:3199).';
iq = exp(1i .* 2 .* pi .* 3500 .* n ./ fs);
[~, batch] = radio.wideband.channelizerFeed(state, ...
    radio.stream.makeIqChunk(iq, fs, 0));
rmsByBin = sqrt(mean(abs(batch.iq).^2, 2));
left = rmsByBin(batch.binCenterOffsetHz == 3000);
right = rmsByBin(batch.binCenterOffsetHz == 4000);
assert(left > 0.7 && right > 0.7);
end

function testTwoCarriersInsideOneCoarseBand()
fs = 1024000;
cfg = radio.wideband.defaultConfig();
cfg.channelizer.numChannels = 16;
cfg.channelizer.tapsPerChannel = 8;
cfg.detector.fineFftLength = 512;
state = radio.wideband.channelizerInit(fs, 'Config', cfg);

savedRng = rng;
rng(12);
sampleCount = round(0.06 * fs);
left = makeFsk(sampleCount, fs, 101000);
right = makeFsk(sampleCount, fs, 113500);
iq = left + 0.8 .* right + 0.02 .* ...
    (randn(sampleCount, 1) + 1i .* randn(sampleCount, 1));
rng(savedRng);
[~, batch] = radio.wideband.channelizerFeed(state, ...
    radio.stream.makeIqChunk(iq, fs, 0));
[detections, report] = radio.wideband.detectCandidates( ...
    batch, 'Config', cfg);
offsets = [detections.frequencyOffsetHz];
assert(report.candidateCount >= 2);
assert(any(abs(offsets - 101000) < 1500));
assert(any(abs(offsets - 113500) < 1500));
end

function testCandidateLifecycle()
cfg = radio.wideband.defaultConfig();
cfg.tracker.minOnSec = 0.02;
cfg.tracker.offHangSec = 0.05;
tracker = radio.wideband.candidateTrackerInit('Config', cfg);
batch = fakeBatch(10, 1000, 0);
detection = fakeDetection(12500, batch);

[tracker, ~] = radio.wideband.candidateTrackerFeed( ...
    tracker, detection, batch);
assert(numel(tracker.tracks) == 1);
assert(strcmp(tracker.tracks.state, 'tentative'));
batch = fakeBatch(10, 1000, 10);
detection.outputSampleStart = batch.outputSampleStart;
detection.outputSampleEnd = batch.outputSampleEnd;
[tracker, update] = radio.wideband.candidateTrackerFeed( ...
    tracker, detection, batch);
assert(strcmp(tracker.tracks.state, 'active'));
assert(any(strcmp({update.events.type}, 'TRACK_ACTIVATED')));

for first = 20:10:40
    batch = fakeBatch(10, 1000, first);
    [tracker, update] = radio.wideband.candidateTrackerFeed( ...
        tracker, detection([]), batch); %#ok<ASGLU>
end
assert(numel(tracker.tracks) == 1);
assert(strcmp(tracker.tracks.state, 'off_pending'));

batch = fakeBatch(10, 1000, 50);
detection.outputSampleStart = batch.outputSampleStart;
detection.outputSampleEnd = batch.outputSampleEnd;
[tracker, update] = radio.wideband.candidateTrackerFeed( ...
    tracker, detection, batch);
assert(strcmp(tracker.tracks.state, 'active'));
assert(any(strcmp({update.events.type}, 'TRACK_REACQUIRED')));

closedTracks = radio.wideband.emptyTrack();
closedTracks = closedTracks([]);
closedEvents = struct([]);
for first = 60:10:110
    batch = fakeBatch(10, 1000, first);
    [tracker, update] = radio.wideband.candidateTrackerFeed( ...
        tracker, detection([]), batch);
    if ~isempty(update.closedTracks)
        closedTracks = update.closedTracks;
        closedEvents = update.events;
    end
end
assert(isempty(tracker.tracks));
assert(numel(closedTracks) == 1);
assert(any(strcmp({closedEvents.type}, 'TRACK_CLOSED')));
end

function testWidebandScannerIntegration()
fs = 128000;
cfg = radio.wideband.defaultConfig();
cfg.chunkDurationSec = 0.01;
cfg.channelizer.numChannels = 16;
cfg.channelizer.tapsPerChannel = 8;
cfg.detector.fineFftLength = 256;
cfg.detector.channelSmoothingHz = 2400;
cfg.detector.candidateMinSpacingHz = 4000;
cfg.detector.duplicateMergeHz = 2000;
cfg.tracker.matchToleranceHz = 2500;
cfg.tracker.minOnSec = 0.02;
cfg.tracker.offHangSec = 0.06;
cfg.extractor.lowpassCutoffHz = 6000;
cfg.extractor.lowpassTaps = 33;
cfg.stream.chunkDurationSec = 0.01;
cfg.stream.ringBufferSec = 1;
cfg.stream.preTriggerSec = 0.02;
cfg.stream.activity.minOnSec = 0.02;
cfg.stream.activity.offHangSec = 0.06;

savedRng = rng;
rng(5);
% Leave at least one production DMR minimum-advance interval after the
% synthetic probe reaches its 300 ms confirmation window.
signalSamples = round(0.80 * fs);
signal = makeFsk(signalSamples, fs, 21000);
totalSamples = round(0.96 * fs);
iq = 0.02 .* (randn(totalSamples, 1) + 1i .* randn(totalSamples, 1));
signalStart = round(0.04 * fs) + 1;
iq(signalStart:signalStart+signalSamples-1) = ...
    iq(signalStart:signalStart+signalSamples-1) + signal;
rng(savedRng);

context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
[pdus, report] = radio.wideband.scanIq(iq, fs, ...
    'CenterFrequencyHz', 430e6, ...
    'Config', cfg, ...
    'ProtocolNames', {'DMR'}, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', @tests.fakeLockedDecoder);

assert(report.remainingTrackCount == 0);
assert(report.remainingChannelCount == 0);
assert(~isempty(report.closedEpochs));
assert(any(strcmp({report.closedEpochs.protocol}, 'DMR')));
assert(~isempty(pdus));
assert(isfield(pdus(1).extra, 'wideband'));
frequencies = arrayfun(@(item) ...
    item.extra.wideband.rf_center_frequency_hz, pdus);
assert(any(abs(frequencies - (430e6 + 21000)) < 3000));
assert(all(arrayfun(@(item) ...
    item.extra.wideband.source_sample >= uint64(0), pdus)));
end

function testInputDiscontinuityResetsState()
fs = 16000;
cfg = smallPfbConfig(fs);
state = radio.wideband.channelizerInit(fs, 'Config', cfg);
n = (0:799).';
iq = exp(1i .* 2 .* pi .* 3000 .* n ./ fs);
[state, firstBatch] = radio.wideband.channelizerFeed(state, ...
    radio.stream.makeIqChunk(iq, fs, 0));
assert(firstBatch.outputSampleStart == uint64(0));

secondChunk = radio.stream.makeIqChunk(iq, fs, 900, ...
    'Discontinuity', true, 'DroppedSourceSamples', uint64(100));
[~, resetBatch] = radio.wideband.channelizerFeed(state, secondChunk);
assert(resetBatch.discontinuity);
assert(resetBatch.continuityGeneration == uint64(1));
assert(resetBatch.outputSampleStart == uint64(0));

trackCfg = radio.wideband.defaultConfig();
trackCfg.tracker.minOnSec = 0.01;
tracker = radio.wideband.candidateTrackerInit('Config', trackCfg);
batch = fakeBatch(10, 1000, 0);
detection = fakeDetection(12500, batch);
[tracker, ~] = radio.wideband.candidateTrackerFeed( ...
    tracker, detection, batch);
assert(~isempty(tracker.tracks));
reset = fakeBatch(10, 1000, 0);
reset.discontinuity = true;
reset.continuityGeneration = uint64(1);
[tracker, update] = radio.wideband.candidateTrackerFeed( ...
    tracker, detection([]), reset);
assert(isempty(tracker.tracks));
assert(numel(update.closedTracks) == 1);
assert(strcmp(update.events(1).reason, 'input_discontinuity'));
end

function testWidebandFileDispatch()
fs = 128000;
cfg = radio.wideband.defaultConfig();
cfg.chunkDurationSec = 0.01;
cfg.channelizer.numChannels = 16;
cfg.channelizer.tapsPerChannel = 4;
cfg.tracker.minOnSec = 0.02;
cfg.tracker.offHangSec = 0.04;
cfg.extractor.lowpassCutoffHz = 6000;
cfg.extractor.lowpassTaps = 33;
cfg.stream.chunkDurationSec = 0.01;
cfg.stream.activity.minOnSec = 0.02;
cfg.stream.activity.offHangSec = 0.04;

path = [tempname, '_128000.rawiq'];
cleanup = onCleanup(@() deleteIfPresent(path)); %#ok<NASGU>
fid = fopen(path, 'wb');
assert(fid >= 0);
fwrite(fid, zeros(round(0.05 * fs) * 2, 1, 'int16'), 'int16');
fclose(fid);
[pdus, report] = radio.scanFile(path, ...
    'ExecutionMode', 'wideband', ...
    'SampleRate', fs, ...
    'WidebandConfig', cfg, ...
    'CenterFrequencyHz', 430e6, ...
    'ShowProgress', false);
assert(isempty(pdus));
assert(strcmp(report.executionMode, 'wideband-streaming'));
assert(strcmp(report.outcome, 'no_signal'));
assert(report.candidateTrackCount == 0);
assert(report.channelizer.numChannels == 16);
end

function cfg = smallPfbConfig(fs)
cfg = radio.wideband.defaultConfig();
cfg.channelizer.numChannels = 16;
cfg.channelizer.tapsPerChannel = 4;
cfg.extractor.lowpassCutoffHz = fs / 32;
cfg.extractor.lowpassTaps = 33;
end

function iq = makeFsk(sampleCount, sampleRateHz, centerHz)
samplesPerSymbol = round(sampleRateHz / 4800);
levels = [-1800; -600; 600; 1800];
symbols = levels(randi(4, ceil(sampleCount / samplesPerSymbol), 1));
instantaneous = centerHz + repelem(symbols, samplesPerSymbol);
instantaneous = instantaneous(1:sampleCount);
iq = exp(1i .* cumsum(2 .* pi .* instantaneous ./ sampleRateHz));
end

function batch = fakeBatch(sampleCount, sampleRateHz, first)
batch = struct( ...
    'iq', complex(zeros(1, sampleCount)), ...
    'sampleRateHz', double(sampleRateHz), ...
    'outputSampleStart', uint64(first), ...
    'outputSampleEnd', uint64(first + sampleCount), ...
    'frameSourceSamples', first:first+sampleCount-1, ...
    'binCenterOffsetHz', 0, ...
    'widebandCenterFrequencyHz', 0, ...
    'widebandSampleRateHz', sampleRateHz, ...
    'groupDelaySamples', 0, ...
    'continuityGeneration', uint64(0), ...
    'discontinuity', false, ...
    'droppedSourceSamples', uint64(0));
end

function item = fakeDetection(offsetHz, batch)
item = struct( ...
    'frequencyOffsetHz', double(offsetHz), ...
    'centerFrequencyHz', double(offsetHz), ...
    'coarseBin', uint32(1), ...
    'coarseCenterOffsetHz', 0.0, ...
    'residualOffsetHz', double(offsetHz), ...
    'powerDb', 0.0, ...
    'noiseFloorDb', -40.0, ...
    'snrDb', 40.0, ...
    'outputSampleStart', batch.outputSampleStart, ...
    'outputSampleEnd', batch.outputSampleEnd, ...
    'widebandStartSample', uint64(batch.frameSourceSamples(1)), ...
    'widebandEndSample', uint64(batch.frameSourceSamples(end) + 1), ...
    'continuityGeneration', uint64(0));
end

function deleteIfPresent(path)
if exist(path, 'file') == 2
    delete(path);
end
end
