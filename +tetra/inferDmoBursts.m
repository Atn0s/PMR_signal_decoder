function report = inferDmoBursts(bits, training, seqs, cfg)
%INFERDMOBURSTS Infer, classify, and extract DMO DNB/DSB payload blocks.
if nargin < 3 || isempty(seqs)
    seqs = tetra.trainingSequences();
end
if nargin < 4 || isempty(cfg)
    cfg = tetra.config();
end

bits = bits(:) ~= 0;
defs = tetra.dmoBurstDefinitions(seqs, cfg);
candidates = repmat(emptyCandidate(), 0, 1);

if ~isfield(training, 'hits') || isempty(training.hits)
    report = makeReport(candidates, defs);
    return;
end

for k = 1:numel(training.hits)
    hit = training.hits(k);
    defIdx = find(strcmp({defs.trainingName}, hit.name));
    for m = 1:numel(defIdx)
        def = defs(defIdx(m));
        slotStart = hit.bitOffset - def.trainingStartBit + 1;
        slotEnd = slotStart + cfg.slotBits - 1;
        isComplete = slotStart >= 1 && slotEnd <= numel(bits);
        bitString = '';
        dibitString = '';
        payloadBlocks = struct([]);
        classification = incompleteClassification(def);
        if isComplete
            slotBits = bits(slotStart:slotEnd);
            bitString = bitsToString(slotBits);
            dibitString = dibitsToString(slotBits);
            classification = tetra.classifyDmoBurst(slotBits, def, cfg);
            payloadBlocks = tetra.extractDmoPayload(slotBits, classification, slotStart);
        end
        candidates(end+1, 1) = makeCandidate(hit, def, classification, ... %#ok<AGROW>
            slotStart, slotEnd, isComplete, bitString, dibitString, payloadBlocks);
    end
end

candidates = sortCandidates(candidates);
candidates = limitCandidates(candidates, cfg);
report = makeReport(candidates, defs);
end

function c = emptyCandidate()
c = struct( ...
    'slotStartBit', NaN, ...
    'slotEndBit', NaN, ...
    'slotBits', 0, ...
    'isComplete', false, ...
    'symbolAligned', false, ...
    'expectedBurstName', '', ...
    'expectedBurstType', '', ...
    'trainingName', '', ...
    'trainingStartBit', NaN, ...
    'trainingStartBitInSlot', NaN, ...
    'trainingLength', 0, ...
    'trainingHitErrors', 0, ...
    'trainingHitErrorFraction', 1, ...
    'isTrainingGood', false, ...
    'burstName', '', ...
    'burstType', 'unknown', ...
    'preambleName', '', ...
    'description', '', ...
    'isConfirmed', false, ...
    'confidence', 0, ...
    'totalErrors', 0, ...
    'totalCheckedBits', 0, ...
    'errorFraction', 1, ...
    'preambleErrors', 0, ...
    'preambleLength', 0, ...
    'trainingErrors', 0, ...
    'frequencyErrors', 0, ...
    'frequencyLength', 0, ...
    'tailErrors', 0, ...
    'bkn1StartBit', 0, ...
    'bkn1EndBit', 0, ...
    'bkn1LogicalChannel', '', ...
    'bkn2StartBit', 0, ...
    'bkn2EndBit', 0, ...
    'bkn2LogicalChannel', '', ...
    'payloadBlocks', struct([]), ...
    'bitString', '', ...
    'dibitString', '');
end

function c = makeCandidate(hit, def, cls, slotStart, slotEnd, isComplete, ...
        bitString, dibitString, payloadBlocks)
c = emptyCandidate();
c.slotStartBit = slotStart;
c.slotEndBit = slotEnd;
c.slotBits = def.slotBits;
c.isComplete = isComplete;
c.symbolAligned = mod(slotStart, 2) == 1;
c.expectedBurstName = def.name;
c.expectedBurstType = def.burstType;
c.trainingName = char(hit.name);
c.trainingStartBit = hit.bitOffset;
c.trainingStartBitInSlot = def.trainingStartBit;
c.trainingLength = hit.length;
c.trainingHitErrors = hit.errors;
c.trainingHitErrorFraction = hit.errorFraction;
c.isTrainingGood = hit.isGood;
c.burstName = cls.burstName;
c.burstType = cls.burstType;
c.preambleName = cls.preambleName;
c.description = cls.description;
c.isConfirmed = cls.isConfirmed;
c.confidence = cls.confidence;
c.totalErrors = cls.totalErrors;
c.totalCheckedBits = cls.totalCheckedBits;
c.errorFraction = cls.errorFraction;
c.preambleErrors = cls.preambleErrors;
c.preambleLength = cls.preambleLength;
c.trainingErrors = cls.trainingErrors;
c.frequencyErrors = cls.frequencyErrors;
c.frequencyLength = cls.frequencyLength;
c.tailErrors = cls.tailErrors;
c.bkn1StartBit = cls.bkn1StartBit;
c.bkn1EndBit = cls.bkn1EndBit;
c.bkn1LogicalChannel = cls.bkn1LogicalChannel;
c.bkn2StartBit = cls.bkn2StartBit;
c.bkn2EndBit = cls.bkn2EndBit;
c.bkn2LogicalChannel = cls.bkn2LogicalChannel;
c.payloadBlocks = payloadBlocks;
c.bitString = bitString;
c.dibitString = dibitString;
end

