function bits = symbolsToBits(symbols)
%SYMBOLSTOBITS Convert dPMR dibit symbols to bit vector.
pairs = [0 0; 0 1; 1 0; 1 1];
symbols = bitand(uint8(symbols(:)), 3);
bits = reshape(pairs(double(symbols) + 1, :).', [], 1).';
end

