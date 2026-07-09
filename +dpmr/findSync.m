function candidates = findSync(y, varargin)
%FINDSYNC Find dPMR FS1/FS2/FS3/FS4 sync candidates.
p = inputParser;
p.addParameter('Threshold', 0.82);
p.addParameter('MaxSymbolErrors', 0);
p.addParameter('MinDistanceSamples', 1200);
p.addParameter('DedupWindowSymbols', 3);
p.addParameter('SyncErrorPhaseSearch', linspace(-12, 12, 13));
p.addParameter('SyncTypes', {'FS1', 'FS2', 'FS3', 'FS4'});
p.parse(varargin{:});

c = dpmr.constants();
refs = {
    'FS1', false, c.fs1Symbols;
    'FS2', false, c.fs2Symbols;
    'FS3', false, c.fs3Symbols;
    'FS4', false, c.fs4Symbols;
    'FS1', true,  c.invFs1Symbols;
    'FS2', true,  c.invFs2Symbols;
    'FS3', true,  c.invFs3Symbols;
    'FS4', true,  c.invFs4Symbols;
};
want = string(p.Results.SyncTypes);
raw = struct([]);
for r = 1:size(refs, 1)
    syncType = refs{r, 1};
    inverted = refs{r, 2};
    ref = refs{r, 3};
    ncc = zeroMeanNcc(y(:), ref);
    peaks = localFindPeaks(ncc, p.Results.Threshold, p.Results.MinDistanceSamples);
    for k = 1:numel(peaks)
        fsStart = round((peaks(k) - 1) - (numel(ref) * c.sps) / 2);
        if fsStart < 0
            continue;
        end
        [errors, resid] = syncError(y(:), fsStart, ref, p.Results.SyncErrorPhaseSearch);
        if errors <= p.Results.MaxSymbolErrors
            item = struct('fs_start', fsStart, 'polarity_inverted', inverted, ...
                'ncc', ncc(peaks(k)), 'sync_type', syncType, ...
                'errors', errors, 'resid', resid);
            raw = appendStruct(raw, item);
        end
    end
end
if isempty(raw)
    candidates = struct([]);
    return;
end
[~, order] = sortrows([[raw.fs_start].', [raw.errors].', [raw.resid].', -[raw.ncc].']);
raw = raw(order);
deduped = struct([]);
for k = 1:numel(raw)
    cand = raw(k);
    if ~isempty(deduped) && abs(cand.fs_start - deduped(end).fs_start) < c.sps * p.Results.DedupWindowSymbols
        prev = deduped(end);
        if compareCandidate(cand, prev) < 0
            deduped(end) = cand;
        end
    else
        deduped = appendStruct(deduped, cand);
    end
end
candidates = filterSyncTypes(rmfield(deduped, {'errors', 'resid'}), want);
end

function candidates = filterSyncTypes(items, want)
candidates = struct([]);
for k = 1:numel(items)
    if any(want == string(items(k).sync_type))
        candidates = appendStruct(candidates, items(k));
    end
end
end

function ncc = zeroMeanNcc(y, refDibits)
c = dpmr.constants();
refLevels = dpmr.dibitsToLevels(refDibits);
wave = repelem(refLevels(:) - mean(refLevels), c.sps);
window = numel(wave);
kernel = ones(window, 1);
localMean = conv(y, kernel, 'same') ./ window;
centered = y - localMean;
corr = conv(centered, flipud(wave), 'same');
energy = conv(centered .^ 2, kernel, 'same');
energy(energy <= 0) = 1e-9;
ncc = corr ./ sqrt(energy .* sum(wave .^ 2));
end

function [errors, resid] = syncError(y, fsStart, ref, phaseSearch)
c = dpmr.constants();
bestErrors = numel(ref);
bestResid = inf;
refLevels = dpmr.dibitsToLevels(ref);
for phase = phaseSearch
    pos = fsStart + phase + (0:numel(ref)-1).' .* c.sps;
    if pos(1) < 0 || pos(end) >= numel(y) - 1
        continue;
    end
    seg = common.interpLinear(y, pos);
    coeff = [seg, ones(numel(seg), 1)] \ refLevels(:);
    calibrated = coeff(1) .* seg + coeff(2);
    [~, nearest] = min(abs(calibrated(:) - c.dibitLevels), [], 2);
    nearest = nearest(:).' - 1;
    itemErrors = sum(nearest ~= ref(:).');
    itemResid = mean((calibrated(:) - refLevels(:)) .^ 2);
    if itemErrors < bestErrors || (itemErrors == bestErrors && itemResid < bestResid)
        bestErrors = itemErrors;
        bestResid = itemResid;
    end
end
errors = bestErrors;
resid = bestResid;
end

function peaks = localFindPeaks(x, threshold, minDistance)
x = x(:);
candidate = find(x(2:end-1) > x(1:end-2) & x(2:end-1) >= x(3:end) & x(2:end-1) >= threshold) + 1;
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

function value = compareCandidate(a, b)
ak = [a.errors, a.resid, -a.ncc];
bk = [b.errors, b.resid, -b.ncc];
value = 0;
for k = 1:numel(ak)
    if ak(k) < bk(k), value = -1; return; end
    if ak(k) > bk(k), value = 1; return; end
end
end

function out = appendStruct(arr, item)
if isempty(arr), out = item; else, out = arr; out(end + 1) = item; end
end
