function key = dedupKey(pdu)
%DEDUPKEY P25 semantic de-duplication key.
cfg = p25.config();
ptype = char(radio.getField(pdu, 'type', ''));
nac = radio.getNestedField(pdu, 'extra.nac', []);

if strcmp(ptype, 'P25_CALL')
    key = {'P25', 'CALL', nac, radio.getField(pdu, 'src', 0), ...
        radio.getField(pdu, 'dst', 0), radio.getField(pdu, 'flco', '')};
    return;
end

if strcmp(ptype, 'P25_HDU') && anyExtra(pdu, {'mi', 'hdu_mfid', 'algid', 'kid', 'hdu_tgid'})
    key = {'P25', 'HDU', nac, ...
        radio.getNestedField(pdu, 'extra.mi', []), ...
        radio.getNestedField(pdu, 'extra.hdu_mfid', []), ...
        radio.getNestedField(pdu, 'extra.algid', []), ...
        radio.getNestedField(pdu, 'extra.kid', []), ...
        radio.getNestedField(pdu, 'extra.hdu_tgid', radio.getField(pdu, 'dst', 0))};
    return;
end

if strcmp(ptype, 'P25_LDU1') && anyExtra(pdu, {'lco', 'mfid', 'call_type', 'lc_info'})
    dst = radio.getField(pdu, 'dst', []);
    if isempty(dst) || (isnumeric(dst) && isscalar(dst) && dst == 0)
        dst = radio.getNestedField(pdu, 'extra.tgid', 0);
    end
    key = {'P25', 'LDU1', nac, ...
        radio.getField(pdu, 'src', 0), ...
        dst, ...
        radio.getNestedField(pdu, 'extra.call_type', ''), ...
        radio.getNestedField(pdu, 'extra.lco', []), ...
        radio.getNestedField(pdu, 'extra.mfid', []), ...
        radio.getNestedField(pdu, 'extra.lc_info', [])};
    return;
end

if strcmp(ptype, 'P25_LDU2') && anyExtra(pdu, {'es_mi', 'es_algid', 'es_kid'})
    key = {'P25', 'LDU2', nac, ...
        radio.getNestedField(pdu, 'extra.es_mi', []), ...
        radio.getNestedField(pdu, 'extra.es_algid', []), ...
        radio.getNestedField(pdu, 'extra.es_kid', [])};
    return;
end

fsStart = radio.getNestedField(pdu, 'extra.fs_start', 0);
frameBucket = round(double(fsStart) / cfg.dedupFrameBucketSamples);
key = {'P25', nac, ptype, frameBucket};
end

function yes = anyExtra(pdu, names)
yes = false;
for k = 1:numel(names)
    value = radio.getNestedField(pdu, ['extra.' names{k}], []);
    if ~isempty(value)
        yes = true;
        return;
    end
end
end