function cls = incompleteClassification(def)
cls = struct( ...
    'burstName', def.name, ...
    'burstType', def.burstType, ...
    'trainingName', def.trainingName, ...
    'preambleName', def.preambleName, ...
    'description', def.description, ...
    'isConfirmed', false, ...
    'confidence', 0, ...
    'totalErrors', 0, ...
    'totalCheckedBits', 0, ...
    'errorFraction', 1, ...
    'preambleErrors', 0, ...
    'preambleLength', numel(def.preambleBits), ...
    'trainingErrors', 0, ...
    'trainingLength', numel(def.trainingBits), ...
    'trainingErrorFraction', 1, ...
    'frequencyErrors', 0, ...
    'frequencyLength', numel(def.frequencyBits), ...
    'frequencyErrorFraction', NaN, ...
    'tailErrors', 0, ...
    'tailLength', numel(def.tailBits), ...
    'bkn1StartBit', def.bkn1StartBit, ...
    'bkn1EndBit', def.bkn1EndBit, ...
    'bkn1Name', def.bkn1Name, ...
    'bkn1LogicalChannel', def.bkn1LogicalChannel, ...
    'bkn2StartBit', def.bkn2StartBit, ...
    'bkn2EndBit', def.bkn2EndBit, ...
    'bkn2Name', def.bkn2Name, ...
    'bkn2LogicalChannel', def.bkn2LogicalChannel);
end

function report = makeReport(candidates, defs)
bursts = confirmedBursts(candidates);
payloadBlocks = collectPayloadBlocks(bursts);
report = struct();
report.candidates = candidates;
report.bursts = bursts;
report.payloadBlocks = payloadBlocks;
report.candidateCount = numel(candidates);
report.completeCount = countField(candidates, 'isComplete');
report.confirmedCount = numel(bursts);
report.goodCount = numel(bursts);
report.dsbCount = nnz(strcmp({bursts.burstType}, 'DSB'));
report.dnbCount = nnz(strcmp({bursts.burstType}, 'DNB'));
report.payloadBlockCount = numel(payloadBlocks);
report.definitions = defs;
end

function bursts = confirmedBursts(candidates)
if isempty(candidates)
    bursts = candidates;
    return;
end
bursts = candidates([candidates.isConfirmed]);
if isempty(bursts)
    return;
end
bursts = sortCandidates(bursts);
starts = [bursts.slotStartBit];
uniqueStarts = unique(starts, 'stable');
keep = false(numel(bursts), 1);
for k = 1:numel(uniqueStarts)
    idx = find(starts == uniqueStarts(k));
    bestIdx = idx(1);
    for m = 2:numel(idx)
        if betterCandidate(bursts(idx(m)), bursts(bestIdx))
            bestIdx = idx(m);
        end
    end
    keep(bestIdx) = true;
end
bursts = bursts(keep);
bursts = sortCandidates(bursts);
end

function yes = betterCandidate(a, b)
if a.errorFraction ~= b.errorFraction
    yes = a.errorFraction < b.errorFraction;
else
    yes = a.totalErrors < b.totalErrors;
end
end

function payloadBlocks = collectPayloadBlocks(bursts)
payloadBlocks = struct([]);
for k = 1:numel(bursts)
    blocks = bursts(k).payloadBlocks;
    if isempty(blocks)
        continue;
    end
    if isempty(payloadBlocks)
        payloadBlocks = blocks(:);
    else
        payloadBlocks = [payloadBlocks; blocks(:)]; %#ok<AGROW>
    end
end
end

function candidates = sortCandidates(candidates)
if isempty(candidates)
    return;
end
rank = zeros(numel(candidates), 4);
for k = 1:numel(candidates)
    rank(k, :) = [ ...
        candidates(k).slotStartBit, ...
        -double(candidates(k).isConfirmed), ...
        candidates(k).errorFraction, ...
        candidates(k).totalErrors];
end
[~, order] = sortrows(rank);
candidates = candidates(order);
end

function candidates = limitCandidates(candidates, cfg)
if isempty(candidates)
    return;
end
maxCount = getCfg(cfg, 'dmoBurstCandidateMaxCount', numel(candidates));
if numel(candidates) <= maxCount
    return;
end
confirmed = candidates([candidates.isConfirmed]);
others = candidates(~[candidates.isConfirmed]);
others = rankRejected(others);
nOther = max(0, maxCount - numel(confirmed));
candidates = [confirmed; others(1:min(nOther, numel(others)))];
candidates = sortCandidates(candidates);
end

function candidates = rankRejected(candidates)
if isempty(candidates)
    return;
end
rank = zeros(numel(candidates), 3);
for k = 1:numel(candidates)
    rank(k, :) = [candidates(k).errorFraction, candidates(k).totalErrors, candidates(k).slotStartBit];
end
[~, order] = sortrows(rank);
candidates = candidates(order);
end

function n = countField(items, fieldName)
if isempty(items)
    n = 0;
else
    n = nnz([items.(fieldName)]);
end
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
