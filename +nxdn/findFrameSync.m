function candidates = findFrameSync(y, cfg)
%FINDFRAMESYNC Find NXDN96 FSW candidates at symbol-spaced phases.
if nargin < 2 || isempty(cfg)
    cfg = nxdn.config();
end
y = double(y(:));
sps = cfg.samplesPerSymbol;
tpl = nxdn.constants().fswLevels(:);
tplEnergy = sum(tpl.^2);
raw = repmat(emptyCandidate(), 0, 1);
for phase = 1:sps
    seq = y(phase:sps:end);
    if numel(seq) < numel(tpl)
        continue;
    end
    numerator = conv(seq, flipud(tpl), 'valid');
    energy = conv(seq.^2, ones(numel(tpl), 1), 'valid');
    score = numerator ./ sqrt(max(energy * tplEnergy, eps));
    mag = abs(score);
    local = mag >= cfg.syncThreshold;
    if numel(local) >= 3
        local(2:end-1) = local(2:end-1) & ...
            mag(2:end-1) >= mag(1:end-2) & mag(2:end-1) >= mag(3:end);
    end
    indexes = find(local);
    for j = 1:numel(indexes)
        idx = indexes(j);
        item = emptyCandidate();
        item.fs_start = phase + (idx - 1) * sps;
        item.symbol_phase = phase - 1;
        item.polarity = sign(score(idx));
        if item.polarity == 0, item.polarity = 1; end
        item.score = mag(idx);
        raw(end+1, 1) = item; %#ok<AGROW>
    end
end
if isempty(raw)
    candidates = raw;
    return;
end
[~, order] = sort([raw.score], 'descend');
kept = repmat(emptyCandidate(), 0, 1);
for idx = order
    start = raw(idx).fs_start;
    if isempty(kept) || all(abs([kept.fs_start] - start) >= cfg.syncMinDistanceSamples)
        kept(end+1, 1) = raw(idx); %#ok<AGROW>
    end
end
[~, order] = sort([kept.fs_start]);
candidates = kept(order);
if isfinite(cfg.maxFrameCandidates) && numel(candidates) > cfg.maxFrameCandidates
    candidates = candidates(1:cfg.maxFrameCandidates);
end
for k = 1:numel(candidates)
    candidates(k).frame_index = k;
end
end

function item = emptyCandidate()
item = struct('fs_start', 0, 'symbol_phase', 0, 'polarity', 1, ...
    'score', 0, 'frame_index', 0, 'locked', false);
end
