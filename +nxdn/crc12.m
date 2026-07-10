function value = crc12(bits)
%CRC12 Compute the NXDN FACCH1 CRC12 value.
s = true(1, 12);
for bit = logical(bits(:).')
    a = xor(bit, s(1));
    s = [xor(a, s(2)), s(3), s(4), s(5), s(6), s(7), s(8), s(9), ...
        xor(a, s(10)), xor(a, s(11)), xor(a, s(12)), a];
end
value = nxdn.bitsToInt(s);
end
