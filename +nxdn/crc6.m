function value = crc6(bits)
%CRC6 Compute the NXDN SACCH CRC6 value.
s = true(1, 6);
for bit = logical(bits(:).')
    a = xor(bit, s(1));
    s = [xor(a, s(2)), s(3), s(4), xor(a, s(5)), xor(a, s(6)), a];
end
value = nxdn.bitsToInt(s);
end
