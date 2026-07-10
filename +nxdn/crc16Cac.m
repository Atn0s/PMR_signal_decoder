function value = crc16Cac(bits)
%CRC16CAC Return the NXDN CAC CRC16 remainder (zero means valid block).
crc = uint32(hex2dec('C3EE'));
poly = uint32(hex2dec('1021'));
for bit = logical(bits(:).')
    crc = bitand(bitor(bitshift(crc, 1), uint32(bit)), uint32(hex2dec('1FFFF')));
    if bitand(crc, uint32(hex2dec('10000'))) ~= 0
        crc = bitxor(bitand(crc, uint32(65535)), poly);
    end
end
crc = bitxor(crc, uint32(65535));
value = double(bitand(crc, uint32(65535)));
end
