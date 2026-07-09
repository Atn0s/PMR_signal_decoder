function key = dedupKey(pdu)
%DEDUPKEY TETRA event/session de-duplication key.
typ = char(radio.getField(pdu, 'type', ''));
extra = radio.getField(pdu, 'extra', struct());
startBit = radio.getNestedField(pdu, 'extra.slot_start_bit', []);
if isempty(startBit)
    startBit = radio.getNestedField(pdu, 'extra.start_bit', []);
end
if isempty(startBit)
    startBit = 0;
end
if strcmp(typ, 'TETRA_SESSION')
    startBit = radio.getNestedField(pdu, 'extra.start_bit', startBit);
    key = {'TETRA', typ, radio.getField(pdu, 'src', 0), radio.getField(pdu, 'dst', 0), startBit};
else
    key = {'TETRA', typ, radio.getField(pdu, 'src', 0), radio.getField(pdu, 'dst', 0), ...
        radio.getNestedField(extra, 'frame_number', []), radio.getNestedField(extra, 'slot_number', []), ...
        radio.getNestedField(extra, 'block_name', ''), radio.getField(pdu, 'flco', ''), startBit};
end
end
