function out = interpLinear(arr, pos)
%INTERPLINEAR Linear interpolation at zero-based sample positions.
arr = arr(:);
pos = pos(:);
if numel(arr) < 2
    error('common:interpLinear:TooShort', 'Need at least two samples.');
end

i0 = floor(pos);
frac = pos - i0;
i0 = max(0, min(i0, numel(arr) - 2));
idx = i0 + 1;
out = arr(idx) .* (1 - frac) + arr(idx + 1) .* frac;
end
