function [f, psd] = welchPsd(x, fs, nperseg)
%WELCHPSD Two-sided Welch PSD with fftshifted ascending frequency.
if nargin < 3 || isempty(nperseg)
    nperseg = 4096;
end
x = x(:);
if isempty(x)
    f = zeros(0, 1);
    psd = zeros(0, 1);
    return;
end

nperseg = min(round(nperseg), numel(x));
nperseg = max(nperseg, 8);
step = max(1, floor(nperseg / 2));
win = localHamming(nperseg);
scale = fs * sum(abs(win) .^ 2);

starts = 1:step:(numel(x) - nperseg + 1);
if isempty(starts)
    starts = 1;
    x = [x; zeros(nperseg - numel(x), 1)];
end

acc = zeros(nperseg, 1);
for k = 1:numel(starts)
    seg = x(starts(k):starts(k) + nperseg - 1) .* win;
    acc = acc + abs(fft(seg, nperseg)) .^ 2 ./ scale;
end
psd = fftshift(acc ./ numel(starts));
if mod(nperseg, 2) == 0
    bins = (-nperseg/2:nperseg/2-1).';
else
    bins = (-(nperseg-1)/2:(nperseg-1)/2).';
end
f = bins .* (fs / nperseg);
end

function w = localHamming(n)
if n == 1
    w = 1;
else
    idx = (0:n-1).';
    w = 0.54 - 0.46 * cos(2 * pi * idx / (n - 1));
end
end

