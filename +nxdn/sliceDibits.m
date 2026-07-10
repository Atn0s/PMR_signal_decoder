function [dibits, levels, error] = sliceDibits(samples)
%SLICEDIBITS Slice normalized 4FSK samples to NXDN dibits.
c = nxdn.constants();
samples = double(samples(:));
distance = abs(samples - c.levels.');
[error, idx] = min(distance, [], 2);
levels = c.levels(idx);
dibits = c.levelDibits(idx);
end
