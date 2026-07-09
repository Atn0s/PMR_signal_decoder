function [windows, envelope] = scanActiveWindows(iq, fs, cfg)
%SCANACTIVEWINDOWS Find multiple active windows for offline TETRA scanning.
if nargin < 3 || isempty(cfg)
    cfg = tetra.config();
end
iq = iq(:);
windows = repmat(emptyWindow(), 0, 1);
envelope = emptyEnvelope();
if isempty(iq)
    return;
end

envWin = max(1, round(cfg.envelopeWindowSec * fs));
nWin = floor(numel(iq) / envWin);
if nWin < 4
    windows = makeWindowsFromSpan(1, numel(iq), 1, 1, iq, fs, envWin, [], 'short', cfg);
    envelope.mode = 'short';
    return;
end

trimmed = iq(1:nWin * envWin);
p = reshape(abs(trimmed) .^ 2, envWin, nWin);
pwrDb = 10 .* log10(mean(p, 1).' + 1e-12);
times = ((0:nWin-1).' * envWin) ./ fs;
floorDb = prctile(pwrDb, 20);
topDb = prctile(pwrDb, 95);
thr = max(floorDb + cfg.activeThresholdDb, ...
    floorDb + cfg.activeThresholdFraction * max(topDb - floorDb, 0));
mask = pwrDb > thr;
activeRatio = nnz(mask) / numel(mask);

envelope = struct();
envelope.mode = 'threshold';
envelope.windowSamples = envWin;
envelope.windowPowerDb = pwrDb;
envelope.windowTimesSec = times;
envelope.thresholdDb = thr;
envelope.activeRatio = activeRatio;
envelope.floorDb = floorDb;
envelope.topDb = topDb;
envelope.activeMask = mask;

if nnz(mask) < 3 || activeRatio > cfg.fullScanContinuousActiveRatio
    windows = makeWindowsFromSpan(1, numel(iq), 1, nWin, iq, fs, envWin, ...
        pwrDb, 'continuous_or_uncertain', cfg);
    envelope.mode = 'continuous_or_uncertain';
    windows = reindexWindows(windows);
    return;
end

runs = mergeRuns(contiguousRuns(mask), envWin, fs, cfg.fullScanMergeGapSec);
for k = 1:size(runs, 1)
    runStartWin = runs(k, 1);
    runEndWin = runs(k, 2);
    pre = round(cfg.fullScanPrePadSec * fs);
    post = round(cfg.fullScanPostPadSec * fs);
    startSample = max(1, (runStartWin - 1) * envWin + 1 - pre);
    endSample = min(numel(iq), runEndWin * envWin + post);
    next = makeWindowsFromSpan(startSample, endSample, runStartWin, runEndWin, ...
        iq, fs, envWin, pwrDb, 'active_run', cfg);
    windows = appendWindows(windows, next);
end
windows = reindexWindows(windows);
end

function windows = makeWindowsFromSpan(startSample, endSample, runStartWin, ...
        runEndWin, iq, fs, envWin, pwrDb, mode, cfg)
windows = repmat(emptyWindow(), 0, 1);
startSample = max(1, startSample);
endSample = min(numel(iq), endSample);
if endSample < startSample
    return;
end

maxSamples = max(1, round(cfg.fullScanWindowSec * fs));
overlap = min(maxSamples - 1, max(0, round(cfg.fullScanOverlapSec * fs)));
step = max(1, maxSamples - overlap);
minSamples = max(1, round(cfg.fullScanMinWindowSec * fs));

s = startSample;
splitIndex = 1;
while s <= endSample
    e = min(endSample, s + maxSamples - 1);
    if e - s + 1 < minSamples && ~isempty(windows)
        windows(end).endSample = e;
        windows(end) = fillWindowStats(windows(end), iq, fs, envWin, pwrDb);
        break;
    end
    w = emptyWindow();
    w.startSample = s;
    w.endSample = e;
    w.runStartWindow = runStartWin;
    w.runEndWindow = runEndWin;
    w.mode = mode;
    w.splitIndex = splitIndex;
    w = fillWindowStats(w, iq, fs, envWin, pwrDb);
    windows = appendWindows(windows, w);
    if e >= endSample
        break;
    end
    s = s + step;
    splitIndex = splitIndex + 1;
end
end

function w = fillWindowStats(w, iq, fs, envWin, pwrDb)
w.startSec = (w.startSample - 1) / fs;
w.endSec = (w.endSample - 1) / fs;
w.durationSec = max(0, w.endSec - w.startSec);
w.sampleCount = w.endSample - w.startSample + 1;
idx1 = max(1, floor((w.startSample - 1) / envWin) + 1);
if isempty(pwrDb)
    idx2 = idx1 - 1;
else
    idx2 = min(numel(pwrDb), ceil(w.endSample / envWin));
end
if isempty(pwrDb) || idx2 < idx1
    x = iq(w.startSample:w.endSample);
    p = 10 .* log10(abs(x) .^ 2 + 1e-12);
else
    p = pwrDb(idx1:idx2);
end
w.meanPowerDb = mean(p);
w.peakPowerDb = max(p);
end

function runs = contiguousRuns(mask)
mask = mask(:);
d = diff([false; mask; false]);
starts = find(d == 1);
ends = find(d == -1) - 1;
runs = [starts ends];
end

function runs = mergeRuns(runs, envWin, fs, mergeGapSec)
if isempty(runs)
    return;
end
merged = runs(1, :);
for k = 2:size(runs, 1)
    gapSec = (runs(k, 1) - merged(end, 2) - 1) * envWin / fs;
    if gapSec <= mergeGapSec
        merged(end, 2) = runs(k, 2);
    else
        merged(end+1, :) = runs(k, :); %#ok<AGROW>
    end
end
runs = merged;
end

function out = appendWindows(out, items)
if isempty(items)
    return;
end
if isempty(out)
    out = items(:);
else
    out = [out; items(:)];
end
end

function windows = reindexWindows(windows)
for k = 1:numel(windows)
    windows(k).index = k;
end
end

function w = emptyWindow()
w = struct( ...
    'index', 0, ...
    'startSample', 1, ...
    'endSample', 0, ...
    'startSec', 0, ...
    'endSec', 0, ...
    'durationSec', 0, ...
    'sampleCount', 0, ...
    'runStartWindow', 0, ...
    'runEndWindow', 0, ...
    'mode', '', ...
    'splitIndex', 0, ...
    'meanPowerDb', NaN, ...
    'peakPowerDb', NaN);
end

function envelope = emptyEnvelope()
envelope = struct( ...
    'mode', 'empty', ...
    'windowSamples', 0, ...
    'windowPowerDb', [], ...
    'windowTimesSec', [], ...
    'thresholdDb', NaN, ...
    'activeRatio', 0, ...
    'floorDb', NaN, ...
    'topDb', NaN, ...
    'activeMask', []);
end
