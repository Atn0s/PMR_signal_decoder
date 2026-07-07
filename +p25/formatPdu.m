function line = formatPdu(pdu, foStr)
%FORMATPDU Format a P25 PDU.
if nargin < 2
    foStr = '';
end
typ = char(radio.getField(pdu, 'type', ''));
prefix = sprintf('[%-12s] PROTO=P25', typ);
nac = radio.getNestedField(pdu, 'extra.nac', []);
if isempty(nac)
    nacStr = '';
else
    nacStr = sprintf(' NAC=0x%03X', double(nac));
end

switch typ
    case 'P25_HDU'
        line = sprintf('%s FRAME=HDU%s%s%s', prefix, nacStr, p25.detail(pdu), foStr);
    case 'P25_LDU1'
        callType = char(radio.getNestedField(pdu, 'extra.call_type', ''));
        if strcmp(callType, 'group')
            party = sprintf(' SRC=%s TGID=%s', textValue(radio.getField(pdu, 'src', 0)), ...
                textValue(radio.getNestedField(pdu, 'extra.tgid', 0)));
        elseif strcmp(callType, 'unit_to_unit')
            party = sprintf(' SRC=%s DEST=%s', textValue(radio.getField(pdu, 'src', 0)), ...
                textValue(radio.getField(pdu, 'dst', 0)));
        else
            party = '';
        end
        line = sprintf('%s FRAME=LDU1%s%s%s%s', prefix, party, nacStr, p25.detail(pdu), foStr);
    case 'P25_LDU2'
        line = sprintf('%s FRAME=LDU2%s%s%s', prefix, nacStr, p25.detail(pdu), foStr);
    case 'P25_CALL'
        flco = char(radio.getField(pdu, 'flco', ''));
        if strcmp(flco, 'GROUP')
            call = 'GROUP';
            party = sprintf(' SRC=%s TGID=%s', textValue(radio.getField(pdu, 'src', 0)), ...
                textValue(radio.getField(pdu, 'dst', 0)));
        else
            call = 'UNIT';
            party = sprintf(' SRC=%s DEST=%s', textValue(radio.getField(pdu, 'src', 0)), ...
                textValue(radio.getField(pdu, 'dst', 0)));
        end
        dur = radio.getNestedField(pdu, 'extra.duration_s', []);
        if isempty(dur), durStr = ''; else, durStr = sprintf(' DUR=%ss', textValue(dur)); end
        lduCount = radio.getNestedField(pdu, 'extra.ldu_count', []);
        if isempty(lduCount), lduStr = ''; else, lduStr = sprintf(' LDUS=%s', textValue(lduCount)); end
        line = sprintf('%s CALL=%s%s%s%s%s', prefix, call, party, nacStr, durStr, lduStr);
        line = [line foStr];
    otherwise
        frame = char(radio.getField(pdu, 'flco', radio.getNestedField(pdu, 'extra.duid_name', '')));
        line = sprintf('%s FRAME=%s%s%s%s', prefix, frame, nacStr, p25.detail(pdu), foStr);
end
end

function text = textValue(value)
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

