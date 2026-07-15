function runRealtimeFrontendPhase2()
%RUNREALTIMEFRONTENDPHASE2 Test incremental spectrum and carrier selection.
testSpectrumAndWaterfall();
testDiscontinuityRemainder();
fprintf('Realtime frontend phase-2 spectrum tests passed.\n');
end

function testSpectrumAndWaterfall()
fs = 1024000;
centerHz = 430e6;
toneOffsetHz = 125000;
cfg = radio.scope.defaultConfig();
cfg.nfft = 1024;
cfg.updateIntervalSec = 0.002;
cfg.averageAlpha = 1;
cfg.maxWaterfallRows = 3;
cfg.maxDisplayBins = 256;
state = radio.scope.spectrumInit(fs, centerHz, 'Config', cfg);

n = (0:8191).';
savedRng = rng;
rng(29);
iq = exp(1i .* 2 .* pi .* toneOffsetHz .* n ./ fs) + ...
    0.01 .* (randn(size(n)) + 1i .* randn(size(n)));
rng(savedRng);
updated = 0;
for first = 1:512:numel(iq)
    last = min(numel(iq), first + 511);
    chunk = radio.stream.makeIqChunk( ...
        iq(first:last), fs, uint64(first - 1), ...
        'SequenceNumber', uint64(floor((first - 1) / 512)), ...
        'CenterFrequencyHz', centerHz);
    [state, output] = radio.scope.spectrumFeed(state, chunk);
    updated = updated + double(output.updated);
end
assert(updated == 4);
snapshot = radio.scope.spectrumSnapshot(state);
assert(snapshot.hasEstimate && snapshot.updateCount == uint64(4));
assert(size(snapshot.waterfallPsd, 1) == 3);
assert(size(snapshot.waterfallPsd, 2) == 256);
assert(all(diff(snapshot.waterfallTimeSec) > 0));
[~, peakIndex] = max(snapshot.averagePsd);
assert(abs(snapshot.offsetHz(peakIndex) - toneOffsetHz) <= fs / cfg.nfft);

clickedHz = centerHz + toneOffsetHz - 4000;
selection = radio.scope.refineCarrier( ...
    snapshot, clickedHz, 'BandwidthHz', 12500);
assert(abs(selection.offsetHz - toneOffsetHz) < 2000);
assert(selection.refinedFrequencyHz == ...
    centerHz + selection.offsetHz);

oldMax = state.maxHoldPsd;
state = radio.scope.resetMaxHold(state);
assert(isequal(state.maxHoldPsd, state.averagePsd));
assert(any(oldMax >= state.maxHoldPsd));
end

function testDiscontinuityRemainder()
cfg = radio.scope.defaultConfig();
cfg.nfft = 1024;
cfg.updateIntervalSec = 0.001;
cfg.maxDisplayBins = 128;
state = radio.scope.spectrumInit(1024000, 0, 'Config', cfg);
[state, output] = radio.scope.spectrumFeed(state, ...
    radio.stream.makeIqChunk(complex(ones(600, 1)), 1024000, 0));
assert(~output.updated && numel(state.fftRemainder) == 600);
discontinuous = radio.stream.makeIqChunk( ...
    complex(ones(600, 1)), 1024000, 2000, ...
    'SequenceNumber', 1, 'Discontinuity', true, ...
    'DroppedSourceSamples', 1400);
[state, output] = radio.scope.spectrumFeed(state, discontinuous);
assert(output.discontinuity && ~output.updated);
assert(numel(state.fftRemainder) == 600);
end
