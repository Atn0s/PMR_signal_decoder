function [state, outputChunks] = multiDdcFeed(state, inputChunk)
%MULTIDDCFEED Downconvert all selected carriers in one matrix operation.
radio.stream.validateIqChunk(inputChunk);
if inputChunk.sampleRateHz ~= state.inputSampleRateHz
    error('radio:tuned:multiDdcFeed:SampleRate', ...
        'Input sample rate changed inside the matrix DDC stream.');
end
previousExpected = state.expectedInputSample;
isFirst = isempty(previousExpected);
hasGap = ~isFirst && inputChunk.sourceSampleStart ~= previousExpected;
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
    state.mixerPhases = complex(ones(1, state.capacity));
end
if isempty(state.pendingIq)
    state.pendingSourceSampleStart = inputChunk.sourceSampleStart;
end
state.pendingIq = [state.pendingIq; double(inputChunk.iq(:))];
state.inputSamplesReceived = state.inputSamplesReceived + ...
    uint64(numel(inputChunk.iq));
state.expectedInputSample = inputChunk.sourceSampleEnd;
state.feedCount = state.feedCount + uint64(1);

blockCount = floor(numel(state.pendingIq) / state.inputBlockSamples);
processCount = blockCount * state.inputBlockSamples;
if processCount == 0
    outputChunks = cell(0, 1);
    return;
end
processStart = state.pendingSourceSampleStart;
samples = state.pendingIq(1:processCount);
state.pendingIq = state.pendingIq(processCount+1:end);
state.pendingSourceSampleStart = processStart + uint64(processCount);
outputBlockSamples = state.inputBlockSamples / state.decimationFactor;
baseband = complex(zeros(blockCount * outputBlockSamples, state.capacity));
for blockIndex = 1:blockCount
    first = (blockIndex - 1) * state.inputBlockSamples + 1;
    last = first + state.inputBlockSamples - 1;
    [state, mixed] = mixBlock(state, samples(first:last));
    firstOutput = (blockIndex - 1) * outputBlockSamples + 1;
    lastOutput = firstOutput + outputBlockSamples - 1;
    baseband(firstOutput:lastOutput, :) = state.converter(mixed);
end

droppedInputSamples = uint64(inputChunk.droppedSourceSamples);
if hasGap && inputChunk.sourceSampleStart > previousExpected
    droppedInputSamples = droppedInputSamples + ...
        inputChunk.sourceSampleStart - previousExpected;
end
droppedOutputSamples = uint64(ceil( ...
    double(droppedInputSamples) / state.decimationFactor));
outputChunks = cell(state.activeChannelCount, 1);
for k = 1:state.activeChannelCount
    chunk = radio.stream.makeIqChunk( ...
        baseband(:, k), state.outputSampleRateHz, state.nextOutputSample, ...
        'ChannelId', state.channelIds(k), ...
        'SequenceNumber', state.nextSequenceNumber, ...
        'CenterFrequencyHz', state.targetCenterFrequenciesHz(k), ...
        'Discontinuity', resetNow, ...
        'DroppedSourceSamples', droppedOutputSamples);
    chunk.widebandSourceSampleStart = processStart;
    chunk.widebandSourceSampleEnd = processStart + uint64(processCount);
    chunk.widebandSampleRateHz = state.inputSampleRateHz;
    chunk.widebandCenterFrequencyHz = state.inputCenterFrequencyHz;
    chunk.frequencyOffsetHz = state.frequencyOffsetsHz(k);
    chunk.decimationFactor = state.decimationFactor;
    chunk.continuityGeneration = state.continuityGeneration;
    chunk.isFilterFlush = false;
    outputChunks{k} = chunk;
end
state.nextOutputSample = state.nextOutputSample + ...
    uint64(size(baseband, 1));
state.nextSequenceNumber = state.nextSequenceNumber + uint64(1);
state.inputSamplesConverted = state.inputSamplesConverted + ...
    uint64(processCount);
state.outputSamplesProduced = state.outputSamplesProduced + ...
    uint64(size(baseband, 1));
end

function [state, mixed] = mixBlock(state, samples)
oscillator = state.mixerTemplate .* state.mixerPhases;
mixed = samples(:) .* oscillator;
state.mixerPhases = state.mixerPhases .* state.mixerBlockSteps;
end
