function bits = pn9Sequence(count, seed)
%PN9SEQUENCE Generate the NXDN per-frame PN9 sequence.
if nargin < 2 || isempty(seed)
    seed = nxdn.constants().pn9Seed;
end
lfsr = uint16(seed);
bits = false(count, 1);
for k = 1:count
    bits(k) = bitand(lfsr, uint16(1)) ~= 0;
    feedback = bitxor(bitget(lfsr, 5), bitget(lfsr, 1));
    lfsr = bitshift(lfsr, -1);
    if feedback
        lfsr = bitor(lfsr, bitshift(uint16(1), 8));
    end
end
end
