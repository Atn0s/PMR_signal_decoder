function out = blockDeinterleave(bits, rows, depth)
%BLOCKDEINTERLEAVE Reverse the NXDN rectangular bit interleaver.
bits = bits(:);
if numel(bits) ~= rows * depth
    error('nxdn:blockDeinterleave:BadLength', ...
        'Expected %d bits, got %d.', rows * depth, numel(bits));
end
out = false(size(bits));
k = 1;
for row = 0:rows-1
    for column = 0:depth-1
        out(row + rows * column + 1) = bits(k);
        k = k + 1;
    end
end
end
