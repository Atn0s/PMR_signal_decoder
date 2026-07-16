function [report, finalContext] = inferDmoBursts( ...
        bits, training, seqs, cfg, bitValidMask, varargin)
%INFERDMOBURSTS Infer, classify, and extract DMO DNB/DSB payload blocks.
if nargin < 3 || isempty(seqs)
    seqs = tetra.trainingSequences();
end
if nargin < 4 || isempty(cfg)
    cfg = tetra.config();
end
p = inputParser;
p.addParameter('BitOffset', 0);
p.addParameter('MinimumSlotStartBit', -inf);
p.addParameter('InitialContext', []);
p.parse(varargin{:});
bitOffset = double(p.Results.BitOffset);
minimumSlotStartBit = double(p.Results.MinimumSlotStartBit);

bits = bits(:) ~= 0;
if nargin < 5 || isempty(bitValidMask) || numel(bitValidMask) ~= numel(bits)
    bitValidMask = true(size(bits));
else
    bitValidMask = logical(bitValidMask(:));
end
defs = tetra.dmoBurstDefinitions(seqs, cfg);
candidates = repmat(emptyCandidate(), 0, 1);

if ~isfield(training, 'hits') || isempty(training.hits)
    [report, finalContext] = makeReport( ...
        candidates, defs, cfg, p.Results.InitialContext);
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
        link = emptyDmoLink();
        slotValidMask = false(0, 1);
        if isComplete
            slotBits = bits(slotStart:slotEnd);
            slotValidMask = bitValidMask(slotStart:slotEnd);
            bitString = bitsToString(slotBits);
            dibitString = dibitsToString(slotBits);
            classification = tetra.classifyDmoBurst(slotBits, def, cfg);
            payloadBlocks = tetra.extractDmoPayload(slotBits, classification, slotStart, slotValidMask);
            link = decodeDsbSyncIfPresent(classification, payloadBlocks, cfg);
        end
        candidate = makeCandidate(hit, def, classification, ...
            slotStart, slotEnd, isComplete, bitString, dibitString, ...
            slotValidMask, payloadBlocks, link);
        candidates(end+1, 1) = ... %#ok<AGROW>
            offsetCandidate(candidate, bitOffset);
    end
end

candidates = sortCandidates(candidates);
candidates = limitCandidates(candidates, cfg);
if isfinite(minimumSlotStartBit) && ~isempty(candidates)
    candidates = candidates( ...
        [candidates.slotStartBit] >= minimumSlotStartBit);
end
[report, finalContext] = makeReport( ...
    candidates, defs, cfg, p.Results.InitialContext);
end

function candidate = offsetCandidate(candidate, bitOffset)
if bitOffset == 0, return; end
candidate.slotStartBit = candidate.slotStartBit + bitOffset;
candidate.slotEndBit = candidate.slotEndBit + bitOffset;
candidate.trainingStartBit = candidate.trainingStartBit + bitOffset;
for k = 1:numel(candidate.payloadBlocks)
    candidate.payloadBlocks(k).slotStartBit = ...
        candidate.payloadBlocks(k).slotStartBit + bitOffset;
    candidate.payloadBlocks(k).absoluteStartBit = ...
        candidate.payloadBlocks(k).absoluteStartBit + bitOffset;
    candidate.payloadBlocks(k).absoluteEndBit = ...
        candidate.payloadBlocks(k).absoluteEndBit + bitOffset;
end
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
    'schS', struct([]), ...
    'schSOk', false, ...
    'schH', struct([]), ...
    'schHOk', false, ...
    'dmacSync', struct([]), ...
    'dmacSyncOk', false, ...
    'dccBits', false(30, 1), ...
    'dccValid', false, ...
    'dccText', '', ...
    'dmoContext', struct([]), ...
    'contextValid', false, ...
    'macBlocks', struct([]), ...
    'stchBlocks', struct([]), ...
    'stchDecodedCount', 0, ...
    'schF', struct([]), ...
    'schFOk', false, ...
    'schFStatus', '', ...
    'frameNumber', NaN, ...
    'slotNumber', NaN, ...
    'timingLabel', '', ...
    'timingSource', '', ...
    'timingSlotDelta', NaN, ...
    'payloadBlocks', struct([]), ...
    'validBitCount', 0, ...
    'invalidBitCount', 0, ...
    'validBitRatio', NaN, ...
    'bitString', '', ...
    'dibitString', '');
