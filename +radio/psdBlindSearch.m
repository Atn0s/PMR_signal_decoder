function offsets = psdBlindSearch(iq, sampleRate, radioConfig)
%PSDBLINDSEARCH Find wideband candidates using a Welch PSD peak scan.
if nargin < 3 || isempty(radioConfig)
    radioConfig = radio.defaultConfig();
end
[f, psd] = common.welchPsd(iq, sampleRate, radioConfig.psdNperseg);
psdDb = 10 .* log10(psd + 1e-12);
noiseFloor = median(psdDb);
threshold = noiseFloor + radioConfig.psdPeakThresholdDb;
peaks = localFindPeaks(psdDb, threshold, radioConfig.psdPeakMinDistanceBins);
offsets = f(peaks).';
end

function peaks = localFindPeaks(x, threshold, minDistance)
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
    end
end
peaks = sort(selected(:));
end

