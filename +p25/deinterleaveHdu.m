function [dataGroups, parityGroups] = deinterleaveHdu(frameBits)
%DEINTERLEAVEHDU Return HDU Golay data/parity groups.
c = p25.constants();
data = frameBits(c.hduDataHexbitPositions);
parity = frameBits(c.hduGolayParityPositions);
dataGroups = reshape(data, 6, 36).';
parityGroups = reshape(parity, 12, 36).';
end

