function [foHz, info] = coarseFrequencyOffset(iq, fs, cfg)
%COARSEFREQUENCYOFFSET Estimate center offset from active-channel PSD.
iq = iq(:);
if isempty(iq)
    foHz = 0;
    info = struct('frequencyHz', [], 'psd', [], 'mask', [], 'method', 'empty');
    return;
end

[f, psd] = common.welchPsd(iq, fs, min(cfg.psdNperseg, numel(iq)));
psdDb = 10 .* log10(psd + 1e-18);
mask = abs(f) <= cfg.channelSearchHalfWidthHz & psdDb > median(psdDb) + 4;
if nnz(mask) >= 3
    weights = psd(mask);
    foHz = sum(f(mask) .* weights) / max(sum(weights), eps);
    method = 'weighted_psd_centroid';
else
    [~, idx] = max(psd);
    foHz = f(idx);
    method = 'psd_peak';
end
foHz = max(-cfg.channelSearchHalfWidthHz, min(cfg.channelSearchHalfWidthHz, foHz));

info = struct();
info.frequencyHz = f;
info.psd = psd;
info.mask = mask;
info.method = method;
end
