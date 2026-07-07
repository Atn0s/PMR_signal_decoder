function h = rrcTaps(alpha, sps, spanSymbols)
%RRCTAPS Unit-energy root raised cosine impulse response.
if nargin < 1 || isempty(alpha)
    alpha = 0.35;
end
if nargin < 2 || isempty(sps)
    sps = 4;
end
if nargin < 3 || isempty(spanSymbols)
    spanSymbols = 10;
end

half = spanSymbols * sps;
t = (-half:half).' ./ sps;
h = zeros(size(t));

for k = 1:numel(t)
    x = t(k);
    if abs(x) < 1e-12
        h(k) = 1 - alpha + 4 * alpha / pi;
    elseif alpha > 0 && abs(abs(x) - 1 / (4 * alpha)) < 1e-10
        h(k) = alpha / sqrt(2) * ( ...
            (1 + 2 / pi) * sin(pi / (4 * alpha)) + ...
            (1 - 2 / pi) * cos(pi / (4 * alpha)));
    else
        num = sin(pi * x * (1 - alpha)) + ...
            4 * alpha * x * cos(pi * x * (1 + alpha));
        den = pi * x * (1 - (4 * alpha * x) ^ 2);
        h(k) = num / den;
    end
end

energy = sqrt(sum(abs(h) .^ 2));
if energy > 0
    h = h ./ energy;
end
end
