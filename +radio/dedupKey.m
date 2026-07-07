function key = dedupKey(pdu)
%DEDUPKEY Dispatch protocol-aware PDU keys.
proto = char(radio.getField(pdu, 'protocol', 'DMR'));
try
    spec = radio.specForProtocol(proto);
    key = spec.dedupFcn(pdu);
catch
    key = dmr.dedupKey(pdu);
end
end

