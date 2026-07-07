function es = decodeLdu2Es(frameBits)
%DECODELDU2ES Decode P25 LDU2 encryption sync.
groups = p25.deinterleaveEs(frameBits);
hexbits = zeros(1, 24);
corrected = 0;
for k = 1:24
    [data, fixed] = p25.hamming106Decode(groups(k, :));
    hexbits(k) = p25.bitsToInt(data);
    corrected = corrected + double(fixed);
end
[decoded, ok] = p25.rsDecode(hexbits, '24_16_9');
if ~ok
    es = [];
    return;
end
bits = [];
for k = numel(decoded):-1:1
    bits = [bits, bitget(uint8(decoded(k)), 6:-1:1)]; %#ok<AGROW>
end
if numel(bits) < 96
    es = [];
    return;
end
es = struct( ...
    'mi', p25.bitsToInt(bits(1:72)), ...
    'algid', p25.bitsToInt(bits(73:80)), ...
    'kid', p25.bitsToInt(bits(81:96)), ...
    'rs_ok', true, ...
    'hamming_corrected', corrected, ...
    'raw', bits(1:96));
end
