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
score = 0;

for k = 1:numel(seqs)
    seqBits = seqs(k).bits(:) ~= 0;
    L = numel(seqBits);
    bestErrors = L;
    bestOffset = NaN;
    if numel(bits) >= L
        for pos = 1:(numel(bits) - L + 1)
            err = nnz(bits(pos:pos + L - 1) ~= seqBits);
            if err < bestErrors
                bestErrors = err;
                bestOffset = pos;
                if err == 0
                    break;
                end
            end
        end
    end
    frac = bestErrors / L;
    isGood = frac <= cfg.trainingGoodErrorFraction;
    isCandidate = frac <= cfg.trainingMaxErrorFraction;
    items(end+1) = struct( ...
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
end

report = struct();
report.items = items;
report.score = score;
report.goodCount = nnz([items.isGood]);
report.candidateCount = nnz([items.isCandidate]);
end
