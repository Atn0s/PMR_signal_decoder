function value = crc15(bits)
%CRC15 Compute the NXDN UDCH/FACCH2 CRC15 value.
s = true(1, 15);
for bit = logical(bits(:).')
    a = xor(bit, s(1));
    s = [xor(a, s(2)), s(3), s(4), xor(a, s(5)), xor(a, s(6)), ...
        s(7), s(8), xor(a, s(9)), xor(a, s(10)), s(11), s(12), ...
        s(13), xor(a, s(14)), s(15), a];
end
value = nxdn.bitsToInt(s);
end
