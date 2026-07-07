function text = detail(pdu)
%DETAIL P25 frame detail string.
duid = radio.getNestedField(pdu, 'extra.duid', []);
if isempty(duid)
    base = '';
else
    validBch = logical(radio.getNestedField(pdu, 'extra.valid_bch', false));
    corrected = logical(radio.getNestedField(pdu, 'extra.corrected', false));
    base = sprintf(' DUID=0x%X BCH=%s CORR=%d', double(duid), okFail(validBch), corrected);
end

typ = char(radio.getField(pdu, 'type', ''));
switch typ
    case 'P25_HDU'
        text = sprintf('%s MI=0x%018X MFID=0x%02X ALGID=0x%02X KID=0x%04X TGID=%s', ...
            base, double(radio.getNestedField(pdu, 'extra.mi', 0)), ...
            double(radio.getNestedField(pdu, 'extra.hdu_mfid', 0)), ...
            double(radio.getNestedField(pdu, 'extra.algid', 0)), ...
            double(radio.getNestedField(pdu, 'extra.kid', 0)), ...
            valueText(radio.getNestedField(pdu, 'extra.hdu_tgid', 0)));
    case 'P25_LDU1'
        text = sprintf('%s LCF=0x%02X MFID=0x%02X CALL=%s LCW16=0x%04X', ...
            base, double(radio.getNestedField(pdu, 'extra.lco', 0)), ...
            double(radio.getNestedField(pdu, 'extra.mfid', 0)), ...
            char(radio.getNestedField(pdu, 'extra.call_type', '')), ...
            double(radio.getNestedField(pdu, 'extra.lc_info', 0)));
    case 'P25_LDU2'
        text = sprintf('%s ES_MI=0x%018X ES_ALGID=0x%02X ES_KID=0x%04X', ...
            base, double(radio.getNestedField(pdu, 'extra.es_mi', 0)), ...
            double(radio.getNestedField(pdu, 'extra.es_algid', 0)), ...
            double(radio.getNestedField(pdu, 'extra.es_kid', 0)));
    otherwise
        text = base;
end
end

function text = okFail(tf)
if tf
    text = 'OK';
else
    text = 'FAIL';
end
end

function text = valueText(value)
if isnumeric(value), text = num2str(value); else, text = char(string(value)); end
end

