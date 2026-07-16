function [state, output] = streamDecodeChunk(state, chunk)
%STREAMDECODECHUNK Causally decode one contiguous TETRA DMO IQ chunk.
radio.stream.validateIqChunk(chunk);
if state.finalized
    error('tetra:streamDecodeChunk:Finalized', ...
        'Cannot feed a finalized TETRA stream decoder.');
end
if chunk.sampleRateHz ~= state.inputSampleRateHz
    error('tetra:streamDecodeChunk:SampleRate', ...
        'TETRA stream sample rate changed inside one decoder context.');
end
if chunk.discontinuity
    error('tetra:streamDecodeChunk:Discontinuity', ...
        'A discontinuous IQ chunk requires a new TETRA stream context.');
end
if isempty(state.sourceOriginSample)
    state.sourceOriginSample = chunk.sourceSampleStart;
    state.expectedSourceSample = chunk.sourceSampleStart;
end
if chunk.sourceSampleStart ~= state.expectedSourceSample
    error('tetra:streamDecodeChunk:NonContiguous', ...
        'TETRA stream chunks must be contiguous and ordered.');
end

timerToken = tic;
inputIq = double(chunk.iq(:));
[state, resampled] = rateConvert(state, inputIq);
[state, matched, calibratedNow] = frontendFeed(state, resampled);
[state, symbols] = sampleSymbols(state, matched);
[state, bits, bitValidMask] = decideSymbols(state, symbols);
[state, pdus, diagnostics] = processBits( ...
    state, bits, bitValidMask, chunk.sourceSampleEnd);

state.expectedSourceSample = chunk.sourceSampleEnd;
state.inputSamplesReceived = state.inputSamplesReceived + ...
    uint64(numel(inputIq));
state.resampledSamplesProduced = state.resampledSamplesProduced + ...
    uint64(numel(resampled));
state.symbolsProduced = state.symbolsProduced + uint64(numel(symbols));
state.feedCount = state.feedCount + uint64(1);
sourceSamples = pduSourceSamples(state, pdus);
diagnostics = frontendDiagnostics( ...
    state, diagnostics, calibratedNow);
output = struct( ...
    'pdus', radio.normalizePdus(pdus), ...
    'sourceSamples', sourceSamples, ...
    'diagnostics', diagnostics, ...
    'frequencyOffsetHz', state.totalFrequencyOffsetHz, ...
    'timingState', struct( ...
        'pipelineDelaySamples', state.pipelineDelaySamples, ...
        'phaseSamples', state.timingPhaseSamples, ...
        'errorRad', state.timingErrorRad, ...
        'decisionVariant', state.decisionVariant, ...
        'nextSymbolPosition', state.nextSymbolPosition, ...
        'nextSlotStartBit', state.nextSlotStartBit), ...
    'nativeStreaming', true, ...
    'inputSampleCount', numel(inputIq), ...
    'resampledSampleCount', numel(resampled), ...
    'symbolCount', numel(symbols), ...
    'bitCount', numel(bits), ...
    'elapsedSec', toc(timerToken));
end

function [state, output] = rateConvert(state, input)
if strcmp(state.rateMode, 'none')
    output = input;
elseif strcmp(state.rateMode, 'system_object')
    output = state.rateConverter(input);
else
    error('tetra:streamDecodeChunk:RateMode', ...
        'Unsupported streaming rate-converter mode: %s', state.rateMode);
end
end

function [state, matched, calibratedNow] = frontendFeed(state, incoming)
calibratedNow = false;
if ~state.calibrated
    state.calibrationBuffer = [state.calibrationBuffer; incoming(:)];
    if numel(state.calibrationBuffer) < state.calibrationMinSamples
        matched = complex(zeros(0, 1));
        return;
    end
    estimateIq = state.calibrationBuffer(1:state.calibrationMinSamples);
    state = calibrate(state, estimateIq);
    incoming = state.calibrationBuffer;
    state.calibrationBuffer = complex(zeros(0, 1));
    state.calibrated = true;
    calibratedNow = true;
end
n = double(state.mixedSamplesProcessed) + (0:numel(incoming)-1).';
corrected = incoming(:) .* exp(-1i * 2 * pi * ...
    state.totalFrequencyOffsetHz .* n ./ state.targetSampleRateHz);
state.mixedSamplesProcessed = state.mixedSamplesProcessed + ...
    uint64(numel(incoming));
[matched, state.matchedZi] = filter( ...
    state.matchedNumerator, 1, corrected, state.matchedZi);
end

function state = calibrate(state, estimateIq)
cfg = state.cfg;
fs = state.targetSampleRateHz;
[coarseHz, ~] = tetra.coarseFrequencyOffset(estimateIq, fs, cfg);
n = (0:numel(estimateIq)-1).';
coarseCorrected = estimateIq(:) .* exp(-1i * 2 * pi * coarseHz .* n ./ fs);
temporaryMatched = filter(state.matchedNumerator, 1, coarseCorrected);
firstSync = tetra.timingSearch(temporaryMatched, cfg);
estimatedResidualHz = firstSync.diffPhaseOffsetRad * ...
    cfg.symbolRateHz / (2 * pi);
