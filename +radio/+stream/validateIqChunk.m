function validateIqChunk(chunk)
%VALIDATEIQCHUNK Enforce the common streaming IQ block contract.
required = {'channelId', 'sequenceNumber', 'sourceSampleStart', ...
    'sourceSampleEnd', 'timestampStartNs', 'centerFrequencyHz', ...
    'sampleRateHz', 'iq', 'discontinuity', 'droppedSourceSamples'};
if ~isstruct(chunk) || ~isscalar(chunk)
    error('radio:stream:validateIqChunk:Type', ...
        'An IQ chunk must be a scalar struct.');
end
missing = required(~isfield(chunk, required));
if ~isempty(missing)
    error('radio:stream:validateIqChunk:MissingField', ...
        'IQ chunk is missing field: %s', missing{1});
end
if ~isnumeric(chunk.sampleRateHz) || ~isscalar(chunk.sampleRateHz) || ...
        ~isfinite(chunk.sampleRateHz) || chunk.sampleRateHz <= 0
    error('radio:stream:validateIqChunk:SampleRate', ...
        'sampleRateHz must be a positive finite scalar.');
end
if ~isvector(chunk.iq) && ~isempty(chunk.iq)
    error('radio:stream:validateIqChunk:IqShape', 'IQ data must be a vector.');
end
if chunk.sourceSampleEnd < chunk.sourceSampleStart
    error('radio:stream:validateIqChunk:SampleRange', ...
        'sourceSampleEnd must not precede sourceSampleStart.');
end
expectedCount = chunk.sourceSampleEnd - chunk.sourceSampleStart;
if expectedCount ~= uint64(numel(chunk.iq))
    error('radio:stream:validateIqChunk:SampleCount', ...
        'Absolute sample range does not match IQ length.');
end
if ~isscalar(chunk.discontinuity)
    error('radio:stream:validateIqChunk:Discontinuity', ...
        'discontinuity must be scalar.');
end
end
