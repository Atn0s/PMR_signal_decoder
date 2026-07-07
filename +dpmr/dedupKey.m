function key = dedupKey(pdu)
%DEDUPKEY dPMR SRC/DST/color/frame-bucket key.
cfg = dpmr.config();
fsStart = radio.getNestedField(pdu, 'extra.fs_start', 0);
frameBucket = round(double(fsStart) / cfg.dedupFrameBucketSamples);
key = {'dPMR', radio.getField(pdu, 'src', ''), radio.getField(pdu, 'dst', ''), ...
    radio.getNestedField(pdu, 'extra.color_code', []), frameBucket};
end

