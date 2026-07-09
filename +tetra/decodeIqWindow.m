function [pdus, diag] = decodeIqWindow(iq, sampleRate, cfg, context)
%DECODEIQWINDOW Decode one already-selected TETRA IQ window.
if nargin < 3 || isempty(cfg)
    cfg = tetra.config();
end
if nargin < 4 || isempty(context)
    context = struct();
end

iq = iq(:);
if isempty(iq)
    pdus = struct([]);
    diag = emptyDiag(cfg);
    return;
end
iq = iq - mean(iq);

if nargin < 2 || isempty(sampleRate)
    sampleRate = cfg.frontendSampleRateHz;
end
if abs(sampleRate - cfg.frontendSampleRateHz) < 1e-6
    iq72 = iq;
    up = 1;
    down = 1;
else
    [iq72, up, down] = common.resampleTo(iq, sampleRate, cfg.frontendSampleRateHz);
end
fs72 = cfg.frontendSampleRateHz;

[coarseFoHz, coarseInfo] = tetra.coarseFrequencyOffset(iq72, fs72, cfg);
t = (0:numel(iq72)-1).' ./ fs72;
freqCorrected = iq72 .* exp(-1i * 2 * pi * coarseFoHz .* t);

h = tetra.rrcTaps(cfg.rrcAlpha, cfg.samplesPerSymbol, cfg.rrcSpanSymbols);
matched = conv(freqCorrected, h, 'same');
sync1 = tetra.timingSearch(matched, cfg);
residualHz = sync1.diffPhaseOffsetRad * cfg.symbolRateHz / (2 * pi);

if abs(residualHz) >= cfg.residualCorrectionMinHz && ...
        abs(residualHz) <= cfg.residualCorrectionMaxHz
    freqCorrected2 = freqCorrected .* exp(-1i * 2 * pi * residualHz .* t);
    matched2 = conv(freqCorrected2, h, 'same'); %#ok<NASGU>
    sync = tetra.timingSearch(matched2, cfg);
    usedResidualCorrection = true;
else
    sync = sync1;
    usedResidualCorrection = false;
end

seqs = tetra.trainingSequences();
[decision, training, variantReports] = bestDecisionVariant(sync, seqs, cfg);
slotReport = tetra.inferDmoBursts(decision.bits, training, seqs, cfg, decision.bitValidMask);

decodeContext = makeDecodeContext(context, iq72, fs72, coarseFoHz, ...
    residualHz, usedResidualCorrection, sync, decision, training);
pdus = tetra.pdusFromSlotReport(slotReport, cfg, decodeContext);
pdus = radio.normalizePdus(pdus);

diag = struct();
diag.inputSampleRateHz = sampleRate;
diag.targetSampleRateHz = fs72;
diag.resampleUp = up;
diag.resampleDown = down;
diag.inputSamples = numel(iq);
diag.resampledSamples = numel(iq72);
diag.coarseFrequencyOffsetHz = coarseFoHz;
diag.coarseFrequencyMethod = coarseInfo.method;
diag.residualCorrectionHz = residualHz;
diag.usedResidualCorrection = usedResidualCorrection;
diag.finalDiffPhaseOffsetRad = sync.diffPhaseOffsetRad;
diag.finalResidualHz = sync.diffPhaseOffsetRad * cfg.symbolRateHz / (2 * pi);
diag.timingPhaseSamples = sync.phaseSamples;
diag.timingErrorRad = sync.errorRad;
diag.symbolCount = numel(sync.symbols);
diag.bitCount = numel(decision.bits);
diag.validBitCount = nnz(decision.bitValidMask);
diag.validBitRatio = safeRatio(diag.validBitCount, diag.bitCount);
diag.decisionVariant = decision.variant;
diag.decisionPhaseOffsetRad = decision.phaseOffsetRad;
diag.training = training;
diag.variantReports = variantReports;
diag.slots = slotReport;
diag.context = decodeContext;
end

