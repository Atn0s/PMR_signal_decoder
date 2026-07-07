function [info, corrected, valid] = bch6316Decode(bits64)
%BCH6316DECODE P25 NID BCH(63,16)+DUID parity nearest-codeword decoder.
if numel(bits64) ~= 64
    error('p25:bch6316Decode:BadLength', 'NID must be 64 bits.');
end
received = bitsToUint64(bits64);
codewords = p25.bchCodewords();
x = bitxor(codewords, received);
dist = popcountUint64(x);
[bestDist, best] = min(dist);
if bestDist <= 11
    info = intToBits(best - 1, 16);
    corrected = bestDist ~= 0;
    valid = true;
else
    info = bits64(1:16);
    corrected = false;
    valid = false;
end
end

function value = bitsToUint64(bits)
value = uint64(0);
for k = 1:numel(bits)
    value = bitor(bitshift(value, 1), uint64(bits(k) ~= 0));
end
end

function bits = intToBits(value, width)
bits = zeros(1, width);
u = uint64(value);
for k = 1:width
    bits(k) = bitget(u, width - k + 1);
end
end

function counts = popcountUint64(values)
persistent table
if isempty(table)
    table = zeros(256, 1, 'uint8');
    for k = 0:255
        table(k + 1) = uint8(sum(bitget(uint16(k), 1:8)));
    end
end
bytes = typecast(values(:), 'uint8');
bytes = reshape(bytes, 8, []);
counts = double(sum(table(double(bytes) + 1), 1)).';
end

