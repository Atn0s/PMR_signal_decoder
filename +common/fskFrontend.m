function y = fskFrontend(iqDec, varargin)
%FSKFRONTEND DDC, channel filter, FM discriminator, and DC removal.
p = inputParser;
p.addParameter('Fo', 0.0);
p.addParameter('Fs', 48000.0);
p.addParameter('Cutoff', 9500.0);
p.addParameter('NTaps', 151);
p.addParameter('DevNominal', 1944.0);
p.addParameter('MinSamples', 512);
p.addParameter('PsdNperseg', 4096);
p.parse(varargin{:});

iqDec = iqDec(:);
if numel(iqDec) < p.Results.MinSamples
    error('common:fskFrontend:TooShort', ...
        'Signal too short (%d samples), need >= %d.', ...
        numel(iqDec), p.Results.MinSamples);
end

fs = double(p.Results.Fs);
fo = double(p.Results.Fo);
n = (0:numel(iqDec)-1).';
if fo ~= 0
    iqDec = iqDec .* exp(-1i * 2 * pi * fo .* n ./ fs);
end

[f, psd] = common.welchPsd(iqDec, fs, p.Results.PsdNperseg);
[~, idx] = max(psd);
cf = f(idx);
iqf = iqDec .* exp(-1i * 2 * pi * cf .* n ./ fs);

if exist('fir1', 'file') ~= 2 || exist('filtfilt', 'file') ~= 2
    error('common:fskFrontend:MissingToolbox', ...
        'fir1() and filtfilt() are required for the FSK frontend.');
end
b = fir1(round(p.Results.NTaps) - 1, double(p.Results.Cutoff) / (fs / 2));
iqf = filtfilt(b, 1.0, iqf);

yd = angle(iqf(2:end) .* conj(iqf(1:end-1)));
amp = abs(iqf(1:end-1));
active = amp > (median(amp) + 0.3 * (mean(amp) - median(amp)));
if any(active)
    center = median(yd(active));
else
    center = median(yd);
end
y = (yd - center) .* (3.0 / (2.0 * pi * double(p.Results.DevNominal) / fs));
y = y(:);
end