useResidual = abs(estimatedResidualHz) >= cfg.residualCorrectionMinHz && ...
    abs(estimatedResidualHz) <= cfg.residualCorrectionMaxHz;
appliedResidualHz = 0;
if useResidual, appliedResidualHz = estimatedResidualHz; end
totalHz = coarseHz + appliedResidualHz;
finalCorrected = estimateIq(:) .* exp(-1i * 2 * pi * totalHz .* n ./ fs);
finalMatched = filter(state.matchedNumerator, 1, finalCorrected);
sync = tetra.timingSearch(finalMatched, cfg);
[decision, ~, variantReports] = tetra.bestDecisionVariant( ...
    sync, tetra.trainingSequences(), cfg);
state.coarseFrequencyOffsetHz = coarseHz;
state.residualCorrectionHz = appliedResidualHz;
state.totalFrequencyOffsetHz = totalHz;
state.usedResidualCorrection = useResidual;
state.timingPhaseSamples = sync.phaseSamples;
state.timingErrorRad = sync.errorRad;
state.decisionVariant = decision.variant;
state.decisionPhaseOffsetRad = decision.phaseOffsetRad;
state.variantReports = variantReports;
state.amplitudeThreshold = calibrationAmplitudeThreshold(sync.symbols);
state.nextSymbolPosition = sync.phaseSamples;
end

function threshold = calibrationAmplitudeThreshold(symbols)
if numel(symbols) < 2
    threshold = 0;
    return;
end
amplitude = min(abs(symbols(2:end)), abs(symbols(1:end-1)));
% A calibration interval may contain normal DMO guard periods.  A
% median-plus-tail threshold would invalidate most of an otherwise valid
% slot and prevent the 70%% payload-validity gate from attempting FEC.
% Activity/Epoch logic already rejects long silence, so use a low fixed
% fraction of the active-symbol scale here and leave bit-pattern/FEC checks
% to the protocol layer.
threshold = 0.10 * prctile(amplitude, 90);
if ~isfinite(threshold) || threshold <= 0, threshold = 0; end
end

function [state, symbols] = sampleSymbols(state, incoming)
symbols = complex(zeros(0, 1));
if ~state.calibrated || isempty(incoming), return; end
if isempty(state.matchedBuffer)
    state.matchedBufferStart = state.mixedSamplesProcessed - ...
        uint64(numel(incoming));
end
state.matchedBuffer = [state.matchedBuffer; incoming(:)];
state.maxMatchedBufferSamples = max( ...
    state.maxMatchedBufferSamples, uint64(numel(state.matchedBuffer)));
bufferEnd = double(state.matchedBufferStart) + ...
    numel(state.matchedBuffer);
lastPosition = bufferEnd - 1 - eps(bufferEnd);
if ceil(state.nextSymbolPosition) > lastPosition, return; end
count = floor((lastPosition - state.nextSymbolPosition) / ...
    state.cfg.samplesPerSymbol) + 1;
positions = state.nextSymbolPosition + ...
    (0:count-1).' .* state.cfg.samplesPerSymbol;
localPositions = positions - double(state.matchedBufferStart);
symbols = common.interpLinear(state.matchedBuffer, localPositions);
state.nextSymbolPosition = state.nextSymbolPosition + ...
    count * state.cfg.samplesPerSymbol;
keepStart = uint64(max(0, floor(state.nextSymbolPosition)));
if keepStart > state.matchedBufferStart
    drop = min(uint64(numel(state.matchedBuffer)), ...
        keepStart - state.matchedBufferStart);
    state.matchedBuffer = state.matchedBuffer(double(drop)+1:end);
    state.matchedBufferStart = state.matchedBufferStart + drop;
end
end

function [state, bits, bitValidMask] = decideSymbols(state, symbols)
bits = false(0, 1);
bitValidMask = false(0, 1);
if isempty(symbols), return; end
if isempty(state.previousSymbol)
    combined = symbols(:);
else
    combined = [state.previousSymbol; symbols(:)];
end
state.previousSymbol = symbols(end);
if numel(combined) < 2, return; end
amplitude = min(abs(combined(2:end)), abs(combined(1:end-1)));
if state.amplitudeThreshold <= 0
    validTransitions = true(size(amplitude));
else
    validTransitions = amplitude > state.amplitudeThreshold;
end
decision = tetra.pi4dqpskDecision(combined, ...
    'Variant', state.decisionVariant, ...
    'PhaseOffsetRad', state.decisionPhaseOffsetRad, ...
    'ValidTransitionMask', validTransitions);
bits = logical(decision.bits(:));
bitValidMask = logical(decision.bitValidMask(:));
end

function [state, pdus, diagnostics] = processBits( ...
        state, incomingBits, incomingValid, sourceEndSample)
