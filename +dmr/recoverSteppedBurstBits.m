function bits = recoverSteppedBurstBits(y, anchor, j, phase, polarity, strideSamples)
%RECOVERSTEPPEDBURSTBITS Recover voice burst bits at fixed stride.
cfg = dmr.config();
start = anchor + strideSamples * j - (54 + 12) * cfg.samplesPerSymbol + phase;
pos = start + (0:131).' .* cfg.samplesPerSymbol;
if pos(1) < 0 || pos(end) >= numel(y) - 1
    bits = [];
    return;
end
seg = polarity .* common.interpLinear(y, pos);
bits = dmr.adaptiveSliceBits(seg);
end

