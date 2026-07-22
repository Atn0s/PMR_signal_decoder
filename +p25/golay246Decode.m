function [value, corrected] = golay246Decode(data6, parity12)
%GOLAY246DECODE Golay(24,6) shortened decoder by nearest codeword search.
if numel(data6) ~= 6 || numel(parity12) ~= 12
    error('p25:golay246Decode:BadLength', 'Golay(24,6) needs 6 data and 12 parity bits.');
end
rxData = p25.bitsToInt(data6);
rx = golayWord(rxData, parity12);
bestDist = 25;
bestData = rxData;
for data = 0:63
    cw = golayWord(data, golay246Encode(data));
    dist = bitCount(bitxor(uint32(rx), uint32(cw)));
    if dist < bestDist
        bestDist = dist;
        bestData = data;
    end
end
if bestDist <= 3
    value = bestData;
    corrected = bestDist ~= 0;
else
    value = rxData;
    corrected = false;
end
end

function parity = golay246Encode(data6)
poly = uint32(hex2dec('AE3'));
data12 = bitshift(uint32(bitand(data6, 63)), 6);
cw = data12;
tmp = cw;
for k = 1:12
    if bitand(tmp, 1)
        tmp = bitxor(tmp, poly);
    end
    tmp = bitshift(tmp, -1);
end
codeword = bitor(bitshift(tmp, 12), cw);
if mod(bitCount(codeword), 2) == 1
    codeword = bitxor(codeword, uint32(hex2dec('800000')));
end
parity = zeros(1, 12);
for idx = 1:12
    bitPos = idx + 11; % Positions 12:23, emitted MSB-first over that slice.
    parity(idx) = bitget(codeword, bitPos + 1);
end
end

function word = golayWord(data6, parity12)
word = uint32(0);
for i = 12:-1:1
    word = bitor(bitshift(word, 1), uint32(parity12(i) ~= 0));
end
word = bitor(bitshift(word, 6), uint32(bitand(data6, 63)));
word = bitshift(word, 6);
end

function n = bitCount(x)
n = 0;
while x ~= 0
    n = n + double(bitand(x, 1));
    x = bitshift(x, -1);
end
end
