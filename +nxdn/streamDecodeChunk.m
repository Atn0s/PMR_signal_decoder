function [state, output] = streamDecodeChunk(state, chunk)
%STREAMDECODECHUNK Causally decode one contiguous NXDN96 IQ chunk.
radio.stream.validateIqChunk(chunk);
if state.finalized
    error('nxdn:streamDecodeChunk:Finalized', ...
        'Cannot feed a finalized NXDN stream decoder.');
end
if chunk.sampleRateHz ~= state.inputSampleRateHz
    error('nxdn:streamDecodeChunk:SampleRate', ...
        'NXDN stream sample rate changed inside one decoder context.');
end
if chunk.discontinuity
    error('nxdn:streamDecodeChunk:Discontinuity', ...
        'A discontinuous IQ chunk requires a new NXDN stream context.');
end
if isempty(state.sourceOriginSample)
    state.sourceOriginSample = chunk.sourceSampleStart;
    state.expectedSourceSample = chunk.sourceSampleStart;
end
if chunk.sourceSampleStart ~= state.expectedSourceSample
    error('nxdn:streamDecodeChunk:NonContiguous', ...
        'NXDN stream chunks must be contiguous and ordered.');
end

before = counters(state.frameState);
timerToken = tic;
inputIq = double(chunk.iq(:));
[state, resampled] = rateConvert(state, inputIq);
if isempty(resampled)
    filtered = complex(zeros(0, 1));
else
    [filtered, state.frontendZi] = filter( ...
        state.frontendNumerator, 1, resampled, state.frontendZi);
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
    'pdus', nxdn.postprocess(pdus), ...
    'sourceSamples', sourceSamples, ...
    'diagnostics', diagnostics, ...
    'frequencyOffsetHz', state.dcEstimateLevels * ...
        state.cfg.nominalDeviationHz / 3, ...
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
    case 'polyphase_fir'
        [state, output] = polyphaseRateConvert(state, input);
    otherwise
        error('nxdn:streamDecodeChunk:RateMode', ...
            'Unsupported streaming rate-converter mode: %s', state.rateMode);
end
end

function [state, output] = polyphaseRateConvert(state, input)
if ~isempty(input)
    if isempty(state.rateInputBuffer)
        state.rateInputBufferStart = state.rateInputSamplesReceived;
    end
    state.rateInputBuffer = [state.rateInputBuffer; input(:)];
    state.rateInputSamplesReceived = ...
        state.rateInputSamplesReceived + numel(input);
end
lastInput = state.rateInputSamplesReceived - 1;
if lastInput < 0
    output = complex(zeros(0, 1));
    return;
end
up = state.rateUp;
down = state.rateDown;
lastOutput = floor(((lastInput + 1) * up - 1) / down);
if lastOutput < state.rateNextOutputIndex
    output = complex(zeros(0, 1));
    return;
end
q = (state.rateNextOutputIndex:lastOutput).';
k = q .* down;
phases = mod(k, up);
centers = floor(k ./ up);
output = complex(zeros(numel(q), 1));
for phase = 0:up-1
    rows = find(phases == phase);
    if isempty(rows), continue; end
    coefficients = state.rateBranches{phase + 1};
    tapOffsets = 0:numel(coefficients)-1;
    absoluteIndexes = centers(rows) - tapOffsets;
    values = complex(zeros(size(absoluteIndexes)));
    localIndexes = absoluteIndexes - state.rateInputBufferStart + 1;
    valid = localIndexes >= 1 & ...
        localIndexes <= numel(state.rateInputBuffer);
    values(valid) = state.rateInputBuffer(localIndexes(valid));
    output(rows) = values * coefficients;
end
state.rateNextOutputIndex = lastOutput + 1;

nextCenter = floor(state.rateNextOutputIndex * down / up);
keepStart = max(0, nextCenter - state.rateMaxBranchLength + 1);
drop = min(numel(state.rateInputBuffer), ...
    max(0, floor(keepStart - state.rateInputBufferStart)));
if drop > 0
    state.rateInputBuffer = state.rateInputBuffer(drop+1:end);
    state.rateInputBufferStart = state.rateInputBufferStart + drop;
end
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
if ~isempty(meanTrack)
    state.dcEstimateLevels = meanTrack(end);
end
y = levels - meanTrack;
y = double(y(:));
end

function [state, pdus, accepted] = processAvailableFrames(state, incoming)
pdus = struct([]);
accepted = repmat(emptyCandidate(), 0, 1);
if ~isempty(incoming)
    if isempty(state.demodBuffer)
        state.demodBufferStart = state.demodSamplesProduced + uint64(1);
    end
    state.demodBuffer = [state.demodBuffer; incoming(:)];
    state.demodSamplesProduced = state.demodSamplesProduced + ...
        uint64(numel(incoming));
    state.maxDemodBufferSamples = max(state.maxDemodBufferSamples, ...
        uint64(numel(state.demodBuffer)));
