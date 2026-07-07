function line = formatPdu(pdu)
%FORMATPDU Format one PDU using its protocol formatter.
proto = char(radio.getField(pdu, 'protocol', 'DMR'));
fo = radio.getField(pdu, 'fo_hz', []);
if isempty(fo)
    foStr = '';
else
    foStr = sprintf(' (fo=%+.1fkHz)', double(fo) / 1e3);
end
try
    spec = radio.specForProtocol(proto);
    line = spec.formatterFcn(pdu, foStr);
catch
    line = dmr.formatPdu(pdu, foStr);
end
end

