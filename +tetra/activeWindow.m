function [seg, info] = activeWindow(iq, fs, cfg)
%ACTIVEWINDOW Pick a useful active region for DMO/TMO symbol inspection.
iq = iq(:);
if isempty(iq)
    seg = iq;
    info = struct('mode', 'empty', 'startSample', 1, 'endSample', 0, ...
        'thresholdDb', NaN, 'activeRatio', 0, 'windowPowerDb', [], ...
        'windowTimesSec', []);
    return;
end

win = max(1, round(cfg.envelopeWindowSec * fs));
nWin = floor(numel(iq) / win);
if nWin < 4
    seg = iq;
    info = struct('mode', 'short', 'startSample', 1, ...
        'endSample', numel(iq), 'thresholdDb', NaN, 'activeRatio', 1, ...
        'windowPowerDb', [], 'windowTimesSec', []);
    return;
end

trimmed = iq(1:nWin * win);
p = reshape(abs(trimmed) .^ 2, win, nWin);
pwrDb = 10 .* log10(mean(p, 1).' + 1e-12);
times = ((0:nWin-1).' * win) ./ fs;
floorDb = prctile(pwrDb, 20);
topDb = prctile(pwrDb, 95);
thr = max(floorDb + cfg.activeThresholdDb, ...
    floorDb + cfg.activeThresholdFraction * max(topDb - floorDb, 0));
mask = pwrDb > thr;
activeRatio = nnz(mask) / numel(mask);

if nnz(mask) < 3 || activeRatio > 0.85
    startSample = 1;
    endSample = min(numel(iq), max(1, round(cfg.previewMaxSec * fs)));
    mode = 'continuous_or_uncertain';
else
    runs = contiguousRuns(mask);
    scores = zeros(size(runs, 1), 1);
    for k = 1:size(runs, 1)
        idx = runs(k, 1):runs(k, 2);
        scores(k) = mean(pwrDb(idx)) + 0.05 * numel(idx);
    end
    [~, best] = max(scores);
    pad = round(cfg.activePadSec * fs);
    startSample = max(1, (runs(best, 1) - 1) * win + 1 - pad);
    endSample = min(numel(iq), runs(best, 2) * win + pad);
    maxSamples = round(cfg.activeMaxSec * fs);
    if endSample - startSample + 1 > maxSamples
        center = round((startSample + endSample) / 2);
        startSample = max(1, center - floor(maxSamples / 2));
        endSample = min(numel(iq), startSample + maxSamples - 1);
    end
    mode = 'bursty_active';
end

seg = iq(startSample:endSample);
info = struct();
info.mode = mode;
info.startSample = startSample;
info.endSample = endSample;
info.startSec = (startSample - 1) / fs;
info.endSec = (endSample - 1) / fs;
info.thresholdDb = thr;
info.activeRatio = activeRatio;
info.windowPowerDb = pwrDb;
info.windowTimesSec = times;
end

function runs = contiguousRuns(mask)
mask = mask(:);
d = diff([false; mask; false]);
starts = find(d == 1);
ends = find(d == -1) - 1;
runs = [starts ends];
end
