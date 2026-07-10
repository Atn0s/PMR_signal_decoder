function pdu = parseLayer3(bits, context)
%PARSELAYER3 Parse a CRC-valid NXDN Layer-3 channel payload.
if nargin < 2 || isempty(context)
    context = struct();
end
bits = logical(bits(:).');
if numel(bits) < 8
    pdu = [];
    return;
end
messageType = nxdn.bitsToInt(bits(3:8));
messageName = nxdn.messageTypeName(messageType);
if strcmp(messageName, 'UNKNOWN')
    typeName = 'NXDN_L3_UNKNOWN';
else
    typeName = ['NXDN_' messageName];
end
src = 0;
dst = 0;
extra = struct();
extra.ran = fieldOr(context, 'ran', []);
extra.rf_channel_type = fieldOr(context, 'rf_channel_type', '');
extra.functional_channel = fieldOr(context, 'functional_channel', '');
extra.direction = fieldOr(context, 'direction', '');
extra.lich = fieldOr(context, 'lich', []);
extra.message_type = messageType;
extra.message_name = messageName;
extra.flag1 = bits(1);
extra.flag2 = bits(2);
extra.payload_hex = nxdn.bitsToHex(bits);
extra.crc_ok = true;
extra.fs_start = fieldOr(context, 'fs_start', []);
extra.frame_index = fieldOr(context, 'frame_index', []);
extra.half_index = fieldOr(context, 'half_index', []);
extra.superframe_start = fieldOr(context, 'superframe_start', []);
extra.voice_present = fieldOr(context, 'voice_present', false);
extra.voice_half_mask = fieldOr(context, 'voice_half_mask', [false false]);

if any(messageType == [1 7 8 17]) && numel(bits) >= 64
    extra.cc_option = nxdn.bitsToInt(bits(9:16));
    extra.call_type_code = nxdn.bitsToInt(bits(17:19));
    extra.call_type = nxdn.callTypeName(extra.call_type_code);
    extra.voice_call_option = nxdn.bitsToInt(bits(20:24));
    extra.duplex = bitget(uint8(extra.voice_call_option), 5) ~= 0;
    extra.transmission_mode = bitand(extra.voice_call_option, 7);
    src = nxdn.bitsToInt(bits(25:40));
    dst = nxdn.bitsToInt(bits(41:56));
    extra.cipher_type = nxdn.bitsToInt(bits(57:58));
    extra.key_id = nxdn.bitsToInt(bits(59:64));
    extra.emergency = bitget(uint8(extra.cc_option), 8) ~= 0;
    extra.visitor = bitget(uint8(extra.cc_option), 7) ~= 0;
    extra.priority_paging = bitget(uint8(extra.cc_option), 6) ~= 0;
elseif messageType == 63 && numel(bits) >= 40
    extra.mfid = nxdn.bitsToInt(bits(9:16));
    extra.proprietary_id = nxdn.bitsToInt(bits(17:32));
    if extra.mfid == hex2dec('68') && extra.proprietary_id == hex2dec('8204')
        typeName = 'NXDN_PROP_ALIAS';
        messageName = 'PROP_ALIAS';
        extra.message_name = messageName;
        extra.alias_segment = nxdn.bitsToInt(bits(33:36));
        extra.alias_total = nxdn.bitsToInt(bits(37:40));
        available = floor((numel(bits) - 40) / 8);
        bytes = zeros(1, min(4, available));
        for k = 1:numel(bytes)
            bytes(k) = nxdn.bitsToInt(bits(41+8*(k-1):48+8*(k-1)));
        end
        extra.alias_bytes = bytes;
        printable = bytes(bytes >= 32 & bytes <= 126);
        extra.alias_text = char(printable);
    end
elseif any(messageType == [24 25 26 27]) && numel(bits) >= 32
    extra.location_id = nxdn.bitsToInt(bits(9:32));
end

pdu = struct('protocol', 'NXDN', 'type', typeName, 'src', src, 'dst', dst, ...
    'ts', 0, 'flco', messageName, 'fid', '', 'extra', extra, ...
    'raw_bits', bits);
end

function value = fieldOr(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
