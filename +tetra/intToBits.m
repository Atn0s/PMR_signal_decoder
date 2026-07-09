function bits = intToBits(value, width)
%INTTOBITS Convert a non-negative integer to big-endian bits.
if nargin < 2 || isempty(width)
    width = 1;
end
if ~isscalar(value) || value < 0 || value ~= floor(value)
    error('tetra:intToBits:BadValue', ...
        'intToBits expects a non-negative scalar integer.');
end
if width < 1 || width ~= floor(width)
    error('tetra:intToBits:BadWidth', ...
        'intToBits expects a positive integer width.');
end
if value >= 2 ^ width
    error('tetra:intToBits:Overflow', ...
        'Value %g does not fit in %d bits.', value, width);
end
bits = bitget(uint32(value), width:-1:1).' ~= 0;
end
