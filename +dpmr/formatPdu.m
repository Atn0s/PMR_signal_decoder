function line = formatPdu(pdu, foStr)
%FORMATPDU Format a dPMR PDU.
if nargin < 2
    foStr = '';
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

