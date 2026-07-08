function report = inferSlotCandidates(bits, training, seqs, cfg)
%INFERSLOTCANDIDATES Infer 510-bit TETRA slot candidates from training hits.
bits = bits(:) ~= 0;
layouts = tetra.slotLayouts(seqs, cfg);
candidates = repmat(emptyCandidate(), 0, 1);

if ~isfield(training, 'hits') || isempty(training.hits)
    report = makeReport(candidates, layouts);
    return;
end

for k = 1:numel(training.hits)
    hit = training.hits(k);
    layoutIdx = find(strcmp({layouts.trainingName}, hit.name));
    for m = 1:numel(layoutIdx)
        layout = layouts(layoutIdx(m));
        slotStart = hit.bitOffset - layout.trainingStartBit + 1;
        slotEnd = slotStart + cfg.slotBits - 1;
        isComplete = slotStart >= 1 && slotEnd <= numel(bits);
        bitString = '';
        dibitString = '';
        if isComplete
            slotBits = bits(slotStart:slotEnd);
            bitString = bitsToString(slotBits);
            dibitString = dibitsToString(slotBits);
        end
        candidates(end+1, 1) = struct( ... %#ok<AGROW>
            'trainingName', char(hit.name), ...
            'burstClass', char(layout.burstClass), ...
            'description', char(layout.description), ...
            'slotStartBit', slotStart, ...
            'slotEndBit', slotEnd, ...
            'slotBits', cfg.slotBits, ...
            'isComplete', isComplete, ...
            'symbolAligned', mod(slotStart, 2) == 1, ...
            'trainingStartBit', hit.bitOffset, ...
            'trainingStartBitInSlot', layout.trainingStartBit, ...
            'trainingLength', hit.length, ...
            'trainingErrors', hit.errors, ...
            'trainingErrorFraction', hit.errorFraction, ...
            'isGood', hit.isGood, ...
            'bitString', bitString, ...
            'dibitString', dibitString);
    end
end

candidates = rankAndLimit(candidates, cfg);
report = makeReport(candidates, layouts);
end

function c = emptyCandidate()
c = struct( ...
    'trainingName', '', ...
    'burstClass', '', ...
    'description', '', ...
    'slotStartBit', NaN, ...
    'slotEndBit', NaN, ...
    'slotBits', 0, ...
    'isComplete', false, ...
    'symbolAligned', false, ...
    'trainingStartBit', NaN, ...
    'trainingStartBitInSlot', NaN, ...
    'trainingLength', 0, ...
    'trainingErrors', 0, ...
    'trainingErrorFraction', 1, ...
    'isGood', false, ...
    'bitString', '', ...
    'dibitString', '');
end

function report = makeReport(candidates, layouts)
report = struct();
report.candidates = candidates;
report.candidateCount = numel(candidates);
report.completeCount = nnz([candidates.isComplete]);
report.goodCount = nnz([candidates.isGood]);
report.layouts = layouts;
end

function candidates = rankAndLimit(candidates, cfg)
if isempty(candidates)
    return;
end
rank = zeros(numel(candidates), 5);
for k = 1:numel(candidates)
    rank(k, :) = [ ...
        -double(candidates(k).isComplete), ...
        -double(candidates(k).isGood), ...
        candidates(k).trainingErrorFraction, ...
        candidates(k).trainingErrors, ...
        candidates(k).slotStartBit];
end
[~, order] = sortrows(rank);
maxCount = getCfg(cfg, 'slotCandidateMaxCount', 24);
maxPerTraining = getCfg(cfg, 'slotCandidateMaxPerTraining', maxCount);
ranked = candidates(order);
kept = repmat(emptyCandidate(), 0, 1);
for k = 1:numel(ranked)
    c = ranked(k);
    if numel(kept) >= maxCount
        break;
    end
    if ~isempty(kept) && nnz(strcmp({kept.trainingName}, c.trainingName)) >= maxPerTraining
        continue;
    end
    kept(end+1, 1) = c; %#ok<AGROW>
end
candidates = kept;
[~, order] = sort([candidates.slotStartBit]);
candidates = candidates(order);
end

function txt = bitsToString(bits)
txt = char('0' + double(bits(:).'));
end

function txt = dibitsToString(bits)
bits = double(bits(:));
n = floor(numel(bits) / 2);
if n < 1
    txt = '';
    return;
end
pairs = reshape(bits(1:2*n), 2, n).';
dibits = pairs(:, 1) * 2 + pairs(:, 2);
txt = char('0' + dibits(:).');
end

function value = getCfg(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
