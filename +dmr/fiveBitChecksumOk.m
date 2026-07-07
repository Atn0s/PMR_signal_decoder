function ok = fiveBitChecksumOk(bits72, rxCs5)
%FIVEBITCHECKSUMOK Verify DMR 5-bit checksum over 72 LC bits.
bytes = bitsToBytes(bits72);
if numel(bytes) < 9
    bytes = [zeros(1, 9 - numel(bytes)), bytes];
end
cs = mod(sum(bytes(end:-1:1)), 31);
ok = rxCs5 >= 0 && rxCs5 <= 30 && cs == rxCs5;
end

function bytes = bitsToBytes(bits)
n = ceil(numel(bits) / 8);
bytes = zeros(1, n);
for k = 1:n
    chunk = bits((k-1)*8+1:min(k*8, numel(bits)));
    if numel(chunk) < 8
        chunk = [chunk, zeros(1, 8 - numel(chunk))];
    end
    bytes(k) = dmr.bitsToInt(chunk);
end
end

