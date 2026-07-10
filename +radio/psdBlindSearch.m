function offsets = psdBlindSearch(iq, sampleRate, radioConfig)
%PSDBLINDSEARCH Find wideband candidates using a Welch PSD peak scan.
if nargin < 3 || isempty(radioConfig)
    radioConfig = radio.defaultConfig();
end
[f, psd] = common.welchPsd(iq, sampleRate, radioConfig.psdNperseg);
if isempty(f)
    offsets = zeros(1, 0);
    return;
end

% A modulated 4FSK carrier has several strong local spectral peaks.  Peak
% picking the raw PSD therefore returns the individual symbols/deviations as
% separate candidate radios.  Integrate power over a narrowband channel
% before peak picking so that one occupied channel produces one candidate.
binWidthHz = abs(median(diff(f)));
smoothingHz = getConfigValue(radioConfig, 'psdChannelSmoothingHz', 4800.0);
smoothingBins = max(3, round(smoothingHz / binWidthHz));
kernel = ones(smoothingBins, 1);
channelPsd = conv(psd, kernel, 'same') ./ ...
    conv(ones(size(psd)), kernel, 'same');
psdDb = 10 .* log10(channelPsd + 1e-12);
noiseFloor = median(psdDb);
threshold = noiseFloor + radioConfig.psdPeakThresholdDb;
spacingHz = getConfigValue(radioConfig, 'psdCandidateMinSpacingHz', ...
    radioConfig.psdPeakMinDistanceBins * binWidthHz);
minDistanceBins = max(1, round(spacingHz / binWidthHz));
maxCandidates = getConfigValue(radioConfig, 'psdMaxCandidates', inf);
peaks = localFindPeaks(psdDb, threshold, minDistanceBins, maxCandidates);
offsets = f(peaks).';
end

function value = getConfigValue(cfg, name, fallback)
if isfield(cfg, name) && ~isempty(cfg.(name))
    value = cfg.(name);
else
    value = fallback;
end
end

function peaks = localFindPeaks(x, threshold, minDistance, maxCandidates)
x = x(:);
candidate = find(x(2:end-1) > x(1:end-2) & x(2:end-1) >= x(3:end) & x(2:end-1) >= threshold) + 1;
if isempty(candidate)
    peaks = zeros(0, 1);
    return;
end
[~, order] = sort(x(candidate), 'descend');
candidate = candidate(order);
selected = [];
for k = 1:numel(candidate)
    if isempty(selected) || all(abs(candidate(k) - selected) >= minDistance)
        selected(end + 1) = candidate(k); %#ok<AGROW>
        if numel(selected) >= maxCandidates
            break;
        end
    end
end
peaks = sort(selected(:));
end
