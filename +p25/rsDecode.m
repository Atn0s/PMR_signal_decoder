function [decoded, ok] = rsDecode(hexbits, mode)
%RSDECODE Decode shortened P25 RS codewords over GF(2^6).
switch mode
    case '24_12_13'
        if numel(hexbits) ~= 24, error('p25:rsDecode:BadLength', 'RS(24,12) needs 24 symbols.'); end
        dataLen = 12; nroots = 12; t = 6; outRange = 13:24;
    case '36_20_17'
        if numel(hexbits) ~= 36, error('p25:rsDecode:BadLength', 'RS(36,20) needs 36 symbols.'); end
        dataLen = 20; nroots = 16; t = 8; outRange = 17:36;
    case '24_16_9'
        if numel(hexbits) ~= 24, error('p25:rsDecode:BadLength', 'RS(24,16) needs 24 symbols.'); end
        dataLen = 16; nroots = 8; t = 4; outRange = 9:24;
    otherwise
        error('p25:rsDecode:UnsupportedMode', 'Unsupported RS mode: %s', mode);
end
data = hexbits(1:dataLen);
parity = hexbits(dataLen+1:end);
recd = [parity(:).', data(:).', zeros(1, 63 - numel(hexbits))];
[recd, ok] = rs63DecodeInPlace(recd, nroots, t);
if ok
    decoded = recd(outRange);
else
    decoded = [];
end
end

function [recdPoly, ok] = rs63DecodeInPlace(recdPoly, nroots, t)
[gfExp, gfLog] = gf6Tables();
recd = arrayfun(@idx, recdPoly);
s = zeros(1, nroots);
synError = false;
for i = 1:nroots
    accum = 0;
    for j = 0:62
        if recd(j + 1) ~= -1
            accum = bitxor(accum, gfExp(mod(recd(j + 1) + i * j, 63) + 1));
        end
    end
    if accum ~= 0
        synError = true;
    end
    s(i) = idx(accum);
end
if ~synError
    ok = true;
    return;
end

elp = zeros(nroots + 2, nroots);
d = zeros(1, nroots + 2);
l = zeros(1, nroots + 2);
uLu = zeros(1, nroots + 2);
d(1) = 0;
d(2) = s(1);
elp(1, 1) = 0;
elp(2, 1) = 1;
for i = 1:nroots-1
    elp(1, i + 1) = -1;
    elp(2, i + 1) = 0;
end
l(1) = 0;
l(2) = 0;
uLu(1) = -1;
uLu(2) = 0;
u = 0;

while true
    u = u + 1;
    if d(u + 1) == -1
        l(u + 2) = l(u + 1);
        for i = 0:l(u + 1)
            elp(u + 2, i + 1) = elp(u + 1, i + 1);
            elp(u + 1, i + 1) = idx(elp(u + 1, i + 1));
        end
    else
        q = u - 1;
        while q > 0 && d(q + 1) == -1
            q = q - 1;
        end
        if q > 0
            j = q;
            while j > 0
                j = j - 1;
                if d(j + 1) ~= -1 && uLu(q + 1) < uLu(j + 1)
                    q = j;
                end
            end
        end
        l(u + 2) = max(l(u + 1), l(q + 1) + u - q);
        elp(u + 2, :) = 0;
        for i = 0:l(q + 1)
            if elp(q + 1, i + 1) ~= -1
                elp(u + 2, i + u - q + 1) = gfExp(mod(d(u + 1) + 63 - d(q + 1) + elp(q + 1, i + 1), 63) + 1);
            end
        end
        for i = 0:l(u + 1)
            elp(u + 2, i + 1) = bitxor(elp(u + 2, i + 1), elp(u + 1, i + 1));
            elp(u + 1, i + 1) = idx(elp(u + 1, i + 1));
        end
    end
    uLu(u + 2) = u - l(u + 2);
    if u < nroots
        if s(u + 1) ~= -1
            d(u + 2) = gfExp(s(u + 1) + 1);
        else
            d(u + 2) = 0;
        end
        for i = 1:l(u + 2)
            if s(u + 1 - i) ~= -1 && elp(u + 2, i + 1) ~= 0
                d(u + 2) = bitxor(d(u + 2), gfExp(mod(s(u + 1 - i) + idx(elp(u + 2, i + 1)), 63) + 1));
            end
        end
        d(u + 2) = idx(d(u + 2));
    end
    if ~(u < nroots && l(u + 2) <= t)
        break;
    end
