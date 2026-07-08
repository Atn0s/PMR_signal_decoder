function report = findTrainingSequences(bits, seqs, cfg)
%FINDTRAININGSEQUENCES Search hard-decision bit stream for known sequences.
bits = bits(:) ~= 0;
items = repmat(struct( ...
    'name', '', ...
    'length', 0, ...
    'bestOffset', NaN, ...
    'bestErrors', 0, ...
    'errorFraction', 1, ...
    'isCandidate', false, ...
    'isGood', false, ...
    'description', ''), 0, 1);
hits = repmat(struct( ...
    'name', '', ...
    'length', 0, ...
    'bitOffset', NaN, ...
    'errors', 0, ...
    'errorFraction', 1, ...
    'isCandidate', false, ...
    'isGood', false, ...
    'description', ''), 0, 1);
score = 0;

for k = 1:numel(seqs)
    seqBits = seqs(k).bits(:) ~= 0;
    L = numel(seqBits);
    bestErrors = L;
    bestOffset = NaN;
    errorsByOffset = zeros(0, 1);
    if numel(bits) >= L
        errorsByOffset = zeros(numel(bits) - L + 1, 1);
        for pos = 1:(numel(bits) - L + 1)
            err = nnz(bits(pos:pos + L - 1) ~= seqBits);
            errorsByOffset(pos) = err;
            if err < bestErrors
                bestErrors = err;
                bestOffset = pos;
            end
        end
    end
    frac = bestErrors / L;
    isGood = frac <= cfg.trainingGoodErrorFraction;
    isCandidate = frac <= cfg.trainingMaxErrorFraction;
    items(end+1, 1) = struct( ...
        'name', seqs(k).name, ...
        'length', L, ...
        'bestOffset', bestOffset, ...
        'bestErrors', bestErrors, ...
        'errorFraction', frac, ...
        'isCandidate', isCandidate, ...
        'isGood', isGood, ...
        'description', seqs(k).description); %#ok<AGROW>
    if isCandidate
        score = score + (1 - frac) * L;
    end
    seqHits = collectHits(errorsByOffset, seqs(k), cfg);
    hits = [hits; seqHits(:)]; %#ok<AGROW>
end

if ~isempty(hits)
    [~, order] = sort([hits.bitOffset]);
    hits = hits(order);
end

report = struct();
report.items = items;
report.hits = hits;
report.score = score;
report.goodCount = nnz([items.isGood]);
report.candidateCount = nnz([items.isCandidate]);
report.hitCount = numel(hits);
end

function hits = collectHits(errorsByOffset, seq, cfg)
hits = repmat(struct( ...
    'name', '', ...
    'length', 0, ...
    'bitOffset', NaN, ...
    'errors', 0, ...
    'errorFraction', 1, ...
    'isCandidate', false, ...
    'isGood', false, ...
    'description', ''), 0, 1);
if isempty(errorsByOffset)
    return;
end

L = seq.length;
maxErrors = floor(cfg.trainingMaxErrorFraction * L + 1e-9);
left = [inf; errorsByOffset(1:end-1)];
right = [errorsByOffset(2:end); inf];
isLocalMin = errorsByOffset <= left & errorsByOffset <= right;
candidateOffsets = find(errorsByOffset <= maxErrors & isLocalMin);
if isempty(candidateOffsets)
    return;
end

[~, order] = sortrows([errorsByOffset(candidateOffsets), candidateOffsets]);
candidateOffsets = candidateOffsets(order);
maxHits = getCfg(cfg, 'trainingMaxHitsPerSequence', 20);
minSpacing = getCfg(cfg, 'trainingHitMinSpacingBits', 32);
keptOffsets = zeros(0, 1);
for k = 1:numel(candidateOffsets)
    pos = candidateOffsets(k);
    if numel(keptOffsets) >= maxHits
        break;
    end
    if ~isempty(keptOffsets) && any(abs(pos - keptOffsets) < minSpacing)
        continue;
    end
    err = errorsByOffset(pos);
    frac = err / L;
    hits(end+1, 1) = struct( ... %#ok<AGROW>
        'name', seq.name, ...
        'length', L, ...
        'bitOffset', pos, ...
        'errors', err, ...
        'errorFraction', frac, ...
        'isCandidate', frac <= cfg.trainingMaxErrorFraction, ...
        'isGood', frac <= cfg.trainingGoodErrorFraction, ...
        'description', seq.description);
    keptOffsets(end+1, 1) = pos; %#ok<AGROW>
end
end

function value = getCfg(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
