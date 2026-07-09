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
        pdu = decodeLc(bits, info, colorCode, dataType, 'VOICE_LC_HEADER', 'LC_HEADER');
    case 2
        pdu = decodeLc(bits, info, colorCode, dataType, 'TERMINATOR_WITH_LC', 'TERMINATOR');
    case 3
        pdu = decodeCsbk(bits, info, colorCode, dataType, 'CSBK');
    otherwise
        pdu = [];
end
end

function pdu = decodeLc(rawBits, info, colorCode, dataType, dataTypeName, pduType)
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
extra = struct();
extra.color_code = colorCode;
extra.data_type = dataType;
extra.data_type_name = dataTypeName;
extra.fec = struct('golay_ok', true, 'bptc_196_96_ok', true, 'rs_12_9_4_ok', true);
extra.flc = struct( ...
    'flco_value', flc.flco, ...
    'fid_value', flc.fid, ...
    'call_type', callTypeFromFlco(flc.flco));
pdu = struct( ...
    'protocol', 'DMR', ...
    'type', pduType, ...
    'src', flc.src, ...
    'dst', flc.dst, ...
    'ts', 0, ...
    'flco', flc.flco_name, ...
    'fid', flc.fid_name, ...
    'extra', extra, ...
    'raw_bits', rawBits);
end

function pdu = decodeCsbk(rawBits, info, colorCode, dataType, dataTypeName)
decoded = dmr.bptc196DataBits(info);
csbko = dmr.bitsToInt(decoded(3:8));
fid = dmr.bitsToInt(decoded(9:16));
extra = struct();
extra.color_code = colorCode;
extra.data_type = dataType;
extra.data_type_name = dataTypeName;
extra.last_block = logical(decoded(1));
extra.csbk = struct('last_block', logical(decoded(1)), ...
    'protect_flag', logical(decoded(2)), ...
    'csbko_value', csbko, ...
    'fid_value', fid);
extra.fec = struct('golay_ok', true, 'bptc_196_96_ok', true);
pdu = struct( ...
    'protocol', 'DMR', ...
    'type', 'CSBK', ...
    'src', 0, ...
    'dst', 0, ...
    'ts', 0, ...
    'flco', sprintf('CSBKO_0x%02X', csbko), ...
    'fid', dmr.fidName(fid), ...
    'extra', extra, ...
    'raw_bits', rawBits);
end

function text = callTypeFromFlco(flco)
switch flco
    case 0
        text = 'group';
    case 3
        text = 'unit_to_unit';
    otherwise
        text = 'unknown';
end
end
