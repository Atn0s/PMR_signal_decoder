function candidates = findFrameSync(y, varargin)
%FINDFRAMESYNC Find P25 frame sync candidates.
p = inputParser;
p.addParameter('Sps', 10);
p.addParameter('Threshold', 0.62);
p.addParameter('MinDistanceSymbols', 120);
p.parse(varargin{:});

c = p25.constants();
ref = repelem(c.frameSyncSymbols(:), p.Results.Sps);
y = y(:);
if numel(y) < numel(ref)
    candidates = struct([]);
    return;
end
ncc = localNcc(y, ref);
distance = max(1, p.Results.MinDistanceSymbols * p.Results.Sps);
posPeaks = localFindPeaks(ncc, p.Results.Threshold, distance);
negPeaks = localFindPeaks(-ncc, p.Results.Threshold, distance);
half = floor(numel(ref) / 2);

candidates = struct([]);
for k = 1:numel(posPeaks)
    candidates = appendCandidate(candidates, posPeaks(k) - half - 1, 1.0, ncc(posPeaks(k)));
end
for k = 1:numel(negPeaks)
    candidates = appendCandidate(candidates, negPeaks(k) - half - 1, -1.0, -ncc(negPeaks(k)));
end
if isempty(candidates)
    return;
end
keep = arrayfun(@(x) x.fs_start >= 0 && x.fs_start + numel(ref) <= numel(y), candidates);
candidates = candidates(keep);
[~, order] = sort([candidates.fs_start]);
candidates = candidates(order);
end

function ncc = localNcc(y, ref)
corr = conv(y, flipud(ref), 'same');
energy = conv(y .^ 2, ones(numel(ref), 1), 'same');
energy(energy <= 0) = 1e-9;
ncc = corr ./ sqrt(energy .* sum(ref .^ 2));
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

function out = appendCandidate(arr, fsStart, polarity, ncc)
item = struct('fs_start', double(fsStart), 'polarity', double(polarity), 'ncc', double(ncc));
if isempty(arr)
    out = item;
else
    out = arr;
    out(end + 1) = item;
end
end

