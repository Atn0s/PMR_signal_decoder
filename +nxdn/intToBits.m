function bits = intToBits(value, width)
%INTTOBITS Convert an integer to an MSB-first logical vector.
bits = false(width, 1);
value = uint64(value);
for k = 1:width
    bits(k) = bitget(value, width - k + 1) ~= 0;
end
end
