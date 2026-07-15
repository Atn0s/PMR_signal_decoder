function [state, outputChunk] = ddcFeed(state, inputChunk)
%DDCFEED Downconvert one continuous wideband IqChunk into 120 kS/s IQ.
radio.stream.validateIqChunk(inputChunk);
if inputChunk.sampleRateHz ~= state.inputSampleRateHz
    error('radio:tuned:ddcFeed:SampleRate', ...
        'Input chunk sample rate changed inside one DDC stream.');
end

previousExpectedInputSample = state.expectedInputSample;
isFirst = isempty(previousExpectedInputSample);
hasGap = ~isFirst && ...
    inputChunk.sourceSampleStart ~= previousExpectedInputSample;
resetNow = logical(inputChunk.discontinuity) || hasGap;
if isFirst || resetNow
    if ~isFirst
        reset(state.converter);
        state.continuityGeneration = ...
            state.continuityGeneration + uint64(1);
    end
    state.pendingIq = complex(zeros(0, 1));
    state.pendingSourceSampleStart = inputChunk.sourceSampleStart;
    state.nextOutputSample = uint64(floor( ...
        double(inputChunk.sourceSampleStart) / state.decimationFactor));
    if strcmp(state.mixerMode, 'external')
        state.mixerPhase = complex(1);
    end
end

if isempty(state.pendingIq)
    state.pendingSourceSampleStart = inputChunk.sourceSampleStart;
end
inputIq = double(inputChunk.iq(:));
if strcmp(state.mixerMode, 'external') && ~isempty(inputIq)
    oscillator = complex(ones(numel(inputIq), 1));
    if numel(inputIq) > 1
        oscillator(2:end) = cumprod(repmat( ...
            state.mixerStep, numel(inputIq) - 1, 1));
    end
    oscillator = state.mixerPhase .* oscillator;
    inputIq = inputIq .* oscillator;
    state.mixerPhase = oscillator(end) .* state.mixerStep;
end
state.pendingIq = [state.pendingIq; inputIq];
state.inputSamplesReceived = state.inputSamplesReceived + ...
    uint64(numel(inputChunk.iq));
state.expectedInputSample = inputChunk.sourceSampleEnd;

blockCount = floor(numel(state.pendingIq) / state.inputBlockSamples);
processCount = blockCount * state.inputBlockSamples;
if processCount == 0
    outputChunk = [];
    return;
end

processStart = state.pendingSourceSampleStart;
samples = state.pendingIq(1:processCount);
state.pendingIq = state.pendingIq(processCount+1:end);
state.pendingSourceSampleStart = processStart + uint64(processCount);
outputBlockSamples = state.inputBlockSamples / state.decimationFactor;
baseband = complex(zeros(blockCount * outputBlockSamples, 1));
for blockIndex = 1:blockCount
    first = (blockIndex - 1) * state.inputBlockSamples + 1;
    last = first + state.inputBlockSamples - 1;
    firstOutput = (blockIndex - 1) * outputBlockSamples + 1;
    lastOutput = firstOutput + outputBlockSamples - 1;
    baseband(firstOutput:lastOutput) = ...
        state.converter(samples(first:last));
end
expectedOutputCount = processCount / state.decimationFactor;
if numel(baseband) ~= expectedOutputCount
    error('radio:tuned:ddcFeed:OutputCount', ...
        'Digital downconverter returned an unexpected sample count.');
end

droppedInputSamples = uint64(inputChunk.droppedSourceSamples);
if hasGap && inputChunk.sourceSampleStart > previousExpectedInputSample
    droppedInputSamples = droppedInputSamples + ...
        inputChunk.sourceSampleStart - previousExpectedInputSample;
end
droppedOutputSamples = uint64(ceil( ...
    double(droppedInputSamples) / state.decimationFactor));
outputChunk = radio.stream.makeIqChunk( ...
    baseband, state.outputSampleRateHz, state.nextOutputSample, ...
    'ChannelId', state.channelId, ...
    'SequenceNumber', state.nextSequenceNumber, ...
    'CenterFrequencyHz', state.targetCenterFrequencyHz, ...
    'Discontinuity', resetNow, ...
    'DroppedSourceSamples', droppedOutputSamples);
outputChunk.widebandSourceSampleStart = processStart;
outputChunk.widebandSourceSampleEnd = processStart + uint64(processCount);
outputChunk.widebandSampleRateHz = state.inputSampleRateHz;
outputChunk.widebandCenterFrequencyHz = state.inputCenterFrequencyHz;
outputChunk.frequencyOffsetHz = state.frequencyOffsetHz;
outputChunk.decimationFactor = state.decimationFactor;
outputChunk.continuityGeneration = state.continuityGeneration;
outputChunk.isFilterFlush = false;

state.nextOutputSample = outputChunk.sourceSampleEnd;
state.nextSequenceNumber = state.nextSequenceNumber + uint64(1);
state.inputSamplesConverted = state.inputSamplesConverted + ...
    uint64(processCount);
state.outputSamplesProduced = state.outputSamplesProduced + ...
    uint64(numel(baseband));
end
