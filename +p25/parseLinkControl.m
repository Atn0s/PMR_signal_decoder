function lc = parseLinkControl(lc72)
%PARSELINKCONTROL Parse 72-bit P25 link control.
if numel(lc72) ~= 72
    lc = [];
    return;
end
lco = p25.bitsToInt(lc72(1:8));
mfid = p25.bitsToInt(lc72(9:16));
octet2 = p25.bitsToInt(lc72(17:24));
octet3 = p25.bitsToInt(lc72(25:32));
lcInfo = p25.bitsToInt(lc72(17:32));
svc = octet2;
isGroup = lco == 0;
if isGroup
    emergency = logical(lc72(17));
    reserved = p25.bitsToInt(lc72(18:32));
    reservedBits = 15;
    tgid = p25.bitsToInt(lc72(33:48));
    src = p25.bitsToInt(lc72(49:72));
    dst = tgid;
    callType = 'group';
elseif lco == 3
    emergency = [];
    reserved = octet2;
    reservedBits = 8;
    tgid = 0;
    dst = p25.bitsToInt(lc72(25:48));
    src = p25.bitsToInt(lc72(49:72));
    callType = 'unit_to_unit';
else
    emergency = [];
    reserved = lcInfo;
    reservedBits = 16;
    tgid = 0;
    src = 0;
    dst = 0;
    callType = sprintf('unknown_0x%02X', lco);
end
lc = struct( ...
    'lco', lco, ...
    'mfid', mfid, ...
    'svc', svc, ...
    'lc_info', lcInfo, ...
    'octet2', octet2, ...
    'octet3', octet3, ...
    'emergency', emergency, ...
    'reserved', reserved, ...
    'reserved_bits', reservedBits, ...
    'src', src, ...
    'dst', dst, ...
    'tgid', tgid, ...
    'is_group', isGroup, ...
    'call_type', callType, ...
    'raw', lc72(:).');
end

