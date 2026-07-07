function codewords = bchCodewords()
%BCHCODEWORDS Return all P25 BCH NID codewords as uint64 values.
persistent cache
if ~isempty(cache)
    codewords = cache;
    return;
end

[transform, pivotRows, h] = paritySolver();
codewords = zeros(65536, 1, 'uint64');
for value = 0:65535
    data = intToBits(value, 16);
    rhs = mod(double(h(:, 1:16)) * data(:), 2);
    reduced = mod(double(transform) * rhs, 2);
    parityBits = reduced(pivotRows);
    bits = [data(:).', parityBits(:).', duidParity(data)];
    codewords(value + 1) = bitsToUint64(bits);
end
cache = codewords;
end

function [transform, pivotRows, h] = paritySolver()
h = syndromeMatrix();
a = h(:, 17:63);
[rows, cols] = size(a);
transform = eye(rows, 'uint8');
pivotRows = zeros(cols, 1);
r = 1;
for c = 1:cols
    rel = find(a(r:end, c), 1, 'first');
    if isempty(rel)
        continue;
    end
    p = rel + r - 1;
    if p ~= r
        a([r p], :) = a([p r], :);
        transform([r p], :) = transform([p r], :);
    end
    for rr = 1:rows
        if rr ~= r && a(rr, c)
            a(rr, :) = bitxor(a(rr, :), a(r, :));
            transform(rr, :) = bitxor(transform(rr, :), transform(r, :));
        end
    end
    pivotRows(r) = r;
    r = r + 1;
    if r > cols
        break;
    end
end
if r <= cols
    error('p25:bchCodewords:RankDeficient', 'P25 BCH parity matrix is rank deficient.');
end
pivotRows = pivotRows(1:cols);
end

function h = syndromeMatrix()
gfExp = uint8([ ...
    1, 2, 4, 8, 16, 32, 3, 6, 12, 24, 48, 35, 5, 10, 20, 40, ...
    19, 38, 15, 30, 60, 59, 53, 41, 17, 34, 7, 14, 28, 56, 51, 37, ...
    9, 18, 36, 11, 22, 44, 27, 54, 47, 29, 58, 55, 45, 25, 50, 39, ...
    13, 26, 52, 43, 21, 42, 23, 46, 31, 62, 63, 61, 57, 49, 33]);
h = zeros(22 * 6, 63, 'uint8');
for airPos = 0:62
    op25Pos = 62 - airPos;
    for syn = 1:22
        value = gfExp(mod(syn * op25Pos, 63) + 1);
        for bit = 0:5
            h((syn - 1) * 6 + bit + 1, airPos + 1) = bitget(value, bit + 1);
        end
    end
end
end

function parity = duidParity(info16)
d0 = info16(13) * 2 + info16(14);
d1 = info16(15) * 2 + info16(16);
parity = double((d0 == 1 && d1 == 1) || (d0 == 2 && d1 == 2));
end

function bits = intToBits(value, width)
bits = zeros(1, width);
u = uint64(value);
for k = 1:width
    bits(k) = bitget(u, width - k + 1);
end
end

function value = bitsToUint64(bits)
value = uint64(0);
for k = 1:numel(bits)
    value = bitor(bitshift(value, 1), uint64(bits(k) ~= 0));
end
end

