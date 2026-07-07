function [data, corrected] = hamming106Decode(bits10)
%HAMMING106DECODE Exhaustive Hamming(10,6,3) decoder.
if numel(bits10) ~= 10
    error('p25:hamming106Decode:BadLength', 'Hamming codeword must be 10 bits.');
end
rx = double(bits10(:).') ~= 0;
bestDist = 11;
bestData = rx(1:6);
for val = 0:63
    trial = bitget(uint8(val), 6:-1:1) ~= 0;
    codeword = [trial, hammingParity(trial)];
    dist = sum(xor(rx, codeword));
    if dist < bestDist
        bestDist = dist;
        bestData = trial;
    end
end
corrected = bestDist == 1;
if bestDist <= 1
    data = double(bestData);
else
    data = double(rx(1:6));
end
end

function parity = hammingParity(d)
parity = [
    xor(xor(d(1), d(2)), xor(d(3), d(6))), ...
    xor(xor(d(1), d(2)), xor(d(4), d(6))), ...
    xor(xor(d(1), d(3)), xor(d(4), d(5))), ...
    xor(xor(d(2), d(3)), xor(d(4), d(5))) ...
];
end

