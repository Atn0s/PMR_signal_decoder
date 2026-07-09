function dcc = dmoDcc(mni, sourceAddress)
%DMODCC Build the 30-bit DMO colour code from MNI and source address.
mniBits = toBits(mni, 24, 'MNI');
sourceBits = toBits(sourceAddress, 24, 'source address');
dcc = [mniBits(19:24); sourceBits(:)];
end

function bits = toBits(value, width, label)
if isnumeric(value) && isscalar(value)
    bits = tetra.intToBits(double(value), width);
    return;
end
bits = value(:) ~= 0;
if numel(bits) ~= width
    error('tetra:dmoDcc:BadLength', ...
        '%s must be either an integer or exactly %d bits.', label, width);
end
end
