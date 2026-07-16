function [state, output] = streamDecodeChunk(state, chunk)
%STREAMDECODECHUNK Causally decode one contiguous DMR IQ chunk.
radio.stream.validateIqChunk(chunk);
if state.finalized
    error('dmr:streamDecodeChunk:Finalized', ...
        'Cannot feed a finalized DMR stream decoder.');
end
if chunk.sampleRateHz ~= state.inputSampleRateHz
    error('dmr:streamDecodeChunk:SampleRate', ...
        'DMR stream sample rate changed inside one decoder context.');
end
if chunk.discontinuity
    error('dmr:streamDecodeChunk:Discontinuity', ...
        'A discontinuous IQ chunk requires a new DMR stream context.');
end
if isempty(state.sourceOriginSample)
    state.sourceOriginSample = chunk.sourceSampleStart;
    state.expectedSourceSample = chunk.sourceSampleStart;
end
if chunk.sourceSampleStart ~= state.expectedSourceSample
    error('dmr:streamDecodeChunk:NonContiguous', ...
        'DMR stream chunks must be contiguous and ordered.');
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
[state, pdus, candidates] = processAvailableBursts(state, demodulated);

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
    'pdus', dmr.postprocess(pdus), ...
    'sourceSamples', sourceSamples, ...
    'diagnostics', diagnostics, ...
    'frequencyOffsetHz', state.coarseFrequencyOffsetHz + ...
        state.dcEstimateLevels * state.cfg.nominalDeviationHz / 3, ...
    'timingState', struct( ...
        'pipelineDelaySamples', state.pipelineDelaySamples, ...
        'nextSearchCenter', state.nextSearchCenter, ...
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
    error('dmr:streamDecodeChunk:RateMode', ...
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

function [state, pdus, accepted] = processAvailableBursts(state, incoming)
pdus = struct([]);
accepted = table([], [], strings(0, 1), ...
    'VariableNames', {'center', 'polarity', 'syncType'});
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

maxAfter = uint64((state.cfg.voiceBurstCount - 1) * ...
    state.cfg.voiceBurstStrideSamples + ...
    66 * state.cfg.samplesPerSymbol + 2);
bufferEndExclusive = state.demodBufferStart + ...
    uint64(numel(state.demodBuffer));
if bufferEndExclusive <= maxAfter
    return;
end
searchThrough = bufferEndExclusive - maxAfter - uint64(1);
if searchThrough < state.nextSearchCenter, return; end
positions = dmr.findSyncPositions(state.demodBuffer, state.cfg);
acceptedRows = {};
for k = 1:height(positions)
    absoluteCenter = state.demodBufferStart + ...
        uint64(round(positions.center(k)));
    if absoluteCenter < state.nextSearchCenter || ...
            absoluteCenter > searchThrough
        continue;
    end
    centerOffset = double(state.demodBufferStart) - ...
        state.pipelineDelaySamples;
    [state.frameState, items] = dmr.frameDecoderFeedCandidate( ...
        state.frameState, state.demodBuffer, positions.center(k), ...
        positions.polarity(k), char(positions.syncType(k)), ...
        'CenterOffset', centerOffset);
    pdus = appendPdus(pdus, items);
    acceptedRows(end+1, :) = {double(absoluteCenter), ... %#ok<AGROW>
        positions.polarity(k), positions.syncType(k)};
end
if ~isempty(acceptedRows)
    accepted = cell2table(acceptedRows, ...
        'VariableNames', {'center', 'polarity', 'syncType'});
end
state.nextSearchCenter = searchThrough + uint64(1);

preSamples = 66 * state.cfg.samplesPerSymbol + 8;
guard = uint64(state.cfg.syncPeakDistanceSamples + preSamples + ...
    24 * state.cfg.samplesPerSymbol);
if state.nextSearchCenter > guard
    keepStart = state.nextSearchCenter - guard;
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
values = struct('candidateCount', frameState.candidateCount, ...
    'decodedPduCount', frameState.decodedPduCount, ...
    'strongPduCount', frameState.strongPduCount);
end

function diagnostics = deltaDiagnostics(state, before, after, candidates)
diagnostics = struct( ...
    'syncCandidates', candidates, ...
    'candidateCount', double(after.candidateCount - before.candidateCount), ...
    'decodedPduCount', ...
        double(after.decodedPduCount - before.decodedPduCount), ...
    'strongPduCount', ...
        double(after.strongPduCount - before.strongPduCount), ...
    'coarseFrequencyOffsetHz', state.coarseFrequencyOffsetHz, ...
    'streamTotals', dmr.frameDecoderReport(state.frameState));
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
