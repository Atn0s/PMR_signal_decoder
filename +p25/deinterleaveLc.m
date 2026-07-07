function groups = deinterleaveLc(frameBits)
%DEINTERLEAVELC Return 24 Hamming groups for LDU1 LC.
c = p25.constants();
picked = frameBits(c.lcHexbitPositions);
groups = reshape(picked, 10, 24).';
end

