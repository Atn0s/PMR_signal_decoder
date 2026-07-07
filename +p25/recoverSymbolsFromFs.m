function symbols = recoverSymbolsFromFs(y, candidate, symbolCount, varargin)
%RECOVERSYMBOLSFROMFS Recover calibrated symbols forward from frame sync.
p = inputParser;
p.addParameter('Sps', 10);
p.addParameter('PhaseSearch', linspace(-4, 4, 33));
p.parse(varargin{:});

c = p25.constants();
if symbolCount < numel(c.frameSyncSymbols)
    symbols = [];
    return;
end

y = y(:);
levels = [-3; -1; 1; 3];
bestResid = inf;
symbols = [];
for phase = p.Results.PhaseSearch
    pos = candidate.fs_start + phase + (0:symbolCount-1).' .* p.Results.Sps;
    if pos(1) < 0 || pos(end) >= numel(y) - 1
        continue;
    end
    seg = candidate.polarity .* common.interpLinear(y, pos);
    fsSeg = seg(1:numel(c.frameSyncSymbols));
    coeff = [fsSeg, ones(numel(fsSeg), 1)] \ c.frameSyncSymbols(:);
    calibrated = coeff(1) .* seg + coeff(2);
    [~, nearestIdx] = min(abs(calibrated(:) - levels.'), [], 2);
    nearest = levels(nearestIdx);
    resid = mean((calibrated(1:numel(c.frameSyncSymbols)) - c.frameSyncSymbols(:)) .^ 2);
    resid = resid + 0.05 * mean((calibrated(:) - nearest(:)) .^ 2);
    if resid < bestResid
        bestResid = resid;
        symbols = calibrated(:);
    end
end
end

