function sync = timingSearch(x, cfg)
%TIMINGSEARCH Offline timing phase search for pi/4-DQPSK differential symbols.
x = x(:);
sps = cfg.samplesPerSymbol;
phaseGrid = 0:cfg.timingPhaseStepSamples:(sps - cfg.timingPhaseStepSamples);
centers = [-3 -1 1 3].' .* pi ./ 4;

metrics = struct('phaseSamples', num2cell(phaseGrid), ...
    'errorRad', [], 'phaseOffsetRad', [], 'validTransitions', []);
bestScore = inf;
best = struct();

for k = 1:numel(phaseGrid)
    ph = phaseGrid(k);
    symbols = sampleAtPhase(x, sps, ph);
    if numel(symbols) < 8
        score = inf;
        phaseOffset = 0;
        valid = false(0, 1);
    else
        dphi = angle(symbols(2:end) .* conj(symbols(1:end-1)));
        amp = min(abs(symbols(2:end)), abs(symbols(1:end-1)));
        valid = activeTransitions(amp);
        [phaseOffset, err] = bestPhaseOffset(dphi(valid), centers, cfg);
        if isempty(err)
            score = inf;
        else
            score = median(abs(err));
        end
    end
    metrics(k).errorRad = score;
    metrics(k).phaseOffsetRad = phaseOffset;
    metrics(k).validTransitions = nnz(valid);
    if score < bestScore
        bestScore = score;
        best.phaseSamples = ph;
        best.symbols = symbols;
        best.validTransitionMask = valid;
        best.diffPhaseOffsetRad = phaseOffset;
        best.errorRad = score;
    end
end

sync = best;
sync.metrics = metrics;
if numel(sync.symbols) >= 2
    sync.diffPhaseRaw = angle(sync.symbols(2:end) .* conj(sync.symbols(1:end-1)));
else
    sync.diffPhaseRaw = zeros(0, 1);
end
end

function symbols = sampleAtPhase(x, sps, phase)
last = numel(x) - 1;
pos = (phase:sps:last).';
if isempty(pos)
    symbols = complex(zeros(0, 1));
else
    symbols = common.interpLinear(x, pos);
end
end

function valid = activeTransitions(amp)
amp = amp(:);
if isempty(amp)
    valid = false(0, 1);
    return;
end
lo = median(amp);
hi = prctile(amp, 90);
thr = lo + 0.20 * max(hi - lo, 0);
valid = amp > thr;
if nnz(valid) < max(16, round(0.10 * numel(amp)))
    valid = true(size(amp));
end
end

function [offset, err] = bestPhaseOffset(dphi, centers, cfg)
dphi = dphi(:);
if isempty(dphi)
    offset = 0;
    err = zeros(0, 1);
    return;
end
searchValues = representativeTransitions(dphi, cfg);
offsetGrid = (-pi/4):cfg.diffPhaseOffsetStepRad:(pi/4);
bestScore = inf;
offset = 0;
for off = offsetGrid
    e = nearestError(wrapToPiLocal(searchValues - off), centers);
    score = median(abs(e));
    if score < bestScore
        bestScore = score;
        offset = off;
    end
end
err = nearestError(wrapToPiLocal(dphi - offset), centers);
end

function values = representativeTransitions(values, cfg)
maxCount = 8192;
if isfield(cfg, 'diffPhaseSearchMaxTransitions')
    maxCount = cfg.diffPhaseSearchMaxTransitions;
end
if ~isfinite(maxCount) || numel(values) <= maxCount
    return;
end
indices = unique(round(linspace(1, numel(values), maxCount)));
values = values(indices);
end

function err = nearestError(values, centers)
% The four pi/4-DQPSK centers are uniformly spaced by pi/2.  Folding into
% [-pi/4, pi/4) is exactly the nearest-center error and avoids constructing
% an N-by-4 distance matrix for every phase-offset candidate.
if numel(centers) == 4 && ...
        max(abs(diff(centers(:)) - pi / 2)) < 10 * eps
    err = mod(values(:), pi / 2) - pi / 4;
    return;
end
dist = abs(wrapToPiLocal(values(:) - centers(:).'));
[~, idx] = min(dist, [], 2);
err = wrapToPiLocal(values(:) - centers(idx));
end

function y = wrapToPiLocal(x)
y = mod(x + pi, 2 * pi) - pi;
end