end

function c = makeCandidate(hit, def, cls, slotStart, slotEnd, isComplete, ...
        bitString, dibitString, slotValidMask, payloadBlocks, link)
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
c.schS = link.schS;
c.schSOk = link.schSOk;
c.schH = link.schH;
c.schHOk = link.schHOk;
c.dmacSync = link.dmacSync;
c.dmacSyncOk = link.dmacSyncOk;
c.dccBits = link.dccBits;
c.dccValid = link.dccValid;
c.dccText = link.dccText;
if ~isempty(link.schS)
    c.frameNumber = link.schS.frameNumber;
    c.slotNumber = link.schS.slotNumber;
    if link.schS.ok
        c.timingLabel = sprintf('FN%d TN%d', link.schS.frameNumber, link.schS.slotNumber);
        c.timingSource = 'SCH/S';
        c.timingSlotDelta = 0;
    end
end
c.payloadBlocks = payloadBlocks;
if ~isempty(slotValidMask)
    c.validBitCount = nnz(slotValidMask);
    c.invalidBitCount = numel(slotValidMask) - c.validBitCount;
    c.validBitRatio = c.validBitCount / numel(slotValidMask);
end
c.bitString = bitString;
c.dibitString = dibitString;
end

function link = emptyDmoLink()
link = struct( ...
    'schS', struct([]), ...
    'schSOk', false, ...
    'schH', struct([]), ...
    'schHOk', false, ...
    'dmacSync', struct([]), ...
    'dmacSyncOk', false, ...
    'dccBits', false(30, 1), ...
    'dccValid', false, ...
    'dccText', '');
end

function link = decodeDsbSyncIfPresent(classification, payloadBlocks, cfg)
link = emptyDmoLink();
if ~classification.isConfirmed || ~strcmp(classification.burstType, 'DSB')
    return;
end
if isempty(payloadBlocks)
    return;
end
idx = find(strcmp({payloadBlocks.blockName}, 'BKN1') & ...
    strcmp({payloadBlocks.logicalChannelHint}, 'SCH/S'), 1);
if ~isempty(idx)
    if payloadValidEnough(payloadBlocks(idx), cfg)
        link.schS = tetra.decodeSchS(payloadBlocks(idx).bits, cfg);
        link.schSOk = link.schS.ok;
    end
end
idxH = find(strcmp({payloadBlocks.blockName}, 'BKN2') & ...
    strcmp({payloadBlocks.logicalChannelHint}, 'SCH/H'), 1);
if ~isempty(idxH)
    if payloadValidEnough(payloadBlocks(idxH), cfg)
        link.schH = tetra.decodeDmoSignallingBlock(payloadBlocks(idxH).bits, ...
            'SCH/H', zeros(30, 1) ~= 0, cfg);
        link.schHOk = link.schH.ok;
    end
end
if isempty(link.schS) || isempty(link.schH) || ~link.schS.ok || ~link.schH.ok
    return;
end
link.dmacSync = tetra.parseDmacSync(link.schS.type1Bits, link.schH.type1Bits, cfg);
link.dmacSyncOk = link.dmacSync.ok;
link.dccBits = link.dmacSync.dccBits;
link.dccValid = link.dmacSync.dccValid;
link.dccText = link.dmacSync.dccText;
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

function [report, finalContext] = makeReport( ...
        candidates, defs, cfg, initialContext)
