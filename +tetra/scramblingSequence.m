function p = scramblingSequence(n, colourCodeBits)
%SCRAMBLINGSEQUENCE Generate the TETRA DMO scrambling sequence p(k).
%
% For SCH/S and SCH/H in a DSB, EN 300 396-2 sets all 30 colour-code bits
% to zero. Pass no colourCodeBits, or pass zeros(30,1), for that case.
if nargin < 2 || isempty(colourCodeBits)
    colourCodeBits = false(30, 1);
end
colourCodeBits = colourCodeBits(:) ~= 0;
if numel(colourCodeBits) ~= 30
    error('tetra:scramblingSequence:BadColourCode', ...
        'DMO scrambling needs exactly 30 colour-code bits.');
end

if n < 0
    error('tetra:scramblingSequence:BadLength', ...
        'Scrambling sequence length must be non-negative.');
end

offset = 32;
state = false(n + offset, 1);
state((-31) + offset) = true;
state((-30) + offset) = true;
for k = -29:0
    state(k + offset) = colourCodeBits(1 - k);
end

taps = [1 2 4 5 7 8 10 11 12 16 22 23 26 32];
for k = 1:n
    bit = false;
    for m = 1:numel(taps)
        bit = xor(bit, state(k - taps(m) + offset));
    end
    state(k + offset) = bit;
end

p = state((1:n) + offset);
end
