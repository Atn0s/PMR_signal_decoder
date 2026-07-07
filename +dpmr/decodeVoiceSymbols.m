function decoded = decodeVoiceSymbols(symbols)
%DECODEVOICESYMBOLS Decode one recovered FS2 voice symbol candidate.
c = dpmr.constants();
offset = numel(c.fs2Symbols);
cch0Bits = dpmr.symbolsToBits(symbols(offset+1:offset+c.cchSymbols));
offset = offset + c.cchSymbols + c.tchSymbols;
ccBits = dpmr.symbolsToBits(symbols(offset+1:offset+c.ccSymbols));
offset = offset + c.ccSymbols;
cch1Bits = dpmr.symbolsToBits(symbols(offset+1:offset+c.cchSymbols));
cch0 = dpmr.decodeCch(cch0Bits);
cch1 = dpmr.decodeCch(cch1Bits);
colorCode = dpmr.getColorCode(ccBits);
if ~voiceUsable(cch0, cch1, colorCode)
    decoded = [];
    return;
end
decoded = struct('cch0_bits', cch0Bits, 'cc_bits', ccBits, 'cch1_bits', cch1Bits, ...
    'cch0', cch0, 'cch1', cch1, 'color_code', colorCode, ...
    'quality', voiceQuality(cch0, cch1), 'raw_bits', ccBits);
end

function tf = voiceUsable(cch0, cch1, colorCode)
records = {};
if ~isempty(cch0), records{end + 1} = cch0; end %#ok<AGROW>
if ~isempty(cch1), records{end + 1} = cch1; end %#ok<AGROW>
if colorCode < 0 || isempty(records)
    tf = false;
    return;
end
tf = any(cellfun(@(r) r.crc_ok || r.hamming_ok, records));
end

function quality = voiceQuality(cch0, cch1)
records = {};
if ~isempty(cch0), records{end + 1} = cch0; end %#ok<AGROW>
if ~isempty(cch1), records{end + 1} = cch1; end %#ok<AGROW>
frames = [];
crcOk = 0;
hammingOk = 0;
for k = 1:numel(records)
    rec = records{k};
    if dpmr.cchUsable(rec), frames(end + 1) = rec.frame_number; end %#ok<AGROW>
    crcOk = crcOk + double(rec.crc_ok);
    hammingOk = hammingOk + double(rec.hamming_ok);
end
validPair = all(ismember([0 1], frames)) || all(ismember([2 3], frames));
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
    'valid_frame_pair', validPair, 'confidence', confidence);
end

