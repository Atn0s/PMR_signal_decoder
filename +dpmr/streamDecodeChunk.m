function [state, output] = streamDecodeChunk(state, chunk)
%STREAMDECODECHUNK Causally decode one contiguous dPMR IQ chunk.
radio.stream.validateIqChunk(chunk);
if state.finalized
    error('dpmr:streamDecodeChunk:Finalized', ...
        'Cannot feed a finalized dPMR stream decoder.');
end
if chunk.sampleRateHz ~= state.inputSampleRateHz
    error('dpmr:streamDecodeChunk:SampleRate', ...
        'dPMR stream sample rate changed inside one decoder context.');
end
if chunk.discontinuity
    error('dpmr:streamDecodeChunk:Discontinuity', ...
        'A discontinuous IQ chunk requires a new dPMR stream context.');
end
if isempty(state.sourceOriginSample)
    state.sourceOriginSample = chunk.sourceSampleStart;
    state.expectedSourceSample = chunk.sourceSampleStart;
end
if chunk.sourceSampleStart ~= state.expectedSourceSample
    error('dpmr:streamDecodeChunk:NonContiguous', ...
        'dPMR stream chunks must be contiguous and ordered.');
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
% Keep the per-PDU source positions one-to-one with the immediate stream
% output.  Stable-colour filtering needs an aggregate view and is therefore
% applied by the offline/final consumer, not independently per IQ chunk.
output = struct( ...
    'pdus', radio.normalizePdus(pdus), ...
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
if strcmp(state.rateMode, 'none')
    output = input;
elseif strcmp(state.rateMode, 'system_object')
    output = state.rateConverter(input);
else
    error('dpmr:streamDecodeChunk:RateMode', ...
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
n = double(state.mixedSamplesProcessed) + (0:numel(incoming)-1).';
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
c = dpmr.constants();
frameSpan = uint64(max(c.frameSymbols, c.voiceFs2TotalSymbols) * ...
    state.cfg.samplesPerSymbol + ceil(abs(state.cfg.phaseSearchMax)) + 2);
bufferEndExclusive = state.demodBufferStart + ...
    uint64(numel(state.demodBuffer));
if bufferEndExclusive <= frameSpan, return; end
searchThrough = bufferEndExclusive - frameSpan;
if searchThrough < state.nextSearchSample, return; end
candidates = dpmr.findSync(state.demodBuffer, ...
    'Threshold', state.cfg.syncThreshold, ...
    'MaxSymbolErrors', state.cfg.syncMaxSymbolErrors, ...
    'MinDistanceSamples', state.cfg.syncMinDistanceSamples, ...
    'DedupWindowSymbols', state.cfg.syncDedupWindowSymbols, ...
    'SyncErrorPhaseSearch', linspace( ...
        state.cfg.syncErrorPhaseMin, state.cfg.syncErrorPhaseMax, ...
        state.cfg.syncErrorPhaseSteps), ...
    'SyncTypes', {'FS1', 'FS2'});
for k = 1:numel(candidates)
    absoluteStart = state.demodBufferStart + ...
        uint64(round(candidates(k).fs_start));
    if absoluteStart < state.nextSearchSample || ...
            absoluteStart > searchThrough
        continue;
    end
    sampleOffset = double(state.demodBufferStart) - ...
        state.pipelineDelaySamples;
    [state.frameState, items] = dpmr.frameDecoderFeedCandidate( ...
        state.frameState, state.demodBuffer, candidates(k), ...
        'SampleOffset', sampleOffset);
    pdus = appendPdus(pdus, items);
    accepted = appendCandidates(accepted, candidates(k), sampleOffset);
end
state.nextSearchSample = searchThrough + uint64(1);
maxSyncSymbols = max(numel(c.fs1Symbols), numel(c.fs4Symbols));
guard = uint64(state.cfg.syncMinDistanceSamples + ...
    maxSyncSymbols * state.cfg.samplesPerSymbol + ...
    ceil(abs(state.cfg.syncErrorPhaseMax)));
if state.nextSearchSample > guard
    keepStart = state.nextSearchSample - guard;
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

function value = appendCandidates(value, candidate, offset)
candidate.fs_start = candidate.fs_start + offset;
if isempty(value), value = candidate; else, value(end+1) = candidate; end
end

function values = counters(frameState)
values = struct('candidateCount', frameState.candidateCount, ...
    'decodedPduCount', frameState.decodedPduCount, ...
    'crcValidPduCount', frameState.crcValidPduCount);
end

function diagnostics = deltaDiagnostics(state, before, after, candidates)
diagnostics = struct( ...
    'syncCandidates', candidates, ...
    'candidateCount', double(after.candidateCount - before.candidateCount), ...
    'decodedPduCount', ...
        double(after.decodedPduCount - before.decodedPduCount), ...
    'crcValidPduCount', ...
        double(after.crcValidPduCount - before.crcValidPduCount), ...
    'coarseFrequencyOffsetHz', state.coarseFrequencyOffsetHz, ...
    'streamTotals', dpmr.frameDecoderReport(state.frameState));
end

function samples = pduSourceSamples(state, pdus)
samples = zeros(numel(pdus), 1, 'uint64');
for k = 1:numel(pdus)
    targetSample = radio.getNestedField(pdus(k), 'extra.fs_start', []);
    if isempty(targetSample)
        targetSample = radio.getNestedField(pdus(k), 'extra.end_sample', []);
    end
    if isempty(targetSample)
        targetSample = radio.getNestedField(pdus(k), 'extra.start_sample', 0);
    end
    inputOffset = round(max(0, double(targetSample)) * ...
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