bursts = confirmedBursts(candidates);
bursts = assignTimingFromSchS(bursts, initialContext);
[bursts, finalContext] = ...
    decodeTrafficSignalling(bursts, cfg, initialContext);
payloadBlocks = collectPayloadBlocks(bursts);
macBlocks = collectMacBlocks(bursts);
report = struct();
report.candidates = candidates;
report.bursts = bursts;
report.payloadBlocks = payloadBlocks;
report.macBlocks = macBlocks;
report.candidateCount = numel(candidates);
report.completeCount = countField(candidates, 'isComplete');
report.confirmedCount = numel(bursts);
report.goodCount = numel(bursts);
report.dsbCount = nnz(strcmp({bursts.burstType}, 'DSB'));
report.dnbCount = nnz(strcmp({bursts.burstType}, 'DNB'));
report.payloadBlockCount = numel(payloadBlocks);
report.macBlockCount = numel(macBlocks);
report.schSDecodedCount = countField(bursts, 'schSOk');
report.schHDecodedCount = countField(bursts, 'schHOk');
report.dmacSyncDecodedCount = countField(bursts, 'dmacSyncOk');
report.dccContextCount = countField(bursts, 'dccValid');
report.stchDecodedCount = sumNumericField(bursts, 'stchDecodedCount');
report.schFDecodedCount = countField(bursts, 'schFOk');
report.macPduDecodedCount = countMacPdus(macBlocks);
report.timingAssignedCount = nnz(~isnan([bursts.frameNumber]) & ~isnan([bursts.slotNumber]));
report.definitions = defs;
report.finalContext = finalContext;
end

function bursts = assignTimingFromSchS(bursts, initialContext)
if isempty(bursts)
    return;
end
refMask = [bursts.schSOk] & ~isnan([bursts.frameNumber]) & ~isnan([bursts.slotNumber]);
refs = bursts(refMask);
refStarts = [refs.slotStartBit];
refFrames = [refs.frameNumber];
refSlots = [refs.slotNumber];
if validTimingContext(initialContext)
    refStarts = [double(initialContext.slotStartBit), refStarts];
    refFrames = [double(initialContext.frameNumber), refFrames];
    refSlots = [double(initialContext.slotNumber), refSlots];
end
if isempty(refStarts)
    return;
end
slotBits = bursts(1).slotBits;
for k = 1:numel(bursts)
    if bursts(k).schSOk
        continue;
    end
    deltas = round((bursts(k).slotStartBit - refStarts) ./ slotBits);
    [~, bestIdx] = min(abs(deltas));
    delta = deltas(bestIdx);
    [fn, tn] = advanceTiming( ...
        refFrames(bestIdx), refSlots(bestIdx), delta);
    bursts(k).frameNumber = fn;
    bursts(k).slotNumber = tn;
    bursts(k).timingLabel = sprintf('FN%d TN%d', fn, tn);
    bursts(k).timingSource = 'inferred_from_SCH/S';
    bursts(k).timingSlotDelta = delta;
end
end

function [bursts, context] = decodeTrafficSignalling( ...
        bursts, cfg, initialContext)
if isempty(initialContext)
    context = emptyDmoContext();
else
    context = initialContext;
end
if isempty(bursts)
    return;
end
for k = 1:numel(bursts)
    if bursts(k).dmacSyncOk && bursts(k).dccValid
        context = contextFromSync(bursts(k).dmacSync, bursts(k));
    end
    bursts(k).dmoContext = context;
    bursts(k).contextValid = context.valid;
    if ~strcmp(bursts(k).burstType, 'DNB')
        continue;
    end
    if strcmp(bursts(k).trainingName, 'normal_2')
        bursts(k) = decodeNormal2Stch(bursts(k), context, cfg);
    elseif strcmp(bursts(k).trainingName, 'normal_1')
        bursts(k) = decodeNormal1SchF(bursts(k), context, cfg);
    end
end
end

