function key = dedupKey(pdu)
%DEDUPKEY NXDN semantic de-duplication key.
ptype = char(radio.getField(pdu, 'type', ''));
ran = radio.getNestedField(pdu, 'extra.ran', []);
if strcmp(ptype, 'NXDN_CALL')
    key = {'NXDN', 'CALL', ran, radio.getField(pdu, 'src', 0), ...
        radio.getField(pdu, 'dst', 0), radio.getField(pdu, 'flco', ''), ...
        radio.getNestedField(pdu, 'extra.start_sample', [])};
else
    key = {'NXDN', ptype, ran, radio.getField(pdu, 'src', 0), ...
        radio.getField(pdu, 'dst', 0), ...
        radio.getNestedField(pdu, 'extra.payload_hex', '')};
end
end