end
if isempty(state.demodBuffer), return; end

bufferEnd = state.demodBufferStart + ...
    uint64(numel(state.demodBuffer)) - uint64(1);
frameSpan = uint64(state.cfg.frameSamples);
if bufferEnd + uint64(1) < frameSpan || ...
        bufferEnd - frameSpan + uint64(1) < state.nextSearchSample
    return;
end
searchThrough = bufferEnd - frameSpan + uint64(1);
candidates = nxdn.findFrameSync(state.demodBuffer, state.cfg);
offset = double(state.demodBufferStart) - 1 - ...
    state.pipelineDelaySamples;
for k = 1:numel(candidates)
    absoluteStart = state.demodBufferStart + ...
        uint64(candidates(k).fs_start - 1);
    if absoluteStart < state.nextSearchSample || ...
            absoluteStart > searchThrough
        continue;
    end
    absoluteCandidate = candidates(k);
    absoluteCandidate.fs_start = double(absoluteStart) - ...
        state.pipelineDelaySamples;
    accepted(end+1, 1) = absoluteCandidate; %#ok<AGROW>
    [state.frameState, framePdus] = ...
        nxdn.frameDecoderFeedCandidate( ...
            state.frameState, state.demodBuffer, candidates(k), ...
            'FsStartOffset', offset);
    pdus = appendPdus(pdus, framePdus);
end
state.nextSearchSample = searchThrough + uint64(1);

syncSpan = state.cfg.samplesPerSymbol * ...
    (numel(nxdn.constants().fswLevels) + 2);
guard = uint64(state.cfg.syncMinDistanceSamples + syncSpan);
if state.nextSearchSample > guard
    keepStart = state.nextSearchSample - guard;
else
    keepStart = uint64(1);
end
if keepStart > state.demodBufferStart
    drop = min(uint64(numel(state.demodBuffer)), ...
        keepStart - state.demodBufferStart);
    state.demodBuffer = state.demodBuffer(double(drop)+1:end);
    state.demodBufferStart = state.demodBufferStart + drop;
end
end

function values = counters(frameState)
values = struct( ...
    'candidateCount', frameState.candidateCount, ...
    'frameCount', frameState.frameCount, ...
    'validFrameCount', frameState.validFrameCount, ...
    'lichOkCount', frameState.lichOkCount, ...
    'channelBlockCount', frameState.channelBlockCount, ...
    'validChannelBlockCount', frameState.validChannelBlockCount, ...
    'sacchAssemblyCount', frameState.sacchAssemblyCount);
end

function diagnostics = deltaDiagnostics(state, before, after, candidates)
validFrames = after.validFrameCount - before.validFrameCount;
frameCount = after.frameCount - before.frameCount;
validBlocks = after.validChannelBlockCount - ...
    before.validChannelBlockCount;
blockCount = after.channelBlockCount - before.channelBlockCount;
lichCount = after.lichOkCount - before.lichOkCount;
quality = struct( ...
    'sync_candidate_count', numel(candidates), ...
    'lich_ok_count', double(lichCount), ...
    'valid_frame_ratio', safeRatio(validFrames, frameCount), ...
    'channel_block_pass_ratio', safeRatio(validBlocks, blockCount), ...
    'mean_valid_sync_score', 0);
diagnostics = struct( ...
    'syncCandidates', candidates, ...
    'frames', state.frameState.frames, ...
    'channelBlocks', state.frameState.blocks, ...
    'lichHistogram', repmat(struct('lich', 0, 'count', 0), 0, 1), ...
    'pduCount', double(state.frameState.pduCount), ...
    'validFrameCount', double(validFrames), ...
    'validChannelBlockCount', double(validBlocks), ...
    'sacchAssemblyCount', double(after.sacchAssemblyCount - ...
        before.sacchAssemblyCount), ...
    'quality', quality, ...
    'streamTotals', nxdn.frameDecoderReport(state.frameState));
end

function value = safeRatio(numerator, denominator)
if denominator == 0
    value = 0;
else
    value = double(numerator) / double(denominator);
end
end

function samples = pduSourceSamples(state, pdus)
samples = zeros(numel(pdus), 1, 'uint64');
for k = 1:numel(pdus)
    targetSample = radio.getNestedField(pdus(k), 'extra.fs_start', []);
    if isempty(targetSample)
        targetSample = radio.getNestedField( ...
            pdus(k), 'extra.start_sample', 0);
    end
    targetOffset = max(0, double(targetSample) - 1);
    inputOffset = round(targetOffset * ...
        state.inputSampleRateHz / state.targetSampleRateHz);
    samples(k) = state.sourceOriginSample + uint64(max(0, inputOffset));
end
end

function item = emptyCandidate()
item = struct('fs_start', 0, 'symbol_phase', 0, 'polarity', 1, ...
    'score', 0, 'frame_index', 0, 'locked', false);
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