function yes = validTimingContext(context)
yes = isstruct(context) && isscalar(context) && ...
    isfield(context, 'valid') && logical(context.valid) && ...
    isfield(context, 'slotStartBit') && ...
    isfield(context, 'frameNumber') && ...
    isfield(context, 'slotNumber') && ...
    all(isfinite([double(context.slotStartBit), ...
        double(context.frameNumber), double(context.slotNumber)]));
end

function burst = decodeNormal2Stch(burst, context, cfg)
blocks = burst.payloadBlocks;
idx1 = find(strcmp({blocks.blockName}, 'BKN1'), 1);
if isempty(idx1)
    return;
end
stch1 = decodeMacBlockFromPayload(blocks(idx1), 'STCH', context, cfg);
stch1.frameNumber = burst.frameNumber;
stch1.slotNumber = burst.slotNumber;
burst.stchBlocks = appendStruct(burst.stchBlocks, stch1);
burst.macBlocks = appendStruct(burst.macBlocks, stch1);
if stch1.decodeOk
    burst.stchDecodedCount = burst.stchDecodedCount + 1;
end

decodeSecondHalf = stch1.decodeOk && isfield(stch1.pdu, 'secondHalfSlotStolenFlag') && ...
    stch1.pdu.secondHalfSlotStolenFlag;
idx2 = find(strcmp({blocks.blockName}, 'BKN2'), 1);
if isempty(idx2)
    return;
end
if decodeSecondHalf
    stch2 = decodeMacBlockFromPayload(blocks(idx2), 'STCH', context, cfg);
    stch2.frameNumber = burst.frameNumber;
    stch2.slotNumber = burst.slotNumber;
    burst.stchBlocks = appendStruct(burst.stchBlocks, stch2);
    burst.macBlocks = appendStruct(burst.macBlocks, stch2);
    if stch2.decodeOk
        burst.stchDecodedCount = burst.stchDecodedCount + 1;
    end
else
    tch = skippedMacBlockFromPayload(blocks(idx2), 'TCH', context, ...
        'BKN2 kept as TCH candidate; first-half STCH did not steal second half');
    tch.frameNumber = burst.frameNumber;
    tch.slotNumber = burst.slotNumber;
    burst.macBlocks = appendStruct(burst.macBlocks, tch);
end
end

function burst = decodeNormal1SchF(burst, context, cfg)
blocks = burst.payloadBlocks;
idx1 = find(strcmp({blocks.blockName}, 'BKN1'), 1);
idx2 = find(strcmp({blocks.blockName}, 'BKN2'), 1);
if isempty(idx1) || isempty(idx2)
    return;
end
bits = [blocks(idx1).bits(:); blocks(idx2).bits(:)];
meta = combinedBlockMeta(blocks(idx1), blocks(idx2));
schF = decodeMacBlock(meta, bits, 'SCH/F', context, cfg);
schF.frameNumber = burst.frameNumber;
schF.slotNumber = burst.slotNumber;
burst.schF = schF;
burst.schFOk = schF.decodeOk;
if schF.decodeOk
    burst.schFStatus = 'SCH/F decoded';
else
    burst.schFStatus = 'SCH/F failed or skipped; keep as TCH candidate';
end
burst.macBlocks = appendStruct(burst.macBlocks, schF);
end

function block = decodeMacBlockFromPayload(payloadBlock, logicalChannel, context, cfg)
block = decodeMacBlock(payloadBlock, payloadBlock.bits, logicalChannel, context, cfg);
end

function block = decodeMacBlock(meta, bits, logicalChannel, context, cfg)
block = macBlockFromMeta(meta, logicalChannel, context);
block.rawBitLength = numel(bits);
block.rawBitString = bitsToString(bits);
if ~payloadValidEnough(meta, cfg)
    block.status = sprintf('skipped: low burst-valid ratio %.3f', meta.validRatio);
    return;
end
if ~context.valid
    block.status = 'skipped: no DCC context';
    return;
