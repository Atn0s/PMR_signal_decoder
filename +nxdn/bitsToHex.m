function text = bitsToHex(bits)
%BITSTOHEX Format MSB-first bits as hexadecimal, padding the last nibble.
bits = bits(:).';
pad = mod(-numel(bits), 4);
bits = [bits false(1, pad)];
digits = repmat('0', 1, numel(bits) / 4);
alphabet = '0123456789ABCDEF';
for k = 1:numel(digits)
    digits(k) = alphabet(nxdn.bitsToInt(bits(4*k-3:4*k)) + 1);
end
text = digits;
end
