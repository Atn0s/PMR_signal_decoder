function [symbols, info] = recoverFrameSymbols(y, candidate, cfg)
%RECOVERFRAMESYMBOLS Recover and normalize one 192-symbol NXDN96 frame.
if nargin < 3 || isempty(cfg)
    cfg = nxdn.config();
end
y = double(y(:));
tpl = nxdn.constants().fswLevels(:);
best = struct('score', -inf, 'offset', 0, 'samples', []);
for offset = -cfg.syncRefineSamples:cfg.syncRefineSamples
    indexes = candidate.fs_start + offset + (0:cfg.frameSymbols-1).' * cfg.samplesPerSymbol;
    if indexes(1) < 1 || indexes(end) > numel(y)
        continue;
    end
    sample = y(indexes);
    x = [tpl ones(numel(tpl), 1)];
    fit = x \ sample(1:numel(tpl));
    scale = fit(1);
    if abs(scale) < 0.05
        continue;
    end
    normalizedFsw = (sample(1:numel(tpl)) - fit(2)) / scale;
    score = dot(normalizedFsw, tpl) / ...
        sqrt(max(sum(normalizedFsw.^2) * sum(tpl.^2), eps));
    if score > best.score
        best = struct('score', score, 'offset', offset, 'samples', sample, ...
            'scale', scale, 'center', fit(2));
    end
end
if isempty(best.samples)
    symbols = [];
    info = struct();
    return;
end
symbols = (best.samples - best.center) / best.scale;
info = struct('timingOffsetSamples', best.offset, 'fswScore', best.score, ...
    'scale', best.scale, 'center', best.center, ...
    'polarity', sign(best.scale), ...
    'fsStart', candidate.fs_start + best.offset);
end
