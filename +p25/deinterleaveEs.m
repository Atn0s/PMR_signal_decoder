function groups = deinterleaveEs(frameBits)
%DEINTERLEAVEES Return 24 Hamming groups for LDU2 encryption sync.
c = p25.constants();
picked = frameBits(c.esHexbitPositions);
groups = reshape(picked, 10, 24).';
end

