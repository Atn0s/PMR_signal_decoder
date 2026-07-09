function line = formatPdu(pdu, foStr)
%FORMATPDU Format a dPMR PDU.
if nargin < 2
    foStr = '';
end
if strcmp(char(radio.getField(pdu, 'type', '')), 'dPMR_CALL')
    line = formatCall(pdu, foStr);
    return;
end
cc = radio.getNestedField(pdu, 'extra.color_code', -1);
if isnumeric(cc) && cc >= 0
    ccText = sprintf('%02d', double(cc));
else
    ccText = '--';
end
if logical(radio.getNestedField(pdu, 'extra.polarity_inverted', false))
    pol = 'INV';
else
    pol = 'NORM';
end
cch = dpmr.formatCch(radio.getNestedField(pdu, 'extra.cch', []));
line = sprintf('[%-12s] PROTO=dPMR SRC=%s DST=%s CC=%s SYNC=%s POL=%s%s%s', ...
    char(radio.getField(pdu, 'type', '')), ...
    textValue(radio.getField(pdu, 'src', '')), ...
    textValue(radio.getField(pdu, 'dst', '')), ...
    ccText, ...
    textValue(radio.getNestedField(pdu, 'extra.sync_type', '')), ...
    pol, cch, foStr);
end

function line = formatCall(pdu, foStr)
extra = radio.getField(pdu, 'extra', struct());
cc = radio.getNestedField(extra, 'color_code', -1);
if isnumeric(cc) && ~isempty(cc) && cc >= 0
    ccText = sprintf('%02d', double(cc));
else
    ccText = '--';
end
duration = radio.getNestedField(extra, 'duration_s', []);
if isempty(duration)
    dur = '';
else
    dur = sprintf(' DUR=%ss', textValue(duration));
end
line = sprintf('[%-12s] PROTO=dPMR CALL=%s SRC=%s DST=%s CC=%s%s HDR=%s VOICE=%s CCH=%s SYNC=%s MODE=%s FMT=%s E=%s CLOSED=%s%s', ...
    char(radio.getField(pdu, 'type', '')), ...
    textValue(radio.getField(pdu, 'flco', '')), ...
    textValue(radio.getField(pdu, 'src', '')), ...
    textValue(radio.getField(pdu, 'dst', '')), ...
    ccText, ...
    dur, ...
    textValue(radio.getNestedField(extra, 'header_count', 0)), ...
    textValue(radio.getNestedField(extra, 'voice_count', 0)), ...
    textValue(radio.getNestedField(extra, 'cch_count', 0)), ...
    joinValues(radio.getNestedField(extra, 'sync_types', {})), ...
    joinValues(radio.getNestedField(extra, 'communication_modes', [])), ...
    joinValues(radio.getNestedField(extra, 'comms_formats', [])), ...
    joinValues(radio.getNestedField(extra, 'emergency_priorities', [])), ...
    textValue(radio.getNestedField(extra, 'closed_by', '')), ...
    foStr);
end

function text = joinValues(value)
if isempty(value)
    text = '';
elseif iscell(value)
    parts = cellfun(@textValue, value, 'UniformOutput', false);
    text = strjoin(parts, ',');
elseif isnumeric(value)
    parts = arrayfun(@(x) num2str(x), value(:).', 'UniformOutput', false);
    text = strjoin(parts, ',');
else
    text = textValue(value);
end
end

function text = textValue(value)
if isnumeric(value)
    if isscalar(value), text = num2str(value); else, text = mat2str(value); end
elseif isstring(value)
    text = char(value);
elseif ischar(value)
    text = value;
else
    text = char(string(value));
end
end
