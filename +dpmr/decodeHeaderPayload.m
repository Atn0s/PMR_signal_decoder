function decoded = decodeHeaderPayload(payloadSymbols)
%DECODEHEADERPAYLOAD Decode dPMR FS1 header payload symbols.
c = dpmr.constants();
payloadSymbols = payloadSymbols(:).';
cchRecords = struct([]);
cchOffsets = [];
for offset = 0:c.cchSymbols:(numel(payloadSymbols) - c.cchSymbols)
    bits = dpmr.symbolsToBits(payloadSymbols(offset + 1:offset + c.cchSymbols));
    record = dpmr.decodeCch(bits);
    if ~isempty(record) && dpmr.cchUsable(record)
        cchRecords = appendStruct(cchRecords, record);
        cchOffsets(end + 1) = offset; %#ok<AGROW>
    end
end

colorCodes = [];
colorOffsets = [];
for offset = 0:c.ccSymbols:(numel(payloadSymbols) - c.ccSymbols)
    bits = dpmr.symbolsToBits(payloadSymbols(offset + 1:offset + c.ccSymbols));
    colorCode = dpmr.getColorCode(bits);
    if colorCode >= 0
        colorCodes(end + 1) = colorCode; %#ok<AGROW>
        colorOffsets(end + 1) = offset; %#ok<AGROW>
    end
end

if isempty(cchRecords) && isempty(colorCodes)
    decoded = [];
    return;
end

quality = recordsQuality(cchRecords);
[src, dst, superframePart] = assembleIdsFromRecords(onlyCrcOk(cchRecords));
if ~strcmp(quality.confidence, 'high')
    src = '';
    dst = '';
end
payloadBits = dpmr.symbolsToBits(payloadSymbols);
if isempty(colorCodes)
    colorCode = -1;
else
    colorCode = colorCodes(1);
end
decoded = struct( ...
    'cch_records', cchRecords, ...
    'cch_offsets', cchOffsets, ...
    'color_codes', colorCodes, ...
    'color_offsets', colorOffsets, ...
    'payload_bits', payloadBits, ...
    'color_code', colorCode, ...
    'quality', quality, ...
    'src', src, ...
    'dst', dst, ...
    'superframe_part', superframePart, ...
    'raw_bits', payloadBits);
end

function quality = recordsQuality(records)
usableFrames = [];
crcOk = 0;
hammingOk = 0;
for k = 1:numel(records)
    rec = records(k);
    if dpmr.cchUsable(rec)
        usableFrames(end + 1) = rec.frame_number; %#ok<AGROW>
    end
    crcOk = crcOk + double(rec.crc_ok);
    hammingOk = hammingOk + double(rec.hamming_ok);
end
validPair = all(ismember([0 1], usableFrames)) || all(ismember([2 3], usableFrames));
if crcOk > 0
    confidence = 'high';
elseif validPair
    confidence = 'medium';
elseif hammingOk > 0
    confidence = 'low';
else
    confidence = 'none';
end
quality = struct('crc_ok_count', crcOk, 'hamming_ok_count', hammingOk, ...
    'valid_frame_pair', validPair, 'confidence', confidence, ...
    'front_end_confidence', confidence);
end

function out = onlyCrcOk(records)
out = struct([]);
for k = 1:numel(records)
    if logical(records(k).crc_ok)
        out = appendStruct(out, records(k));
    end
end
end

function [src, dst, part] = assembleIdsFromRecords(records)
session = dpmr.sessionInit();
src = '';
dst = '';
part = 'unknown';
for idx = 1:2:numel(records)
    a = records(idx);
    if idx + 1 <= numel(records)
        b = records(idx + 1);
    else
        b = [];
    end
    [session, src, dst, part] = dpmr.sessionFeed(session, a, b);
end
end

function out = appendStruct(arr, item)
if isempty(item)
    out = arr;
elseif isempty(arr)
    out = item;
else
    out = arr;
    out(end + 1) = item;
end
end
