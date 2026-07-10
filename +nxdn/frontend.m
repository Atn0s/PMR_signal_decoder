function [y, info] = frontend(iq, sampleRate, cfg)
%FRONTEND Resample, filter, and FM-demodulate centered NXDN96 IQ.
if nargin < 2 || isempty(sampleRate)
    error('nxdn:frontend:MissingSampleRate', 'Input sample rate is required.');
end
if nargin < 3 || isempty(cfg)
    cfg = nxdn.config();
end
iq = iq(:);
if numel(iq) < cfg.frontendMinSamples
    error('nxdn:frontend:TooShort', 'Signal is too short for the NXDN frontend.');
end
inputCount = numel(iq);
if abs(double(sampleRate) - cfg.targetSampleRateHz) > 1e-6
    iq48 = common.resampleTo(iq, sampleRate, cfg.targetSampleRateHz);
else
    iq48 = iq;
end
fs = cfg.targetSampleRateHz;
[f, psd] = common.welchPsd(iq48, fs, cfg.frontendPsdNperseg);
band = abs(f) <= 8000;
weights = max(psd(band) - median(psd(band)), 0);
if any(weights > 0)
    coarseFo = sum(f(band) .* weights) / sum(weights);
else
    coarseFo = 0;
end
n = (0:numel(iq48)-1).';
iq48 = iq48 .* exp(-1i * 2 * pi * coarseFo .* n ./ fs);
if exist('fir1', 'file') ~= 2 || exist('filtfilt', 'file') ~= 2
    error('nxdn:frontend:MissingToolbox', 'fir1 and filtfilt are required.');
end
b = fir1(cfg.frontendTaps - 1, cfg.frontendCutoffHz / (fs / 2));
iqf = filtfilt(b, 1, iq48);
phaseStep = angle(iqf(2:end) .* conj(iqf(1:end-1)));
amp = abs(iqf(1:end-1));
threshold = median(amp) + 0.3 * (mean(amp) - median(amp));
active = amp > threshold;
if nnz(active) >= 32
    residual = median(phaseStep(active));
else
    residual = median(phaseStep);
end
y = (phaseStep - residual) .* ...
    (3.0 / (2.0 * pi * cfg.nominalDeviationHz / fs));
y = y(:);
info = struct( ...
    'inputSampleRateHz', double(sampleRate), ...
    'outputSampleRateHz', fs, ...
    'inputSampleCount', inputCount, ...
    'outputSampleCount', numel(y), ...
    'coarseFrequencyOffsetHz', coarseFo, ...
    'residualFrequencyOffsetHz', residual * fs / (2*pi), ...
    'activeRatio', nnz(active) / numel(active));
end
