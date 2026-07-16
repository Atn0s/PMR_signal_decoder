function sampleCount = validateIqChunkDescriptor(chunk)
%VALIDATEIQCHUNKDESCRIPTOR Validate a full IQ chunk or data-free transport.
required = {'channelId', 'sequenceNumber', 'sourceSampleStart', ...
    'sourceSampleEnd', 'timestampStartNs', 'centerFrequencyHz', ...
    'sampleRateHz', 'iq', 'discontinuity', 'droppedSourceSamples'};
if ~isstruct(chunk) || ~isscalar(chunk)
    error('radio:stream:validateIqChunkDescriptor:Type', ...
        'An IQ descriptor must be a scalar struct.');
end
missing = required(~isfield(chunk, required));
if ~isempty(missing)
    error('radio:stream:validateIqChunkDescriptor:MissingField', ...
        'IQ descriptor is missing field: %s', missing{1});
end
if ~isnumeric(chunk.sampleRateHz) || ~isscalar(chunk.sampleRateHz) || ...
        ~isfinite(chunk.sampleRateHz) || chunk.sampleRateHz <= 0
    error('radio:stream:validateIqChunkDescriptor:SampleRate', ...
        'sampleRateHz must be a positive finite scalar.');
end
if chunk.sourceSampleEnd < chunk.sourceSampleStart
    error('radio:stream:validateIqChunkDescriptor:SampleRange', ...
        'sourceSampleEnd must not precede sourceSampleStart.');
end
sampleCount = uint64(chunk.sourceSampleEnd - chunk.sourceSampleStart);
if numel(chunk.iq) == double(sampleCount)
    radio.stream.validateIqChunk(chunk);
    return;
end
transportCount = radio.getField(chunk, 'transportSampleCount', []);
if ~isempty(chunk.iq) || isempty(transportCount) || ...
        uint64(transportCount) ~= sampleCount
    error('radio:stream:validateIqChunkDescriptor:SampleCount', ...
        ['A data-free descriptor requires empty IQ and a ', ...
         'transportSampleCount matching its absolute sample range.']);
end
if ~isscalar(chunk.discontinuity)
    error('radio:stream:validateIqChunkDescriptor:Discontinuity', ...
        'discontinuity must be scalar.');
end
end
