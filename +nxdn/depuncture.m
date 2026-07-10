function coded = depuncture(bits, pattern, outputLength)
%DEPUNCTURE Insert NaN erasures into a punctured convolutional stream.
bits = double(bits(:) ~= 0);
pattern = logical(pattern(:));
coded = nan(outputLength, 1);
source = 1;
for k = 1:outputLength
    if pattern(mod(k - 1, numel(pattern)) + 1)
        if source > numel(bits)
            error('nxdn:depuncture:TooShort', 'Punctured input ended early.');
        end
        coded(k) = bits(source);
        source = source + 1;
    end
end
if source - 1 ~= numel(bits)
    error('nxdn:depuncture:UnusedBits', 'Not all punctured bits were consumed.');
end
end
