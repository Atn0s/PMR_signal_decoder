function out = descrambleDibits(dibits, seed)
%DESCRAMBLEDIBITS Apply the symmetric NXDN PN9 dibit scrambler.
if nargin < 2
    seed = [];
end
out = uint8(dibits(:));
pn = nxdn.pn9Sequence(numel(out), seed);
out(pn) = bitxor(out(pn), uint8(2));
out = bitand(out, uint8(3));
end