end
block.decodeAttempted = true;
try
    decoded = tetra.decodeDmoSignallingBlock(bits, logicalChannel, context.dccBits, cfg);
    block.decoded = decoded;
    block.blockCodeErrors = decoded.blockCodeErrors;
    block.tailErrors = decoded.tailErrors;
    block.rcpcMetric = decoded.rcpcMetric;
    block.decodeOk = decoded.ok;
    if decoded.ok
        block.pdu = tetra.parseDmoMacPdu(decoded.type1Bits, logicalChannel, context);
        block.decodeOk = block.pdu.ok;
        block.status = 'decoded';
    else
        block.status = sprintf('channel decode failed: blockErr=%d tailErr=%d metric=%g', ...
            decoded.blockCodeErrors, decoded.tailErrors, decoded.rcpcMetric);
    end
catch err
    block.status = sprintf('decode error: %s', err.message);
end
end

function block = skippedMacBlockFromPayload(payloadBlock, logicalChannel, context, status)
block = macBlockFromMeta(payloadBlock, logicalChannel, context);
block.status = status;
block.rawBitLength = payloadBlock.length;
block.rawBitString = payloadBlock.bitString;
end

function block = macBlockFromMeta(meta, logicalChannel, context)
block = emptyMacBlock();
block.logicalChannel = logicalChannel;
block.blockName = meta.blockName;
block.blockIndex = meta.blockIndex;
block.burstType = meta.burstType;
block.trainingName = meta.trainingName;
block.slotStartBit = meta.slotStartBit;
block.startBitInSlot = meta.startBitInSlot;
block.endBitInSlot = meta.endBitInSlot;
block.absoluteStartBit = meta.absoluteStartBit;
block.absoluteEndBit = meta.absoluteEndBit;
block.validBitCount = fieldOr(meta, 'validBitCount', 0);
block.invalidBitCount = fieldOr(meta, 'invalidBitCount', 0);
block.validRatio = fieldOr(meta, 'validRatio', NaN);
block.frameNumber = context.frameNumber;
block.slotNumber = context.slotNumber;
block.contextValid = context.valid;
block.contextSourceSlotStartBit = context.slotStartBit;
block.contextMessageTypeText = context.messageTypeText;
end

function meta = combinedBlockMeta(block1, block2)
meta = block1;
meta.blockName = 'BKN1+BKN2';
meta.blockIndex = 12;
meta.logicalChannelHint = 'SCH/F or TCH';
meta.startBitInSlot = block1.startBitInSlot;
meta.endBitInSlot = block2.endBitInSlot;
meta.absoluteStartBit = block1.absoluteStartBit;
meta.absoluteEndBit = block2.absoluteEndBit;
meta.length = block1.length + block2.length;
meta.bits = [block1.bits(:); block2.bits(:)];
meta.validMask = [block1.validMask(:); block2.validMask(:)];
meta.validBitCount = block1.validBitCount + block2.validBitCount;
meta.invalidBitCount = block1.invalidBitCount + block2.invalidBitCount;
meta.validRatio = safeRatio(meta.validBitCount, meta.length);
meta.bitString = bitsToString(meta.bits);
end

function context = emptyDmoContext()
context = struct( ...
    'valid', false, ...
    'slotStartBit', NaN, ...
    'frameNumber', NaN, ...
    'slotNumber', NaN, ...
    'communicationType', NaN, ...
    'communicationTypeText', '', ...
    'abChannelUsage', NaN, ...
    'abChannelUsageText', '', ...
    'airInterfaceEncryptionState', NaN, ...
    'airInterfaceEncryptionStateText', '', ...
    'sourceAddress', NaN, ...
    'destinationAddress', NaN, ...
    'mobileNetworkIdentity', NaN, ...
    'messageType', NaN, ...
    'messageTypeText', '', ...
    'service', '', ...
    'dccBits', false(30, 1), ...
    'dccText', '');
end

