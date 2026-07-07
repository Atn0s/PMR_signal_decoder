function line = formatPdu(pdu, foStr)
%FORMATPDU Format a DMR PDU.
if nargin < 2
    foStr = '';
end
line = sprintf('[%-12s] PROTO=%s SRC=%s DST=%s FLCO=%s FID=%s%s', ...
    char(radio.getField(pdu, 'type', '')), ...
    char(radio.getField(pdu, 'protocol', 'DMR')), ...
    valueToText(radio.getField(pdu, 'src', 0)), ...
    valueToText(radio.getField(pdu, 'dst', 0)), ...
    valueToText(radio.getField(pdu, 'flco', '')), ...
    valueToText(radio.getField(pdu, 'fid', '')), ...
    foStr);
end

function text = valueToText(value)
if isnumeric(value)
    if isscalar(value)
        text = num2str(value);
    else
        text = mat2str(value);
    end
elseif isstring(value)
    text = char(value);
elseif ischar(value)
    text = value;
else
    text = char(string(value));
end
end

