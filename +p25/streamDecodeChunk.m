function [state, output] = streamDecodeChunk(state, chunk)
%STREAMDECODECHUNK Causally decode one contiguous P25 IQ chunk.
radio.stream.validateIqChunk(chunk);
if state.finalized
    error('p25:streamDecodeChunk:Finalized', ...
        'Cannot feed a finalized P25 stream decoder.');
end
if chunk.sampleRateHz ~= state.inputSampleRateHz
    error('p25:streamDecodeChunk:SampleRate', ...
        'P25 stream sample rate changed inside one decoder context.');
end
if chunk.discontinuity
    error('p25:streamDecodeChunk:Discontinuity', ...
        'A discontinuous IQ chunk requires a new P25 stream context.');
end
if isempty(state.sourceOriginSample)
    state.sourceOriginSample = chunk.sourceSampleStart;
    state.expectedSourceSample = chunk.sourceSampleStart;
end
if chunk.sourceSampleStart ~= state.expectedSourceSample
    error('p25:streamDecodeChunk:NonContiguous', ...
        'P25 stream chunks must be contiguous and ordered.');
end

before = counters(state.frameState);
timerToken = tic;
inputIq = double(chunk.iq(:));
[state, resampled] = rateConvert(state, inputIq);
[state, centered] = correctFrequency(state, resampled);
if isempty(centered)
    filtered = complex(zeros(0, 1));
else
    [filtered, state.frontendZi] = filter( ...
        state.frontendNumerator, 1, centered, state.frontendZi);
end
[state, demodulated] = demodulate(state, filtered);
[state, pdus, candidates] = processAvailableFrames(state, demodulated);

state.expectedSourceSample = chunk.sourceSampleEnd;
state.inputSamplesReceived = state.inputSamplesReceived + ...
    uint64(numel(inputIq));
state.resampledSamplesProduced = state.resampledSamplesProduced + ...
    uint64(numel(resampled));
state.feedCount = state.feedCount + uint64(1);
after = counters(state.frameState);
sourceSamples = pduSourceSamples(state, pdus);
diagnostics = deltaDiagnostics(state, before, after, candidates);

output = struct( ...
    'pdus', p25.postprocess(pdus), ...
    'sourceSamples', sourceSamples, ...
    'diagnostics', diagnostics, ...
    'frequencyOffsetHz', state.coarseFrequencyOffsetHz + ...
        state.dcEstimateLevels * state.cfg.nominalDeviationHz / 3, ...
    'timingState', struct( ...
        'pipelineDelaySamples', state.pipelineDelaySamples, ...
        'nextSearchSample', state.nextSearchSample, ...
        'demodBufferSamples', numel(state.demodBuffer)), ...
    'nativeStreaming', true, ...
    'inputSampleCount', numel(inputIq), ...
    'resampledSampleCount', numel(resampled), ...
    'demodulatedSampleCount', numel(demodulated), ...
    'elapsedSec', toc(timerToken));
end

function [state, output] = rateConvert(state, input)
switch state.rateMode
    case 'none'
        output = input;
    case 'system_object'
        output = state.rateConverter(input);
    otherwise
        error('p25:streamDecodeChunk:RateMode', ...
            'Unsupported streaming rate-converter mode: %s', state.rateMode);
end
end

function [state, output] = correctFrequency(state, incoming)
if isnan(state.coarseFrequencyOffsetHz)
    state.coarseBuffer = [state.coarseBuffer; incoming(:)];
    if numel(state.coarseBuffer) < state.coarseEstimateMinSamples
        output = complex(zeros(0, 1));
        return;
    end
    estimateIq = state.coarseBuffer(1:state.coarseEstimateMinSamples);
    [frequencyHz, power] = common.welchPsd( ...
        estimateIq, state.targetSampleRateHz, ...
        state.cfg.frontendPsdNperseg);
    [~, index] = max(power);
    state.coarseFrequencyOffsetHz = frequencyHz(index);
    incoming = state.coarseBuffer;
    state.coarseBuffer = complex(zeros(0, 1));
end
start = double(state.mixedSamplesProcessed);
n = start + (0:numel(incoming)-1).';
output = incoming(:) .* exp(-1i * 2 * pi * ...
    state.coarseFrequencyOffsetHz .* n ./ state.targetSampleRateHz);
state.mixedSamplesProcessed = state.mixedSamplesProcessed + ...
    uint64(numel(incoming));
end

function [state, y] = demodulate(state, filtered)
if isempty(filtered)
    y = zeros(0, 1);
    return;
end
if isempty(state.previousFilteredIq)
    if numel(filtered) < 2
        state.previousFilteredIq = filtered(end);
        y = zeros(0, 1);
        return;
    end
    phaseStep = angle(filtered(2:end) .* conj(filtered(1:end-1)));