end

u = u + 1;
if l(u + 1) > t
    ok = false;
    return;
end
for i = 0:l(u + 1)
    elp(u + 1, i + 1) = idx(elp(u + 1, i + 1));
end

root = zeros(1, t);
loc = zeros(1, t);
reg = zeros(1, t + 1);
for i = 1:l(u + 1)
    reg(i + 1) = elp(u + 1, i + 1);
end
count = 0;
for i = 1:63
    q = 1;
    for j = 1:l(u + 1)
        if reg(j + 1) ~= -1
            reg(j + 1) = mod(reg(j + 1) + j, 63);
            q = bitxor(q, gfExp(reg(j + 1) + 1));
        end
    end
    if q == 0
        if count >= t
            ok = false;
            return;
        end
        count = count + 1;
        root(count) = i;
        loc(count) = 63 - i;
    end
end
if count ~= l(u + 1)
    ok = false;
    return;
end

z = zeros(1, t + 1);
err = zeros(1, 63);
for i = 1:l(u + 1)
    if s(i) ~= -1 && elp(u + 1, i + 1) ~= -1
        z(i + 1) = bitxor(gfExp(s(i) + 1), gfExp(elp(u + 1, i + 1) + 1));
    elseif s(i) ~= -1
        z(i + 1) = gfExp(s(i) + 1);
    elseif elp(u + 1, i + 1) ~= -1
        z(i + 1) = gfExp(elp(u + 1, i + 1) + 1);
    else
        z(i + 1) = 0;
    end
    for j = 1:i-1
        if s(j) ~= -1 && elp(u + 1, i - j + 1) ~= -1
            z(i + 1) = bitxor(z(i + 1), gfExp(mod(elp(u + 1, i - j + 1) + s(j), 63) + 1));
        end
    end
    z(i + 1) = idx(z(i + 1));
end

for i = 0:62
    if recd(i + 1) ~= -1
        recdPoly(i + 1) = gfExp(recd(i + 1) + 1);
    else
        recdPoly(i + 1) = 0;
    end
end

for i = 1:l(u + 1)
    err(loc(i) + 1) = 1;
    for j = 1:l(u + 1)
        if z(j + 1) ~= -1
            err(loc(i) + 1) = bitxor(err(loc(i) + 1), gfExp(mod(z(j + 1) + j * root(i), 63) + 1));
        end
    end
    if err(loc(i) + 1) ~= 0
        err(loc(i) + 1) = idx(err(loc(i) + 1));
        q = 0;
        for j = 1:l(u + 1)
            if j ~= i
                q = q + idx(bitxor(1, gfExp(mod(loc(j) + root(i), 63) + 1)));
            end
        end
        q = mod(q, 63);
        err(loc(i) + 1) = gfExp(mod(err(loc(i) + 1) - q + 63, 63) + 1);
        recdPoly(loc(i) + 1) = bitxor(recdPoly(loc(i) + 1), err(loc(i) + 1));
    end
end
ok = true;

    function out = idx(x)
        if x == 0
            out = -1;
        else
            out = gfLog(x + 1);
        end
    end
end

function [gfExp, gfLog] = gf6Tables()
gfExp = zeros(1, 126);
gfLog = zeros(1, 64);
x = 1;
for i = 0:62
    gfExp(i + 1) = x;
    gfLog(x + 1) = i;
    x = bitshift(x, 1);
    if bitand(x, 64)
        x = bitxor(x, hex2dec('43'));
    end
    x = bitand(x, 63);
end
for i = 63:125
    gfExp(i + 1) = gfExp(i - 63 + 1);
end
end

