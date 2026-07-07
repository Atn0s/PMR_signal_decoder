function record = decodeCch(rawBits)
%DECODECCH Decode one 72-bit dPMR CCH block.
if numel(rawBits) ~= 72
    record = [];
    return;
end
descrambled = descramble(rawBits);
deinterleaved = deinterleave6x12(descrambled);
data = [];
blockOk = false(1, 6);
corrected = 0;
for idx = 1:6
    [decoded, ok, corr] = hamming128Decode(deinterleaved((idx-1)*12+1:idx*12));
    data = [data, decoded]; %#ok<AGROW>
    blockOk(idx) = ok;
    corrected = corrected + corr;
end
gotCrc = dpmr.bitsToInt(data(42:48));
computedCrc = crc7(data(1:41));
record = struct( ...
    'frame_number', dpmr.bitsToInt(data(1:2)), ...
    'id_half', dpmr.bitsToInt(data(3:14)), ...
    'communication_mode', dpmr.bitsToInt(data(15:17)), ...
    'version', dpmr.bitsToInt(data(18:19)), ...
    'comms_format', dpmr.bitsToInt(data(20:21)), ...
    'emergency_priority', data(22), ...
    'reserved', data(23), ...
    'slow_data', dpmr.bitsToInt(data(24:41)), ...
    'crc_value', gotCrc, ...
    'crc_computed', computedCrc, ...
    'crc_ok', gotCrc == computedCrc, ...
    'hamming_ok', all(blockOk), ...
    'hamming_blocks_ok', blockOk, ...
    'corrected_bits', corrected, ...
    'bits', data);
end

function out = descramble(bits)
s = bitget(uint16(hex2dec('1FF')), 1:9);
out = zeros(1, numel(bits));
for k = 1:numel(bits)
    out(k) = bitxor(double(bits(k) ~= 0), s(1));
    temp = bitxor(s(5), s(1));
    s = [s(2:9), temp];
end
end

function out = deinterleave6x12(bits)
matrix = reshape(bits, 6, 12).';
out = [];
for col = 1:6
    for row = 1:12
        out(end + 1) = matrix(row, col); %#ok<AGROW>
    end
end
end

function [data, ok, corrected] = hamming128Decode(codeword)
h = [
    1 0 1 0 1 1 0 0 1 0 0 0;
    1 1 0 1 0 1 1 0 0 1 0 0;
    1 1 1 0 1 0 1 1 0 0 1 0;
    0 1 0 1 1 0 0 1 0 0 0 1];
corrMap = containers.Map( ...
    {14, 7, 10, 5, 11, 12, 6, 3, 8, 4, 2, 1}, ...
    {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12});
bits = double(codeword(:).' ~= 0);
syndrome = 0;
for row = 1:4
    total = mod(sum(bits .* h(row, :)), 2);
    syndrome = bitor(syndrome, bitshift(total, 4 - row));
end
corrected = 0;
ok = true;
if syndrome ~= 0
    if isKey(corrMap, syndrome)
        pos = corrMap(syndrome);
        bits(pos) = 1 - bits(pos);
        corrected = 1;
    else
        ok = false;
    end
end
data = bits(1:8);
end

function value = crc7(bits)
reg = 0;
poly = 9;
for k = 1:numel(bits)
    if bitxor(bitget(uint8(reg), 7), double(bits(k) ~= 0))
        reg = bitand(bitxor(bitshift(reg, 1), poly), 127);
    else
        reg = bitand(bitshift(reg, 1), 127);
    end
end
value = reg;
end