else
    previous = [state.previousFilteredIq; filtered(1:end-1)];
    phaseStep = angle(filtered .* conj(previous));
end
state.previousFilteredIq = filtered(end);
levels = phaseStep .* (3.0 / (2.0 * pi * ...
    state.cfg.nominalDeviationHz / state.targetSampleRateHz));
[meanTrack, state.dcZi] = filter( ...
    state.dcAlpha, [1 -(1-state.dcAlpha)], levels, state.dcZi);
if ~isempty(meanTrack), state.dcEstimateLevels = meanTrack(end); end
y = double(levels - meanTrack);
y = y(:);
end

function [state, pdus, accepted] = processAvailableFrames(state, incoming)
pdus = struct([]);
accepted = struct([]);
if ~isempty(incoming)
    if isempty(state.demodBuffer)
        state.demodBufferStart = state.demodSamplesProduced;
    end
    state.demodBuffer = [state.demodBuffer; incoming(:)];
    state.demodSamplesProduced = state.demodSamplesProduced + ...
        uint64(numel(incoming));
    state.maxDemodBufferSamples = max(state.maxDemodBufferSamples, ...
        uint64(numel(state.demodBuffer)));
end
if isempty(state.demodBuffer), return; end

frameSpan = uint64(state.cfg.lduSymbols * state.cfg.samplesPerSymbol);
bufferEndExclusive = state.demodBufferStart + ...
    uint64(numel(state.demodBuffer));
if bufferEndExclusive < frameSpan
    return;
end
searchThrough = bufferEndExclusive - frameSpan;
if searchThrough < state.nextSearchSample
    return;
end
candidates = p25.findFrameSync(state.demodBuffer, ...
    'Sps', state.cfg.samplesPerSymbol, ...
    'Threshold', state.cfg.syncThreshold, ...
    'MinDistanceSymbols', state.cfg.syncMinDistanceSymbols);
for k = 1:numel(candidates)
    absoluteStart = state.demodBufferStart + ...
        uint64(round(candidates(k).fs_start));
    if absoluteStart < state.nextSearchSample || ...
            absoluteStart > searchThrough
        continue;
    end
    record = p25.decodeFrameCandidate( ...
        state.demodBuffer, candidates(k), state.cfg);
    if isempty(record), continue; end
    record.candidate.fs_start = double(absoluteStart) - ...
        state.pipelineDelaySamples;
    accepted = appendCandidates(accepted, record.candidate);
    [state.frameState, framePdus] = ...
        p25.frameDecoderFeedRecord(state.frameState, record);
    pdus = appendPdus(pdus, framePdus);
end
state.nextSearchSample = searchThrough + uint64(1);

syncGuard = uint64(state.cfg.syncMinDistanceSymbols * ...
    state.cfg.samplesPerSymbol + ...
    p25.constants().fsSymbols * state.cfg.samplesPerSymbol);
if state.nextSearchSample > syncGuard
    keepStart = state.nextSearchSample - syncGuard;
else
    keepStart = uint64(0);
end
if keepStart > state.demodBufferStart
    drop = min(uint64(numel(state.demodBuffer)), ...
        keepStart - state.demodBufferStart);
    state.demodBuffer = state.demodBuffer(double(drop)+1:end);
    state.demodBufferStart = state.demodBufferStart + drop;
end
end

function values = counters(frameState)
values = struct('frameCount', frameState.frameCount, ...
    'validFrameCount', frameState.validFrameCount, ...
    'pduCount', frameState.pduCount);
end

function diagnostics = deltaDiagnostics(state, before, after, candidates)
diagnostics = struct( ...
    'syncCandidates', candidates, ...
    'frameCount', double(after.frameCount - before.frameCount), ...
    'validBchFrameCount', ...
        double(after.validFrameCount - before.validFrameCount), ...
    'pduCount', double(after.pduCount - before.pduCount), ...
    'coarseFrequencyOffsetHz', state.coarseFrequencyOffsetHz, ...
    'streamTotals', p25.frameDecoderReport(state.frameState));
end

function samples = pduSourceSamples(state, pdus)
samples = zeros(numel(pdus), 1, 'uint64');
for k = 1:numel(pdus)
    targetSample = radio.getNestedField(pdus(k), 'extra.fs_start', 0);
    targetOffset = max(0, double(targetSample));
    inputOffset = round(targetOffset * ...
        state.inputSampleRateHz / state.targetSampleRateHz);
    samples(k) = state.sourceOriginSample + uint64(max(0, inputOffset));
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

function value = appendCandidates(value, item)
if isempty(value), value = item; else, value(end+1) = item; end
end
