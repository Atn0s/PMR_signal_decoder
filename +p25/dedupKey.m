function key = dedupKey(pdu)
%DEDUPKEY P25 NAC/type/frame-bucket key.
cfg = p25.config();
nac = radio.getNestedField(pdu, 'extra.nac', []);
fsStart = radio.getNestedField(pdu, 'extra.fs_start', 0);
frameBucket = round(double(fsStart) / cfg.dedupFrameBucketSamples);
key = {'P25', nac, char(radio.getField(pdu, 'type', '')), frameBucket};
end

