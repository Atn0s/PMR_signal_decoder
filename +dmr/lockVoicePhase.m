function phase = lockVoicePhase(y, anchor, polarity, syncType)
%LOCKVOICEPHASE Find best sub-symbol phase for DMR voice bursts.
templates = dmr.syncTemplates();
ref = templates.(char(syncType));
cfg = dmr.config();
levels = [-3 -1 1 3];
bestResid = inf;
phase = 0;
for ph = linspace(-8, 8, 65)
    start = anchor - (54 + 12) * cfg.samplesPerSymbol + ph;
    pos = start + (0:131).' .* cfg.samplesPerSymbol;
    if pos(1) < 0 || pos(end) >= numel(y) - 1
        continue;
    end
    seg = polarity .* common.interpLinear(y, pos);
    sy = seg(55:78);
    coeff = [sy, ones(24, 1)] \ ref(:);
    segc = coeff(1) .* seg + coeff(2);
    [~, idx] = min(abs(segc(:) - levels), [], 2);
    near = levels(idx).';
    resid = mean((segc(:) - near(:)) .^ 2);
    if resid < bestResid
        bestResid = resid;
        phase = ph;
    end
end
end

