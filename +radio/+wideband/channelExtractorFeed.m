function [state, chunk] = channelExtractorFeed(state, track, batch)
%CHANNELEXTRACTORFEED Fine-tune one active PFB subband into baseband IQ.
bin = double(state.coarseBin);
if bin < 1 || bin > size(batch.iq, 1)
    error('radio:wideband:channelExtractorFeed:CoarseBin', ...
        'Extractor coarse bin is outside the channelizer output.');
end
hasGap = batch.outputSampleStart ~= state.lastOutputSampleEnd;
reset = batch.discontinuity || ...
    batch.continuityGeneration ~= state.continuityGeneration || hasGap;
if reset
    state.ncoPhaseRad = 0;
    state.filterState(:) = 0;
    state.mappingOutputSampleStart = uint64(batch.outputSampleStart);
    state.mappingWidebandSourceSample = firstSourceSample(batch);
    state.continuityGeneration = uint64(batch.continuityGeneration);
end

iq = batch.iq(bin, :).';
residualOffsetHz = double(track.frequencyOffsetHz) - ...
    state.coarseCenterOffsetHz;
increment = 2 * pi * residualOffsetHz / state.sampleRateHz;
phases = state.ncoPhaseRad + increment .* (0:numel(iq)-1).';
shifted = iq .* single(exp(-1i .* phases));
state.ncoPhaseRad = mod( ...
    state.ncoPhaseRad + increment * numel(iq), 2*pi);
[filtered, state.filterState] = filter( ...
    state.filterCoefficients, 1, shifted, state.filterState);

chunk = radio.stream.makeIqChunk(filtered, state.sampleRateHz, ...
    batch.outputSampleStart, ...
    'ChannelId', state.channelId, ...
    'SequenceNumber', state.sequenceNumber, ...
    'CenterFrequencyHz', track.centerFrequencyHz, ...
    'Discontinuity', reset, ...
    'DroppedSourceSamples', batch.droppedSourceSamples);
chunk.widebandSourceSampleStart = firstSourceSample(batch);
chunk.widebandSourceSampleEnd = lastSourceSample(batch);
chunk.widebandSampleRateHz = batch.widebandSampleRateHz;
chunk.widebandCenterFrequencyHz = batch.widebandCenterFrequencyHz;
chunk.frequencyOffsetHz = track.frequencyOffsetHz;
chunk.coarseBin = state.coarseBin;
chunk.coarseCenterOffsetHz = state.coarseCenterOffsetHz;

state.lastOutputSampleEnd = uint64(batch.outputSampleEnd);
state.sequenceNumber = state.sequenceNumber + uint64(1);
end

function sample = firstSourceSample(batch)
if isempty(batch.frameSourceSamples)
    sample = 0.0;
else
    sample = double(batch.frameSourceSamples(1));
end
end

function sample = lastSourceSample(batch)
if isempty(batch.frameSourceSamples)
    sample = firstSourceSample(batch);
else
    sample = double(batch.frameSourceSamples(end) + ...
        batch.widebandSampleRateHz / batch.sampleRateHz);
end
end