function context = contextFromSync(sync, burst)
context = emptyDmoContext();
context.valid = sync.dccValid;
context.slotStartBit = burst.slotStartBit;
context.frameNumber = sync.frameNumber;
context.slotNumber = sync.slotNumber;
context.communicationType = sync.communicationType;
context.communicationTypeText = sync.communicationTypeText;
context.abChannelUsage = sync.abChannelUsage;
context.abChannelUsageText = sync.abChannelUsageText;
context.airInterfaceEncryptionState = sync.airInterfaceEncryptionState;
context.airInterfaceEncryptionStateText = sync.airInterfaceEncryptionStateText;
context.sourceAddress = sync.sourceAddress;
context.destinationAddress = sync.destinationAddress;
context.mobileNetworkIdentity = sync.mobileNetworkIdentity;
context.messageType = sync.messageType;
context.messageTypeText = sync.messageTypeText;
context.service = syncService(sync);
context.dccBits = sync.dccBits;
context.dccText = sync.dccText;
end

function text = syncService(sync)
text = '';
if isfield(sync, 'message') && isfield(sync.message, 'messageDependent')
    md = sync.message.messageDependent;
    if isfield(md, 'circuitModeTypeText')
        text = md.circuitModeTypeText;
    end
end
end

function block = emptyMacBlock()
block = struct( ...
    'logicalChannel', '', ...
    'blockName', '', ...
    'blockIndex', 0, ...
    'burstType', '', ...
    'trainingName', '', ...
    'slotStartBit', NaN, ...
    'startBitInSlot', 0, ...
    'endBitInSlot', 0, ...
    'absoluteStartBit', NaN, ...
    'absoluteEndBit', NaN, ...
    'frameNumber', NaN, ...
    'slotNumber', NaN, ...
    'contextValid', false, ...
    'contextSourceSlotStartBit', NaN, ...
    'contextMessageTypeText', '', ...
    'decodeAttempted', false, ...
    'decodeOk', false, ...
    'status', '', ...
    'blockCodeErrors', NaN, ...
    'tailErrors', NaN, ...
    'rcpcMetric', NaN, ...
    'decoded', struct([]), ...
    'pdu', struct([]), ...
    'rawBitLength', 0, ...
    'validBitCount', 0, ...
    'invalidBitCount', 0, ...
    'validRatio', NaN, ...
    'rawBitString', '');
end

function yes = payloadValidEnough(block, cfg)
ratio = fieldOr(block, 'validRatio', 1);
if isnan(ratio)
    ratio = 1;
end
yes = ratio >= getCfg(cfg, 'dmoPayloadMinValidRatio', 0);
end

function r = safeRatio(n, d)
if d <= 0
    r = NaN;
else
    r = double(n) / double(d);
end
end

function out = appendStruct(out, item)
if isempty(out)
    out = item;
else
    out(end+1, 1) = item;
end
end

function [frameNumber, slotNumber] = advanceTiming(refFrame, refSlot, slotDelta)
idx = (refFrame - 1) * 4 + (refSlot - 1);
idx = mod(idx + slotDelta, 72);
frameNumber = floor(idx / 4) + 1;
slotNumber = mod(idx, 4) + 1;
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

function macBlocks = collectMacBlocks(bursts)
macBlocks = struct([]);
for k = 1:numel(bursts)
    if ~isfield(bursts(k), 'macBlocks') || isempty(bursts(k).macBlocks)
        continue;
    end
    if isempty(macBlocks)
        macBlocks = bursts(k).macBlocks(:);
    else
        macBlocks = [macBlocks; bursts(k).macBlocks(:)]; %#ok<AGROW>
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

function n = sumNumericField(items, fieldName)
if isempty(items)
    n = 0;
else
    n = sum([items.(fieldName)]);
end
end

function n = countMacPdus(macBlocks)
n = 0;
for k = 1:numel(macBlocks)
    if macBlocks(k).decodeOk && ~isempty(macBlocks(k).pdu)
        n = n + 1;
    end
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

function value = fieldOr(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
