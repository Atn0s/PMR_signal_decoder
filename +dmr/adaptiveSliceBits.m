function bits = adaptiveSliceBits(seg)
%ADAPTIVESLICEBITS Slice DMR 4FSK levels to dibit bits.
hi = prctile(seg, 90);
lo = prctile(seg, 10);
if hi == lo
    bits = repmat([0 0], 1, numel(seg));
    return;
end
center = 0.5 * (hi + lo);
umid = 0.5 * (hi + center);
lmid = 0.5 * (lo + center);
bits = zeros(1, numel(seg) * 2);
out = 1;
for k = 1:numel(seg)
    v = seg(k);
    if v >= umid
        pair = [0 1];
    elseif v >= center
        pair = [0 0];
    elseif v >= lmid
        pair = [1 0];
    else
        pair = [1 1];
    end
    bits(out:out+1) = pair;
    out = out + 2;
end
end

