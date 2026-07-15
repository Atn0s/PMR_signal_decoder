function [key, isPersistent] = streamPduKey(pdu, sampleRateHz, varargin)
%STREAMPDUKEY Build an overlap-stable, epoch-local streaming PDU key.
p = inputParser;
p.addParameter('SemanticDeduplicate', true);
p.parse(varargin{:});
semantic = jsonencode(radio.dedupKey(pdu));
type = upper(char(radio.getField(pdu, 'type', '')));
isPersistent = logical(p.Results.SemanticDeduplicate) && ...
    (contains(type, 'CALL') || contains(type, 'SESSION'));
if isPersistent
    key = ['persistent:', semantic];
    return;
end
sourceSample = radio.getNestedField(pdu, 'extra.stream.source_sample', uint64(0));
bucketSamples = max(1, round(0.005 * sampleRateHz));
bucket = round(double(sourceSample) / bucketSamples);
key = sprintf('timed:%s:%d', semantic, bucket);
end
