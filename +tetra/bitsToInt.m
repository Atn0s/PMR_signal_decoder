function value = bitsToInt(bits)
%BITSTOINT Convert big-endian bits to a double integer.
value = 0;
bits = bits(:).';
for k = 1:numel(bits)
    value = value * 2 + double(bits(k) ~= 0);
end
end