function diag = emptyDiag(cfg)
diag = struct();
diag.inputSampleRateHz = cfg.frontendSampleRateHz;
diag.targetSampleRateHz = cfg.frontendSampleRateHz;
diag.resampleUp = 1;
diag.resampleDown = 1;
diag.inputSamples = 0;
diag.resampledSamples = 0;
diag.coarseFrequencyOffsetHz = NaN;
diag.coarseFrequencyMethod = '';
diag.residualCorrectionHz = NaN;
diag.usedResidualCorrection = false;
diag.finalDiffPhaseOffsetRad = NaN;
diag.finalResidualHz = NaN;
diag.timingPhaseSamples = NaN;
diag.timingErrorRad = NaN;
diag.symbolCount = 0;
diag.bitCount = 0;
diag.decisionVariant = '';
diag.decisionPhaseOffsetRad = NaN;
diag.training = struct();
diag.variantReports = struct([]);
diag.slots = struct();
diag.context = struct();
end

function context = makeDecodeContext(base, iq72, fs72, coarseFoHz, residualHz, ...
        usedResidualCorrection, sync, decision, training)
context = base;
if ~isfield(context, 'activeStartSec')
    context.activeStartSec = 0;
end
if ~isfield(context, 'activeEndSec')
    context.activeEndSec = context.activeStartSec + max(0, numel(iq72) - 1) / fs72;
end
context.coarseFrequencyOffsetHz = coarseFoHz;
context.residualCorrectionHz = residualHz;
context.usedResidualCorrection = usedResidualCorrection;
context.timingPhaseSamples = sync.phaseSamples;
context.timingErrorRad = sync.errorRad;
context.decisionVariant = decision.variant;
context.decisionPhaseOffsetRad = decision.phaseOffsetRad;
context.symbolCount = numel(sync.symbols);
context.bitCount = numel(decision.bits);
context.validBitCount = nnz(decision.bitValidMask);
context.validBitRatio = safeRatio(context.validBitCount, context.bitCount);
context.trainingCandidateCount = training.candidateCount;
context.trainingGoodCount = training.goodCount;
end

function [bestDecision, bestTraining, variantReports] = bestDecisionVariant(sync, seqs, cfg)
variants = {'standard', 'conjugate', 'swap_bits', 'conjugate_swap'};
variantReports = repmat(struct( ...
    'variant', '', ...
    'score', 0, ...
    'goodCount', 0, ...
    'candidateCount', 0), 0, 1);
bestScore = -inf;
bestDecision = [];
bestTraining = [];
for k = 1:numel(variants)
    decision = tetra.pi4dqpskDecision(sync.symbols, ...
        'Variant', variants{k}, ...
        'PhaseOffsetStepRad', cfg.diffPhaseOffsetStepRad, ...
        'ValidTransitionMask', sync.validTransitionMask);
    training = tetra.findTrainingSequences(decision.bits, seqs, cfg);
    variantReports(end+1, 1) = struct( ... %#ok<AGROW>
        'variant', variants{k}, ...
        'score', training.score, ...
        'goodCount', training.goodCount, ...
        'candidateCount', training.candidateCount);
    score = training.score + 1000 * training.goodCount + 100 * training.candidateCount;
    if score > bestScore
        bestScore = score;
        bestDecision = decision;
        bestTraining = training;
    end
end
if isempty(bestDecision)
    bestDecision = tetra.pi4dqpskDecision(sync.symbols, ...
        'Variant', 'standard', ...
        'PhaseOffsetStepRad', cfg.diffPhaseOffsetStepRad, ...
        'ValidTransitionMask', sync.validTransitionMask);
    bestTraining = tetra.findTrainingSequences(bestDecision.bits, seqs, cfg);
end
end

function r = safeRatio(n, d)
if d <= 0
    r = NaN;
else
    r = double(n) / double(d);
end
end
