function pdu = decodeBurst(symbols, syncType)
%DECODEBURST Decode one DMR data-sync burst.
bits = dmr.adaptiveSliceBits(symbols);
slotBits = [bits(99:108), bits(157:166)];
if ~dmr.golay2087Check(slotBits)
    pdu = [];
    return;
end
colorCode = dmr.bitsToInt(slotBits(1:4));
dataType = dmr.bitsToInt(slotBits(5:8));
info = [bits(1:98), bits(167:264)];

switch dataType
    case 1
        pdu = decodeLc(bits, info, colorCode, 'LC_HEADER');
    case 2
        pdu = decodeLc(bits, info, colorCode, 'TERMINATOR');
    case 3
        pdu = decodeCsbk(bits, info, colorCode);
    otherwise
        pdu = [];
end
end

function pdu = decodeLc(rawBits, info, colorCode, pduType)
decoded = dmr.bptc196DataBits(info);
if ~dmr.rs1294Check(decoded)
    pdu = [];
    return;
end
flc = dmr.parseFullLinkControl(decoded);
if isempty(flc)
    pdu = [];
    return;
end
pdu = struct( ...
    'protocol', 'DMR', ...
    'type', pduType, ...
    'src', flc.src, ...
    'dst', flc.dst, ...
    'ts', 0, ...
    'flco', flc.flco_name, ...
    'fid', flc.fid_name, ...
    'extra', struct('color_code', colorCode), ...
    'raw_bits', rawBits);
end

function pdu = decodeCsbk(rawBits, info, colorCode)
decoded = dmr.bptc196DataBits(info);
csbko = dmr.bitsToInt(decoded(3:8));
fid = dmr.bitsToInt(decoded(9:16));
pdu = struct( ...
    'protocol', 'DMR', ...
    'type', 'CSBK', ...
    'src', 0, ...
    'dst', 0, ...
    'ts', 0, ...
    'flco', sprintf('CSBKO_0x%02X', csbko), ...
    'fid', dmr.fidName(fid), ...
    'extra', struct('color_code', colorCode, 'last_block', logical(decoded(1))), ...
    'raw_bits', rawBits);
end
