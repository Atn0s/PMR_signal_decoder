function hcw = decodeHduHcw(frameBits)
%DECODEHDUHCW Decode P25 HDU header codeword.
[dataGroups, parityGroups] = p25.deinterleaveHdu(frameBits);
symbols = zeros(1, 36);
corrected = 0;
for k = 1:36
    [value, fixed] = p25.golay246Decode(dataGroups(k, :), parityGroups(k, :));
    symbols(k) = value;
    corrected = corrected + double(fixed);
end
[decoded, ok] = p25.rsDecode(symbols, '36_20_17');
if ~ok
    hcw = [];
    return;
end
bits = [];
for k = numel(decoded):-1:1
    bits = [bits, bitget(uint8(decoded(k)), 6:-1:1)]; %#ok<AGROW>
end
if numel(bits) < 120
    hcw = [];
    return;
end
hcw = struct( ...
    'mi', p25.bitsToInt(bits(1:72)), ...
    'mfid', p25.bitsToInt(bits(73:80)), ...
    'algid', p25.bitsToInt(bits(81:88)), ...
    'kid', p25.bitsToInt(bits(89:104)), ...
    'tgid', p25.bitsToInt(bits(105:120)), ...
    'rs_ok', true, ...
    'golay_corrected', corrected, ...
    'raw', bits(1:120));
end
