function ok = rs1294Check(bits96)
%RS1294CHECK Verify DMR Reed-Solomon(12,9,4) checksum with VLC mask.
if numel(bits96) ~= 96
    ok = false;
    return;
end
data = bitsToBytes(bits96);
generated = generate(data(1:9), [hex2dec('96'), hex2dec('96'), hex2dec('96')]);
ok = isequal(generated, data);
end

function out = generate(data9, mask)
parity = [0, 0, 0];
poly = [64, 56, 14];
for k = 1:numel(data9)
    single = bitxor(data9(k), parity(3));
    parity(3) = bitxor(parity(2), logMultiply(poly(3), single));
    parity(2) = bitxor(parity(1), logMultiply(poly(2), single));
    parity(1) = logMultiply(poly(1), single);
end
out = [data9(:).', bitxor(parity(3:-1:1), mask)];
end

function value = logMultiply(a, b)
persistent expTable logTable
if isempty(expTable)
    expTable = zeros(1, 512);
    logTable = zeros(1, 256);
    x = 1;
    for i = 0:254
        expTable(i + 1) = x;
        logTable(x + 1) = i;
        x = bitshift(x, 1);
        if bitand(x, 256)
            x = bitxor(x, hex2dec('11D'));
        end
        x = bitand(x, 255);
    end
    for i = 255:511
        expTable(i + 1) = expTable(i - 255 + 1);
    end
end
if a == 0 || b == 0
    value = 0;
else
    value = expTable(logTable(a + 1) + logTable(b + 1) + 1);
end
end

function bytes = bitsToBytes(bits)
bytes = zeros(1, 12);
for k = 1:12
    bytes(k) = dmr.bitsToInt(bits((k-1)*8+1:k*8));
end
end

