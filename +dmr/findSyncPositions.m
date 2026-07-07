function positions = findSyncPositions(y, cfg)
%FINDSYNCPOSITIONS Native DMR NCC sync search for visualization/debug.
if nargin < 2 || isempty(cfg)
    cfg = dmr.config();
end
templates = dmr.syncTemplates();
names = fieldnames(templates);
rows = {};
for k = 1:numel(names)
    name = names{k};
    ref = templates.(name);
    wave = repelem(ref(:), cfg.samplesPerSymbol);
    ncc = localNcc(y(:), wave);
    if contains(name, 'VOICE')
        thr = cfg.syncThresholdVoice;
    else
        thr = cfg.syncThresholdData;
    end
    posPeaks = localFindPeaks(ncc, thr, cfg.syncPeakDistanceSamples);
    negPeaks = localFindPeaks(-ncc, thr, cfg.syncPeakDistanceSamples);
    for j = 1:numel(posPeaks)
        rows(end + 1, :) = {posPeaks(j) - 1, 1.0, name}; %#ok<AGROW>
    end
    for j = 1:numel(negPeaks)
        rows(end + 1, :) = {negPeaks(j) - 1, -1.0, name}; %#ok<AGROW>
    end
end
if isempty(rows)
    positions = table([], [], strings(0, 1), 'VariableNames', {'center', 'polarity', 'syncType'});
else
    centers = cell2mat(rows(:, 1));
    [centers, order] = sort(centers);
    polarity = cell2mat(rows(order, 2));
    syncType = string(rows(order, 3));
    positions = table(centers(:), polarity(:), syncType(:), ...
        'VariableNames', {'center', 'polarity', 'syncType'});
end
end

function ncc = localNcc(y, wave)
c = conv(y, flipud(wave), 'same');
energy = conv(y .^ 2, ones(numel(wave), 1), 'same');
energy(energy <= 0) = 1e-9;
ncc = c ./ sqrt(energy .* sum(wave .^ 2));
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
