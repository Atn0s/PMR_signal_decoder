function key = dedupKey(pdu)
%DEDUPKEY dPMR semantic de-duplication key.
cfg = dpmr.config();
ptype = char(radio.getField(pdu, 'type', ''));
src = valueOrEmpty(radio.getField(pdu, 'src', ''));
dst = valueOrEmpty(radio.getField(pdu, 'dst', ''));
colorCode = radio.getNestedField(pdu, 'extra.color_code', []);
syncType = radio.getNestedField(pdu, 'extra.sync_type', '');

if strcmp(ptype, 'dPMR_CALL')
    key = {'dPMR', 'CALL', src, dst, colorCode, radio.getField(pdu, 'flco', ''), ...
        tupleValue(radio.getNestedField(pdu, 'extra.communication_modes', [])), ...
        tupleValue(radio.getNestedField(pdu, 'extra.comms_formats', []))};
    return;
end

if hasValue(src) || hasValue(dst)
    key = {'dPMR', ptype, src, dst, colorCode, syncType};
    return;
end

cchSig = cchSignature(radio.getNestedField(pdu, 'extra.cch', []));
if ~isempty(cchSig)
    key = {'dPMR', ptype, colorCode, syncType, cchSig};
    return;
end

fsStart = radio.getNestedField(pdu, 'extra.fs_start', 0);
frameBucket = round(double(fsStart) / cfg.dedupFrameBucketSamples);
key = {'dPMR', ptype, colorCode, syncType, frameBucket};
end

function value = valueOrEmpty(value)
if isempty(value) || (isnumeric(value) && isscalar(value) && value == 0)
    value = '';
end
end

function yes = hasValue(value)
yes = ~(isempty(value) || (isnumeric(value) && isscalar(value) && value == 0));
end

function out = tupleValue(value)
if isempty(value)
    out = {};
elseif iscell(value)
    out = value(:).';
elseif isnumeric(value) || islogical(value)
    out = num2cell(value(:).');
else
    out = {value};
end
end

function sig = cchSignature(records)
sig = {};
if isempty(records) || ~isstruct(records)
    return;
end
for k = 1:numel(records)
    sig{end+1} = { ... %#ok<AGROW>
        fieldOr(records(k), 'frame_number', []), ...
        fieldOr(records(k), 'id_half', []), ...
        fieldOr(records(k), 'communication_mode', []), ...
        fieldOr(records(k), 'comms_format', []), ...
        fieldOr(records(k), 'emergency_priority', [])};
end
end

function value = fieldOr(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
