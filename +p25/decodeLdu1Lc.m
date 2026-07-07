function lc = decodeLdu1Lc(frameBits)
%DECODELDU1LC Decode P25 LDU1 link control.
groups = p25.deinterleaveLc(frameBits);
hexbits = zeros(1, 24);
for k = 1:24
    data = p25.hamming106Decode(groups(k, :));
    hexbits(k) = p25.bitsToInt(data);
end
[decoded, ok] = p25.rsDecode(hexbits, '24_12_13');
if ~ok
    lc = [];
    return;
end
lc72 = [];
for k = numel(decoded):-1:1
    lc72 = [lc72, bitget(uint8(decoded(k)), 6:-1:1)]; %#ok<AGROW>
end
lc = p25.parseLinkControl(lc72);
end
