function ok = golay2087Check(bits20)
%GOLAY2087CHECK Exact DMR Golay(20,8,7) codeword check.
if numel(bits20) ~= 20
    ok = false;
    return;
end
persistent codewords
if isempty(codewords)
    g = [
        1 0 0 0 0 0 0 0 0 0 1 1 1 1 0 1 1 0 1 0;
        0 1 0 0 0 0 0 0 1 1 0 1 1 0 0 1 1 0 0 1;
        0 0 1 0 0 0 0 0 0 1 1 0 1 1 0 0 1 1 0 1;
        0 0 0 1 0 0 0 0 0 0 1 1 0 1 1 0 0 1 1 1;
        0 0 0 0 1 0 0 0 1 1 0 1 1 1 0 0 0 1 1 0;
        0 0 0 0 0 1 0 0 1 0 1 0 1 0 0 1 0 1 1 1;
        0 0 0 0 0 0 1 0 1 0 0 1 0 0 1 1 1 1 1 0;
        0 0 0 0 0 0 0 1 1 0 0 0 1 1 1 0 1 0 1 1];
    codewords = false(256, 20);
    for value = 0:255
        data = double(bitget(uint16(value), 8:-1:1));
        codewords(value + 1, :) = mod(data * g, 2) ~= 0;
    end
end
bits = logical(bits20(:).');
ok = any(all(codewords == bits, 2));
end