pdus = struct([]);
diagnostics = emptyFrameDiagnostics(state);
if ~isempty(incomingBits)
    if isempty(state.bitBuffer)
        state.bitBufferStart = state.bitsProduced + uint64(1);
    end
    state.bitBuffer = [state.bitBuffer; logical(incomingBits(:))];
    state.bitValidBuffer = [state.bitValidBuffer; logical(incomingValid(:))];
    state.bitsProduced = state.bitsProduced + uint64(numel(incomingBits));
    state.maxBitBufferBits = max( ...
        state.maxBitBufferBits, uint64(numel(state.bitBuffer)));
end
if isempty(state.bitBuffer), return; end
bufferEnd = state.bitBufferStart + uint64(numel(state.bitBuffer)) - 1;
slotBits = uint64(state.cfg.slotBits);
if bufferEnd + 1 < slotBits, return; end
completeThrough = bufferEnd - slotBits + uint64(1);
if completeThrough < state.nextSlotStartBit, return; end

context = struct( ...
    'activeStartSec', double(state.sourceOriginSample) / ...
        state.inputSampleRateHz, ...
    'activeEndSec', double(sourceEndSample) / state.inputSampleRateHz, ...
    'coarseFrequencyOffsetHz', state.coarseFrequencyOffsetHz, ...
    'residualCorrectionHz', state.residualCorrectionHz, ...
    'usedResidualCorrection', state.usedResidualCorrection, ...
    'timingPhaseSamples', state.timingPhaseSamples, ...
    'timingErrorRad', state.timingErrorRad, ...
    'decisionVariant', state.decisionVariant, ...
    'decisionPhaseOffsetRad', state.decisionPhaseOffsetRad, ...
    'symbolCount', double(state.symbolsProduced), ...
    'bitCount', double(state.bitsProduced), ...
    'validBitCount', nnz(state.bitValidBuffer), ...
    'validBitRatio', nnz(state.bitValidBuffer) / ...
        max(1, numel(state.bitValidBuffer)));
[state.frameState, pdus, diagnostics] = ...
    tetra.frameDecoderFeedBits( ...
        state.frameState, state.bitBuffer, state.bitValidBuffer, ...
        'BitOffset', double(state.bitBufferStart - uint64(1)), ...
        'MinimumSlotStartBit', double(state.nextSlotStartBit), ...
        'DecodeContext', context);
state.nextSlotStartBit = completeThrough + uint64(1);
if state.nextSlotStartBit > state.bitBufferStart
    drop = min(uint64(numel(state.bitBuffer)), ...
        state.nextSlotStartBit - state.bitBufferStart);
    state.bitBuffer = state.bitBuffer(double(drop)+1:end);
    state.bitValidBuffer = state.bitValidBuffer(double(drop)+1:end);
    state.bitBufferStart = state.bitBufferStart + drop;
end
end

function diagnostics = emptyFrameDiagnostics(state)
diagnostics = struct( ...
    'training', struct('goodCount', 0, 'candidateCount', 0, ...
        'hitCount', 0, 'hits', struct([]), 'items', struct([]), ...
        'score', 0), ...
    'slots', struct(), ...
    'streamTotals', tetra.frameDecoderReport(state.frameState));
end

function diagnostics = frontendDiagnostics(state, diagnostics, calibratedNow)
diagnostics.coarseFrequencyOffsetHz = state.coarseFrequencyOffsetHz;
diagnostics.residualCorrectionHz = state.residualCorrectionHz;
diagnostics.usedResidualCorrection = state.usedResidualCorrection;
diagnostics.timingPhaseSamples = state.timingPhaseSamples;
diagnostics.timingErrorRad = state.timingErrorRad;
diagnostics.decisionVariant = state.decisionVariant;
diagnostics.decisionPhaseOffsetRad = state.decisionPhaseOffsetRad;
diagnostics.calibrated = state.calibrated;
diagnostics.calibratedThisFeed = calibratedNow;
diagnostics.bitBufferBits = numel(state.bitBuffer);
diagnostics.maxBitBufferBits = double(state.maxBitBufferBits);
diagnostics.maxMatchedBufferSamples = ...
    double(state.maxMatchedBufferSamples);
end

function samples = pduSourceSamples(state, pdus)
samples = zeros(numel(pdus), 1, 'uint64');
for k = 1:numel(pdus)
    bitIndex = radio.getNestedField( ...
        pdus(k), 'extra.slot_start_bit', []);
    if isempty(bitIndex)
        bitIndex = radio.getNestedField(pdus(k), 'extra.start_bit', 1);
    end
    targetOffset = (max(1, double(bitIndex)) - 1) * ...
        state.targetSampleRateHz / (2 * state.cfg.symbolRateHz) - ...
        state.pipelineDelaySamples;
    inputOffset = round(max(0, targetOffset) * ...
        state.inputSampleRateHz / state.targetSampleRateHz);
    samples(k) = state.sourceOriginSample + uint64(max(0, inputOffset));
end
end
