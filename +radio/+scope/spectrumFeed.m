function [state, output] = spectrumFeed(state, chunk)
%SPECTRUMFEED Accumulate one IqChunk and occasionally publish a PSD row.
radio.stream.validateIqChunk(chunk);
if chunk.sampleRateHz ~= state.sampleRateHz
    error('radio:scope:spectrumFeed:SampleRate', ...
        'Spectrum input sample rate changed.');
end

output = emptyOutput(state);
state.lastDiscontinuity = logical(chunk.discontinuity);
if chunk.discontinuity
    state.fftRemainder = complex(zeros(0, 1));
    state.intervalPowerSum(:) = 0;
    state.intervalSegmentCount = uint64(0);
    state.samplesSinceUpdate = uint64(0);
    output.discontinuity = true;
end

samples = [state.fftRemainder; double(chunk.iq(:))];
segmentCount = floor(numel(samples) / state.nfft);
usedCount = segmentCount * state.nfft;
if segmentCount > 0
    segments = reshape(samples(1:usedCount), state.nfft, segmentCount);
    spectrum = fftshift(fft(segments .* state.window, ...
        state.nfft, 1), 1);
    powerSum = sum(abs(spectrum) .^ 2, 2) ./ state.normalization;
    state.intervalPowerSum = state.intervalPowerSum + double(powerSum);
    state.intervalSegmentCount = state.intervalSegmentCount + ...
        uint64(segmentCount);
    state.segmentCount = state.segmentCount + uint64(segmentCount);
end
state.fftRemainder = samples(usedCount+1:end);
state.samplesSinceUpdate = state.samplesSinceUpdate + ...
    uint64(numel(chunk.iq));
state.inputSampleCount = state.inputSampleCount + uint64(numel(chunk.iq));
state.lastSourceSampleEnd = chunk.sourceSampleEnd;

if state.samplesSinceUpdate < state.updateSamples || ...
        state.intervalSegmentCount == 0
    return;
end

currentPsd = state.intervalPowerSum ./ ...
    double(state.intervalSegmentCount);
if state.hasEstimate
    alpha = state.config.averageAlpha;
    state.averagePsd = (1 - alpha) .* state.averagePsd + ...
        alpha .* currentPsd;
    state.maxHoldPsd = max(state.maxHoldPsd, currentPsd);
else
    state.averagePsd = currentPsd;
    state.maxHoldPsd = currentPsd;
    state.hasEstimate = true;
end
displayPsd = mean(reshape(currentPsd, ...
    state.displayFactor, []), 1).';
timeSec = double(chunk.sourceSampleEnd) / state.sampleRateHz;
[state, rowIndex] = appendWaterfall(state, displayPsd, timeSec);
state.updateCount = state.updateCount + uint64(1);
state.intervalPowerSum(:) = 0;
state.intervalSegmentCount = uint64(0);
state.samplesSinceUpdate = uint64(0);

output.updated = true;
output.updateCount = state.updateCount;
output.timeSec = timeSec;
output.currentPsd = currentPsd;
output.displayPsd = displayPsd;
output.waterfallRowIndex = rowIndex;
output.segmentCount = state.segmentCount;
end

function [state, rowIndex] = appendWaterfall(state, displayPsd, timeSec)
maxRows = uint32(state.config.maxWaterfallRows);
rowIndex = mod(state.waterfallWriteIndex, maxRows) + uint32(1);
state.waterfallCircular(double(rowIndex), :) = single(displayPsd(:).');
state.waterfallTimesSec(double(rowIndex)) = timeSec;
state.waterfallWriteIndex = rowIndex;
state.waterfallRowCount = min(maxRows, state.waterfallRowCount + uint32(1));
end

function output = emptyOutput(state)
output = struct( ...
    'updated', false, ...
    'discontinuity', false, ...
    'updateCount', state.updateCount, ...
    'timeSec', double(state.lastSourceSampleEnd) / state.sampleRateHz, ...
    'currentPsd', zeros(0, 1), ...
    'displayPsd', zeros(0, 1), ...
    'waterfallRowIndex', uint32(0), ...
    'segmentCount', state.segmentCount);
end
