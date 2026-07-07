function value = bitsToInt(bits)
%BITSTOINT Convert big-endian bit vector to double integer.
bits = bits(:).';
value = 0;
for k = 1:numel(bits)
    value = value * 2 + double(bits(k) ~= 0);
end
end

