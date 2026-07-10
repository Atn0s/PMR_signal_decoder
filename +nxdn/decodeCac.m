function block = decodeCac(bits, kind)
%DECODECAC Decode outbound, inbound-long, or inbound-short NXDN CAC.
c = nxdn.constants();
kind = upper(char(kind));
switch kind
    case {'CAC_OUTBOUND', 'OUTBOUND'}
        [decoded, codec] = nxdn.decodeChannel(bits, 12, 25, ...
            c.punctureCacOutbound, 350);
        infoLength = 155; crcEnd = 171; layerEnd = 152;
        nullBits = decoded(153:155);
        channelName = 'CAC_OUTBOUND';
    case {'CAC_LONG_INBOUND', 'LONG_INBOUND'}
        [decoded, codec] = nxdn.decodeChannel(bits, 12, 21, ...
            c.punctureCacLongInbound, 312);
        infoLength = 136; crcEnd = 152; layerEnd = 136;
        nullBits = false(0, 1);
        channelName = 'CAC_LONG_INBOUND';
    case {'CAC_SHORT_INBOUND', 'SHORT_INBOUND'}
        [decoded, codec] = nxdn.decodeChannel(bits, 12, 21, ...
            c.punctureCacShortInbound, 252);
        infoLength = 106; crcEnd = 122; layerEnd = 104;
        nullBits = decoded(105:106);
        channelName = 'CAC_SHORT_INBOUND';
    otherwise
        error('nxdn:decodeCac:UnknownKind', 'Unknown CAC kind: %s', kind);
end
tail = decoded(crcEnd+1:crcEnd+4);
remainder = nxdn.crc16Cac(decoded(1:crcEnd));
block = struct('channel', channelName, 'decoded_bits', decoded(:).', ...
    'codec', codec, 'crc_received', nxdn.bitsToInt(decoded(infoLength+1:crcEnd)), ...
    'crc_computed', [], 'crc_remainder', remainder, 'crc_ok', remainder == 0, ...
    'tail_bits', tail(:).', 'tail_ok', ~any(tail), ...
    'null_bits', nullBits(:).', 'null_ok', ~any(nullBits), ...
    'sr_bits', decoded(1:8).', 'structure', nxdn.bitsToInt(decoded(1:2)), ...
    'ran', nxdn.bitsToInt(decoded(3:8)), ...
    'layer3_bits', decoded(9:layerEnd).');
block.ok = block.crc_ok && block.tail_ok && block.null_ok;
end
