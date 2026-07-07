function bits = sliceSymbolsToBits(symbols)
%SLICESYMBOLSTOBITS Convert nominal P25 symbols to dibit bits.
levels = [-3; -1; 1; 3];
pairs = [1 1; 1 0; 0 0; 0 1]; % rows match levels -3,-1,+1,+3
[~, idx] = min(abs(symbols(:) - levels.'), [], 2);
bits = reshape(pairs(idx, :).', [], 1).';
end

