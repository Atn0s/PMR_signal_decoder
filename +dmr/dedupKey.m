function key = dedupKey(pdu)
%DEDUPKEY DMR SRC/DST/type/frequency-bucket key.
cfg = dmr.config();
proto = char(radio.getField(pdu, 'protocol', 'DMR'));
if strcmpi(proto, 'dmr')
    proto = 'DMR';
end
fo = radio.getField(pdu, 'fo_hz', 0);
foBucket = round(double(fo) / cfg.dedupFrequencyBucketHz) * cfg.dedupFrequencyBucketHz;
key = {proto, radio.getField(pdu, 'src', 0), radio.getField(pdu, 'dst', 0), ...
    char(radio.getField(pdu, 'type', '')), foBucket};
end

