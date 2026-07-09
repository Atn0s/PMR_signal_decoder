function result = symbolDebug(path, varargin)
%SYMBOLDEBUG Visual first-stage TETRA pi/4-DQPSK symbol recovery experiment.
p = inputParser;
p.addParameter('SampleRate', []);
p.addParameter('IqDType', 'int16');
p.addParameter('OutputDir', '');
p.addParameter('CreateFigures', true);
p.addParameter('ShowFigures', true);
p.addParameter('SaveFigures', false);
p.addParameter('MaxInputSamplesForPlot', 600000);
p.addParameter('ActiveMaxSec', []);
p.addParameter('ActivePadSec', []);
p.addParameter('ActivePrePadSec', []);
p.addParameter('ActivePostPadSec', []);
p.parse(varargin{:});

cfg = tetra.config();
cfg = applyActiveWindowOverrides(cfg, p.Results);
projectRoot = fileparts(fileparts(mfilename('fullpath')));
if isempty(p.Results.OutputDir)
    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    outputDir = fullfile(projectRoot, 'outputs', 'tetra_symbol_debug', stamp);
else
    outputDir = char(p.Results.OutputDir);
end
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

iq = common.readRawIq(path, 'DType', p.Results.IqDType);
fs = p.Results.SampleRate;
if isempty(fs)
    fs = common.detectSampleRate(path);
end
if isempty(fs)
    error('tetra:symbolDebug:MissingSampleRate', ...
        'Sample rate is required; pass SampleRate or use WAV metadata.');
end
iq = iq(:);
iq = iq - mean(iq);

[iq72, up, down] = common.resampleTo(iq, fs, cfg.frontendSampleRateHz);
fs72 = cfg.frontendSampleRateHz;
[activeIq, activeInfo] = tetra.activeWindow(iq72, fs72, cfg);
[coarseFoHz, coarseInfo] = tetra.coarseFrequencyOffset(activeIq, fs72, cfg);
t = (0:numel(activeIq)-1).' ./ fs72;
freqCorrected = activeIq .* exp(-1i * 2 * pi * coarseFoHz .* t);

h = tetra.rrcTaps(cfg.rrcAlpha, cfg.samplesPerSymbol, cfg.rrcSpanSymbols);
matched = conv(freqCorrected, h, 'same');
sync1 = tetra.timingSearch(matched, cfg);
residualHz = sync1.diffPhaseOffsetRad * cfg.symbolRateHz / (2 * pi);

if abs(residualHz) >= cfg.residualCorrectionMinHz && ...
        abs(residualHz) <= cfg.residualCorrectionMaxHz
    freqCorrected2 = freqCorrected .* exp(-1i * 2 * pi * residualHz .* t);
    matched2 = conv(freqCorrected2, h, 'same');
    sync = tetra.timingSearch(matched2, cfg);
    usedResidualCorrection = true;
else
    freqCorrected2 = freqCorrected;
    matched2 = matched;
    sync = sync1;
    usedResidualCorrection = false;
end

seqs = tetra.trainingSequences();
variants = {'standard', 'conjugate', 'swap_bits', 'conjugate_swap'};
variantReports = repmat(struct( ...
    'variant', '', ...
    'score', 0, ...
    'goodCount', 0, ...
    'candidateCount', 0), 0, 1);
bestVariantScore = -inf;
bestDecision = [];
bestTraining = [];
for k = 1:numel(variants)
    decision = tetra.pi4dqpskDecision(sync.symbols, ...
        'Variant', variants{k}, ...
        'PhaseOffsetStepRad', cfg.diffPhaseOffsetStepRad, ...
        'ValidTransitionMask', sync.validTransitionMask);
    training = tetra.findTrainingSequences(decision.bits, seqs, cfg);
    variantReports(end+1) = struct( ...
        'variant', variants{k}, ...
        'score', training.score, ...
        'goodCount', training.goodCount, ...
        'candidateCount', training.candidateCount); %#ok<AGROW>
    rankScore = training.score + 1000 * training.goodCount + 100 * training.candidateCount;
    if rankScore > bestVariantScore
        bestVariantScore = rankScore;
        bestDecision = decision;
        bestTraining = training;
    end
end
if bestVariantScore <= 0
    bestDecision = tetra.pi4dqpskDecision(sync.symbols, ...
        'Variant', 'standard', ...
        'PhaseOffsetStepRad', cfg.diffPhaseOffsetStepRad, ...
        'ValidTransitionMask', sync.validTransitionMask);
    bestTraining = tetra.findTrainingSequences(bestDecision.bits, seqs, cfg);
end
slotReport = tetra.inferDmoBursts(bestDecision.bits, bestTraining, seqs, cfg);
freqCorrectionReport = makeFrequencyCorrectionReport(bestDecision, slotReport, cfg);

result = struct();
result.path = char(path);
result.outputDir = outputDir;
result.inputSampleRateHz = fs;
result.targetSampleRateHz = fs72;
result.resampleUp = up;
result.resampleDown = down;
result.inputSamples = numel(iq);
result.resampledSamples = numel(iq72);
result.activeInfo = stripLargeFields(activeInfo);
result.coarseFrequencyOffsetHz = coarseFoHz;
result.coarseFrequencyMethod = coarseInfo.method;
result.residualCorrectionHz = residualHz;
result.usedResidualCorrection = usedResidualCorrection;
result.finalDiffPhaseOffsetRad = sync.diffPhaseOffsetRad;
result.finalResidualHz = sync.diffPhaseOffsetRad * cfg.symbolRateHz / (2 * pi);
result.timingPhaseSamples = sync.phaseSamples;
result.timingErrorRad = sync.errorRad;
result.symbolCount = numel(sync.symbols);
result.bitCount = numel(bestDecision.bits);
result.decisionVariant = bestDecision.variant;
result.decisionPhaseOffsetRad = bestDecision.phaseOffsetRad;
result.training = bestTraining;
result.slots = slotReport;
result.frequencyCorrection = stripFrequencyCorrectionReport(freqCorrectionReport);
result.variantReports = variantReports;

if p.Results.CreateFigures
    figOptions = struct( ...
        'showFigures', logical(p.Results.ShowFigures), ...
        'saveFigures', logical(p.Results.SaveFigures), ...
        'outputDir', outputDir);
    plotInputOverview(iq, fs, figOptions, cfg, p.Results.MaxInputSamplesForPlot);
    plotActiveWindow(activeInfo, figOptions);
    plotFrequencyStages(activeIq, freqCorrected, freqCorrected2, fs72, coarseInfo, coarseFoHz, figOptions, cfg);
    plotRrc(h, fs72, figOptions, cfg);
    plotMatchedOutput(matched2, fs72, figOptions);
    plotTiming(sync, figOptions);
    plotSymbolConstellation(sync.symbols, figOptions);
    plotDiffConstellation(bestDecision, figOptions);
    plotDecisionPreview(bestDecision, slotReport, figOptions);
    plotTraining(bestTraining, variantReports, figOptions);
    plotSlotCandidates(slotReport, figOptions);
    plotFrequencyCorrection(freqCorrectionReport, figOptions);
    plotTransitionValidity(sync, bestDecision, slotReport, figOptions);
end

save(fullfile(outputDir, 'summary.mat'), 'result', 'cfg');
writeSummaryJson(result, fullfile(outputDir, 'summary.json'));
writeBits(bestDecision.bits, fullfile(outputDir, 'bits_preview.txt'));
writeSlotCandidates(slotReport, fullfile(outputDir, 'slots_preview.txt'));
writeDmoPayloads(slotReport, fullfile(outputDir, 'dmo_payload_preview.txt'));
writeSchS(slotReport, fullfile(outputDir, 'schs_preview.txt'));
writeDmoMac(slotReport, fullfile(outputDir, 'dmo_mac_preview.txt'));
writeFrequencyCorrection(freqCorrectionReport, fullfile(outputDir, 'frequency_correction_preview.txt'));
end

function cfg = applyActiveWindowOverrides(cfg, opts)
if ~isempty(opts.ActivePadSec)
    cfg.activePadSec = opts.ActivePadSec;
    cfg.activePrePadSec = opts.ActivePadSec;
    cfg.activePostPadSec = opts.ActivePadSec;
end
if ~isempty(opts.ActivePrePadSec)
    cfg.activePrePadSec = opts.ActivePrePadSec;
end
if ~isempty(opts.ActivePostPadSec)
    cfg.activePostPadSec = opts.ActivePostPadSec;
end
if ~isempty(opts.ActiveMaxSec)
    cfg.activeMaxSec = opts.ActiveMaxSec;
end
end

function small = stripLargeFields(info)
small = rmfield(info, intersect(fieldnames(info), {'windowPowerDb', 'windowTimesSec'}));
end

function small = stripFrequencyCorrectionReport(report)
small = rmfield(report, intersect(fieldnames(report), ...
    {'observedHzByBurst', 'expectedHzByBurst', 'errorHzByBurst'}));
end

function plotInputOverview(iq, fs, figOptions, cfg, maxSamples)
n = min(numel(iq), maxSamples);
x = iq(1:n);
fig = newFig('01 Input Overview', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
win = max(1, round(cfg.envelopeWindowSec * fs));
pow = movingPowerDb(x, win);
plot(ax1, (0:numel(pow)-1) .* win ./ fs, pow, 'Color', [0.10 0.35 0.65]);
grid(ax1, 'on');
title(ax1, 'Input envelope preview');
xlabel(ax1, 'Time (s)');
ylabel(ax1, 'Power (dB)');
ax2 = nexttile(tl);
[f, psd] = common.welchPsd(x, fs, min(4096, numel(x)));
plot(ax2, f ./ 1e3, 10 .* log10(psd + 1e-18), 'Color', [0.20 0.20 0.20]);
grid(ax2, 'on');
title(ax2, 'Input Welch PSD');
xlabel(ax2, 'Frequency (kHz)');
ylabel(ax2, 'PSD (dB)');
finishFig(fig, figOptions, '01_input_overview.png');
end

function plotActiveWindow(info, figOptions)
fig = newFig('02 Active Window', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
plotActiveWindowAxes(ax1, info);
title(ax1, sprintf('Active window: %s, active ratio %.3f', info.mode, info.activeRatio));
ax2 = nexttile(tl);
plotActiveWindowAxes(ax2, info);
span = max(info.endSec - info.startSec, 0);
pad = max(0.050, 0.15 * span);
xlim(ax2, [max(0, info.startSec - pad), info.endSec + pad]);
title(ax2, sprintf('Active window zoom, %.3f s span', span));
finishFig(fig, figOptions, '02_active_window.png');
end

function plotActiveWindowAxes(ax, info)
plot(ax, info.windowTimesSec, info.windowPowerDb, 'Color', [0.15 0.40 0.70]);
hold(ax, 'on');
yline(ax, info.thresholdDb, '--', 'Threshold', 'Color', [0.80 0.20 0.10]);
xline(ax, info.startSec, '--', 'Start', 'Color', [0.10 0.55 0.20]);
xline(ax, info.endSec, '--', 'End', 'Color', [0.10 0.55 0.20]);
grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, '1 ms power (dB)');
end

function plotFrequencyStages(activeIq, corrected1, corrected2, fs, coarseInfo, coarseFoHz, figOptions, cfg)
fig = newFig('03 Frequency Stages', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
plot(ax1, coarseInfo.frequencyHz ./ 1e3, 10 .* log10(coarseInfo.psd + 1e-18), 'Color', [0.25 0.25 0.25]);
hold(ax1, 'on');
xline(ax1, coarseFoHz ./ 1e3, '--', sprintf('fo %.1f Hz', coarseFoHz), 'Color', [0.80 0.20 0.10]);
xline(ax1, cfg.channelSearchHalfWidthHz ./ 1e3, ':', 'Color', [0.5 0.5 0.5]);
xline(ax1, -cfg.channelSearchHalfWidthHz ./ 1e3, ':', 'Color', [0.5 0.5 0.5]);
grid(ax1, 'on');
title(ax1, 'Active segment PSD and coarse offset');
xlabel(ax1, 'Frequency (kHz)');
ylabel(ax1, 'PSD (dB)');
ax2 = nexttile(tl);
[f0, p0] = common.welchPsd(activeIq, fs, min(4096, numel(activeIq)));
[f1, p1] = common.welchPsd(corrected1, fs, min(4096, numel(corrected1)));
[f2, p2] = common.welchPsd(corrected2, fs, min(4096, numel(corrected2)));
plot(ax2, f0 ./ 1e3, 10 .* log10(p0 + 1e-18), 'Color', [0.65 0.65 0.65]);
hold(ax2, 'on');
plot(ax2, f1 ./ 1e3, 10 .* log10(p1 + 1e-18), 'Color', [0.10 0.35 0.65]);
plot(ax2, f2 ./ 1e3, 10 .* log10(p2 + 1e-18), 'Color', [0.10 0.55 0.20]);
legend(ax2, {'selected', 'coarse corrected', 'residual corrected'}, 'Location', 'best');
grid(ax2, 'on');
title(ax2, 'Frequency correction stages');
xlabel(ax2, 'Frequency (kHz)');
ylabel(ax2, 'PSD (dB)');
finishFig(fig, figOptions, '03_frequency_stages.png');
end

function plotRrc(h, fs, figOptions, cfg)
fig = newFig('04 RRC Filter', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
n = ((0:numel(h)-1).' - floor(numel(h)/2)) ./ cfg.samplesPerSymbol;
plot(ax1, n, h, 'Color', [0.10 0.35 0.65]);
grid(ax1, 'on');
title(ax1, sprintf('RRC impulse response, alpha=%.2f', cfg.rrcAlpha));
xlabel(ax1, 'Symbols');
ylabel(ax1, 'Amplitude');
ax2 = nexttile(tl);
H = fftshift(abs(fft(h, 4096)));
freq = (-2048:2047).' .* fs / 4096;
plot(ax2, freq ./ 1e3, 20 .* log10(H ./ max(H) + 1e-6), 'Color', [0.25 0.25 0.25]);
grid(ax2, 'on');
ylim(ax2, [-80 5]);
title(ax2, 'RRC magnitude response');
xlabel(ax2, 'Frequency (kHz)');
ylabel(ax2, 'Magnitude (dB)');
finishFig(fig, figOptions, '04_rrc_filter.png');
end

function plotMatchedOutput(x, fs, figOptions)
fig = newFig('05 Matched Output', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
m = min(numel(x), round(0.030 * fs));
t = (0:m-1).' ./ fs .* 1e3;
ax1 = nexttile(tl);
plot(ax1, t, real(x(1:m)), 'Color', [0.10 0.35 0.65]);
hold(ax1, 'on');
plot(ax1, t, imag(x(1:m)), 'Color', [0.80 0.35 0.10]);
grid(ax1, 'on');
title(ax1, 'Matched filter output I/Q preview');
xlabel(ax1, 'Time (ms)');
ylabel(ax1, 'Amplitude');
legend(ax1, {'I', 'Q'});
ax2 = nexttile(tl);
plot(ax2, t, abs(x(1:m)), 'Color', [0.20 0.20 0.20]);
grid(ax2, 'on');
title(ax2, 'Matched filter output magnitude');
xlabel(ax2, 'Time (ms)');
ylabel(ax2, '|x|');
finishFig(fig, figOptions, '05_matched_output.png');
end

function plotTiming(sync, figOptions)
fig = newFig('06 Timing Metric', figOptions);
ph = [sync.metrics.phaseSamples];
err = [sync.metrics.errorRad];
valid = [sync.metrics.validTransitions];
yyaxis left;
plot(ph, err, '-o', 'Color', [0.10 0.35 0.65], 'MarkerSize', 4);
ylabel('Median differential phase error (rad)');
yyaxis right;
bar(ph, valid, 0.4, 'FaceColor', [0.75 0.75 0.75], 'EdgeColor', 'none');
ylabel('Valid transitions');
xline(sync.phaseSamples, '--', sprintf('best %.2f', sync.phaseSamples), 'Color', [0.80 0.20 0.10]);
grid on;
title('Timing phase search');
xlabel('Timing phase (samples at 72 kHz)');
finishFig(fig, figOptions, '06_timing_metric.png');
end

function plotSymbolConstellation(symbols, figOptions)
fig = newFig('07 Symbol Constellation', figOptions);
m = min(numel(symbols), 5000);
s = symbols(1:m);
odd = mod((1:m).', 2) == 1;
scatter(real(s(odd)), imag(s(odd)), 8, [0.10 0.35 0.65], 'filled', 'MarkerFaceAlpha', 0.35);
hold on;
scatter(real(s(~odd)), imag(s(~odd)), 8, [0.80 0.35 0.10], 'filled', 'MarkerFaceAlpha', 0.35);
axis equal;
grid on;
title('Sampled pi/4-DQPSK symbol constellation');
xlabel('I');
ylabel('Q');
legend({'odd symbols', 'even symbols'}, 'Location', 'best');
finishFig(fig, figOptions, '07_symbol_constellation.png');
end

function plotDiffConstellation(decision, figOptions)
fig = newFig('08 Differential Constellation', figOptions);
tl = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
m = min(numel(decision.diffPhaseCorrected), 6000);
d = decision.diffPhaseCorrected(1:m);
valid = decision.validTransitionMask(1:m);
ax1 = nexttile(tl);
scatter(ax1, cos(d(~valid)), sin(d(~valid)), 7, [0.72 0.72 0.72], ...
    'filled', 'MarkerFaceAlpha', 0.18);
hold(ax1, 'on');
scatter(ax1, cos(d(valid)), sin(d(valid)), 10, decision.symbolIndex(valid), ...
    'filled', 'MarkerFaceAlpha', 0.55);
axis(ax1, 'equal');
grid(ax1, 'on');
title(ax1, sprintf('Differential constellation (%s), valid highlighted', decision.variant));
xlabel(ax1, 'cos(dphi)');
ylabel(ax1, 'sin(dphi)');
ax2 = nexttile(tl);
histogram(ax2, d(~valid), 80, 'FaceColor', [0.78 0.78 0.78], 'EdgeColor', 'none');
hold(ax2, 'on');
histogram(ax2, d(valid), 80, 'FaceColor', [0.10 0.35 0.65], 'EdgeColor', 'none');
centers = [-3 -1 1 3] .* pi ./ 4;
for c = centers
    xline(ax2, c, '--', 'Color', [0.80 0.20 0.10]);
end
grid(ax2, 'on');
title(ax2, 'Corrected differential phase histogram');
xlabel(ax2, 'Phase (rad)');
ylabel(ax2, 'Count');
legend(ax2, {'ignored/low energy', 'timing-valid'}, 'Location', 'best');
finishFig(fig, figOptions, '08_diff_constellation.png');
end

function plotDecisionPreview(decision, slotReport, figOptions)
fig = newFig('09 Decision Preview', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
[startBit, label] = previewStartBit(slotReport);
startDibit = max(1, ceil(startBit / 2));
n = min(260, numel(decision.dibits) - startDibit + 1);
ax1 = nexttile(tl);
if n > 0
    idx = startDibit:(startDibit + n - 1);
    valid = decision.validTransitionMask(:);
    if numel(valid) ~= numel(decision.dibits)
        valid = true(size(decision.dibits(:)));
    end
    low = ~valid(idx);
    x = 2 .* idx - 1;
    if any(low)
        stem(ax1, x(low), decision.dibits(idx(low)), '.', ...
            'Color', [0.70 0.70 0.70]);
        hold(ax1, 'on');
    end
    stem(ax1, x(~low), decision.dibits(idx(~low)), '.', ...
        'Color', [0.10 0.35 0.65]);
end
grid(ax1, 'on');
ylim(ax1, [-0.5 3.5]);
title(ax1, sprintf('Dibit preview from %s', label), 'Interpreter', 'none');
xlabel(ax1, 'Recovered bit index (dibit start)');
ylabel(ax1, 'Dibit value');
ax2 = nexttile(tl);
nb = min(520, numel(decision.bits) - startBit + 1);
if nb > 0
    bitIdx = startBit:(startBit + nb - 1);
    stairs(ax2, bitIdx, double(decision.bits(bitIdx)), 'Color', [0.15 0.45 0.20]);
end
ylim(ax2, [-0.2 1.2]);
grid(ax2, 'on');
title(ax2, sprintf('Hard bit preview from %s', label), 'Interpreter', 'none');
xlabel(ax2, 'Recovered bit index');
ylabel(ax2, 'Bit');
finishFig(fig, figOptions, '09_decision_preview.png');
end

function [startBit, label] = previewStartBit(slotReport)
startBit = 1;
label = 'active-window start';
if ~isfield(slotReport, 'bursts') || isempty(slotReport.bursts)
    return;
end
b = slotReport.bursts(1);
startBit = max(1, b.slotStartBit);
timing = '';
if isfield(b, 'timingLabel') && ~isempty(b.timingLabel)
    timing = sprintf(' %s', b.timingLabel);
end
label = sprintf('first confirmed %s %s%s at bit %d', ...
    b.burstType, b.trainingName, timing, b.slotStartBit);
end

function plotTraining(training, variantReports, figOptions)
fig = newFig('10 Training Sequence Check', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
items = training.items;
names = {items.name};
errors = [items.errorFraction];
ax1 = nexttile(tl);
bar(ax1, errors, 'FaceColor', [0.10 0.35 0.65]);
ylim(ax1, [0 1]);
grid(ax1, 'on');
set(ax1, 'XTick', 1:numel(names), 'XTickLabel', names, 'XTickLabelRotation', 20);
yline(ax1, 0.18, '--', 'good', 'Color', [0.10 0.55 0.20]);
yline(ax1, 0.25, '--', 'candidate', 'Color', [0.80 0.35 0.10]);
title(ax1, 'Best normalized Hamming distance per training sequence');
ylabel(ax1, 'Error fraction');
ax2 = nexttile(tl);
variantNames = {variantReports.variant};
scores = [variantReports.score];
bar(ax2, scores, 'FaceColor', [0.55 0.55 0.55]);
grid(ax2, 'on');
set(ax2, 'XTick', 1:numel(variantNames), 'XTickLabel', variantNames, 'XTickLabelRotation', 20);
title(ax2, 'Decision variant training score');
ylabel(ax2, 'Score');
finishFig(fig, figOptions, '10_training_sequence_check.png');
end

function plotSlotCandidates(slotReport, figOptions)
fig = newFig('11 DMO Burst Payloads', figOptions);
if isfield(slotReport, 'bursts')
    rows = slotReport.bursts;
else
    rows = slotReport.candidates;
end
if isempty(rows)
    text(0.5, 0.5, 'No confirmed DMO bursts', 'HorizontalAlignment', 'center');
    axis off;
    finishFig(fig, figOptions, '11_slot_candidates.png');
    return;
end

tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax1 = nexttile(tl);
plotBurstOverview(ax1, rows, slotReport);
ax2 = nexttile(tl);
plotBurstDetail(ax2, rows, slotReport);
finishFig(fig, figOptions, '11_slot_candidates.png');
end

function plotBurstOverview(ax, rows, slotReport)
hold(ax, 'on');
for k = 1:numel(rows)
    c = rows(k);
    y = burstLane(c);
    color = burstColor(c);
    line(ax, [c.slotStartBit c.slotEndBit], [y y], ...
        'LineWidth', 7, 'Color', color);
    plot(ax, c.trainingStartBit, y, 'o', ...
        'MarkerFaceColor', [0.85 0.25 0.10], ...
        'MarkerEdgeColor', 'none', ...
        'MarkerSize', 4);
end
grid(ax, 'on');
ylim(ax, [0.5 4.5]);
yticks(ax, 1:4);
yticklabels(ax, {'DNB normal_2', 'DNB normal_1', 'DNB other', 'DSB sync'});
xMin = min([rows.slotStartBit]);
xMax = max([rows.slotEndBit]);
pad = max(50, round(0.03 * max(xMax - xMin, 1)));
xlim(ax, [xMin - pad, xMax + pad]);
title(ax, sprintf('Confirmed DMO burst overview (%d confirmed, DSB=%d, DNB=%d)', ...
    slotReport.confirmedCount, slotReport.dsbCount, slotReport.dnbCount));
xlabel(ax, 'Recovered bit index');
ylabel(ax, 'Burst class');
end

function plotBurstDetail(ax, rows, slotReport)
hold(ax, 'on');
n = min(numel(rows), 28);
for k = 1:n
    c = rows(k);
    y = n - k + 1;
    baseColor = burstColor(c);
    line(ax, [c.slotStartBit c.slotEndBit], [y y], ...
        'LineWidth', 5, 'Color', [0.78 0.78 0.78]);
    drawPayloadLine(ax, c, y, c.bkn1StartBit, c.bkn1EndBit, baseColor);
    drawPayloadLine(ax, c, y, c.bkn2StartBit, c.bkn2EndBit, baseColor .* 0.75);
    plot(ax, c.trainingStartBit, y, 'o', ...
        'MarkerFaceColor', [0.85 0.25 0.10], ...
        'MarkerEdgeColor', 'none', ...
        'MarkerSize', 6);
    timingText = '';
    if isfield(c, 'timingLabel') && ~isempty(c.timingLabel)
        timingText = sprintf(' %s', c.timingLabel);
    end
    label = sprintf('%s %s%s start=%d err=%d/%d', ...
        c.burstType, c.trainingName, timingText, c.slotStartBit, ...
        c.totalErrors, c.totalCheckedBits);
    text(ax, c.slotEndBit + 15, y, label, ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 9, ...
        'Interpreter', 'none');
end
grid(ax, 'on');
ylim(ax, [0 n + 1]);
xMin = min([rows(1:n).slotStartBit]);
xMax = max([rows(1:n).slotEndBit]);
pad = max(50, round(0.05 * max(xMax - xMin, 1)));
xlim(ax, [xMin - pad, xMax + 10 * pad]);
yticks(ax, 1:n);
yticklabels(ax, flip(arrayfun(@(x) sprintf('#%02d', x), 1:n, 'UniformOutput', false)));
title(ax, sprintf('Detailed BKN blocks, first %d confirmed bursts (%d total)', ...
    n, slotReport.confirmedCount));
xlabel(ax, 'Recovered bit index');
ylabel(ax, 'Burst rank');
end

function y = burstLane(c)
if strcmp(c.burstType, 'DSB')
    y = 4;
elseif strcmp(c.burstType, 'DNB') && strcmp(c.trainingName, 'normal_2')
    y = 1;
elseif strcmp(c.burstType, 'DNB') && strcmp(c.trainingName, 'normal_1')
    y = 2;
else
    y = 3;
end
end

function color = burstColor(c)
color = [0.55 0.55 0.55];
if strcmp(c.burstType, 'DSB')
    color = [0.10 0.35 0.65];
elseif strcmp(c.burstType, 'DNB') && strcmp(c.trainingName, 'normal_1')
    color = [0.10 0.50 0.25];
elseif strcmp(c.burstType, 'DNB') && strcmp(c.trainingName, 'normal_2')
    color = [0.80 0.35 0.10];
end
end

function drawPayloadLine(ax, c, y, startInSlot, endInSlot, color)
if startInSlot <= 0 || endInSlot < startInSlot
    return;
end
x1 = c.slotStartBit + startInSlot - 1;
x2 = c.slotStartBit + endInSlot - 1;
line(ax, [x1 x2], [y y], 'LineWidth', 9, 'Color', color);
end

function report = makeFrequencyCorrectionReport(decision, slotReport, cfg)
fcStartBitInSlot = 49;
fcEndBitInSlot = 128;
freqBits = [ones(1, 8), zeros(1, 64), ones(1, 8)] ~= 0;
expectedPhase = expectedPhaseFromBits(freqBits);
expectedHz = expectedPhase .* cfg.symbolRateHz ./ (2 * pi);
nSymbols = numel(expectedHz);

bursts = slotReport.bursts;
if isempty(bursts)
    dsb = bursts;
else
    dsb = bursts(strcmp({bursts.burstType}, 'DSB') & [bursts.isConfirmed]);
end

observed = NaN(numel(dsb), nSymbols);
errors = NaN(numel(dsb), nSymbols);
labels = cell(numel(dsb), 1);
slotStarts = NaN(numel(dsb), 1);
for k = 1:numel(dsb)
    b = dsb(k);
    slotStarts(k) = b.slotStartBit;
    if isfield(b, 'timingLabel') && ~isempty(b.timingLabel)
        labels{k} = b.timingLabel;
    else
        labels{k} = sprintf('bit %d', b.slotStartBit);
    end
    absStartBit = b.slotStartBit + fcStartBitInSlot - 1;
    absEndBit = b.slotStartBit + fcEndBitInSlot - 1;
    if mod(absStartBit, 2) ~= 1 || mod(absEndBit, 2) ~= 0
        continue;
    end
    pairIdx = ((absStartBit + 1) / 2):(absEndBit / 2);
    if pairIdx(1) < 1 || pairIdx(end) > numel(decision.diffPhaseCorrected)
        continue;
    end
    obsPhase = decision.diffPhaseCorrected(pairIdx);
    observed(k, :) = obsPhase(:).' .* cfg.symbolRateHz ./ (2 * pi);
    errors(k, :) = wrapToPiLocal(obsPhase(:).' - expectedPhase(:).') .* cfg.symbolRateHz ./ (2 * pi);
end

report = struct();
report.frequencyStartBitInSlot = fcStartBitInSlot;
report.frequencyEndBitInSlot = fcEndBitInSlot;
report.fieldBits = freqBits(:);
report.expectedPhaseRad = expectedPhase(:);
report.expectedHz = expectedHz(:);
report.observedHzByBurst = observed;
report.expectedHzByBurst = repmat(expectedHz(:).', size(observed, 1), 1);
report.errorHzByBurst = errors;
report.burstLabels = labels;
report.slotStartBits = slotStarts;
report.burstCount = numel(dsb);
report.validBurstCount = nnz(all(~isnan(observed), 2));
report.medianAbsErrorHzByBurst = median(abs(errors), 2, 'omitnan');
report.maxAbsErrorHzByBurst = max(abs(errors), [], 2, 'omitnan');
report.overallMedianAbsErrorHz = median(abs(errors(:)), 'omitnan');
report.overallMaxAbsErrorHz = max(abs(errors(:)), [], 'omitnan');
end

function phase = expectedPhaseFromBits(bits)
pairs = reshape(bits(:), 2, []).';
phase = zeros(size(pairs, 1), 1);
for k = 1:size(pairs, 1)
    b1 = pairs(k, 1);
    b2 = pairs(k, 2);
    if b1 && b2
        phase(k) = -3 * pi / 4;
    elseif b1 && ~b2
        phase(k) = -pi / 4;
    elseif ~b1 && ~b2
        phase(k) = pi / 4;
    else
        phase(k) = 3 * pi / 4;
    end
end
end

function plotFrequencyCorrection(report, figOptions)
fig = newFig('12 Frequency Correction Check', figOptions);
if report.validBurstCount == 0
    text(0.5, 0.5, 'No DSB frequency-correction fields available', ...
        'HorizontalAlignment', 'center');
    axis off;
    finishFig(fig, figOptions, '12_frequency_correction_check.png');
    return;
end

validRows = find(all(~isnan(report.observedHzByBurst), 2));
firstRow = validRows(1);
sym = 1:numel(report.expectedHz);
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
stairs(ax1, sym, report.expectedHz, 'Color', [0.20 0.20 0.20], 'LineWidth', 1.8);
hold(ax1, 'on');
plot(ax1, sym, report.observedHzByBurst(firstRow, :), 'o-', ...
    'Color', [0.10 0.35 0.65], 'MarkerSize', 4);
grid(ax1, 'on');
ylim(ax1, [-8500 4000]);
yline(ax1, 2250, ':', 'Color', [0.10 0.55 0.20]);
yline(ax1, -6750, ':', 'Color', [0.80 0.25 0.10]);
title(ax1, sprintf('DSB frequency-correction field, %s', report.burstLabels{firstRow}), ...
    'Interpreter', 'none');
xlabel(ax1, 'Field symbol index');
ylabel(ax1, 'Frequency (Hz)');
legend(ax1, {'expected', 'observed'}, 'Location', 'best');

ax2 = nexttile(tl);
imagesc(ax2, sym, 1:numel(validRows), report.observedHzByBurst(validRows, :));
set(ax2, 'YDir', 'normal');
colormap(ax2, parula);
cb = colorbar(ax2);
cb.Label.String = 'Observed frequency (Hz)';
caxis(ax2, [-7500 3000]);
grid(ax2, 'on');
title(ax2, 'Observed frequency-correction pattern across confirmed DSBs');
xlabel(ax2, 'Field symbol index');
ylabel(ax2, 'DSB');
tickRows = thinnedTicks(numel(validRows), 18);
yticks(ax2, tickRows);
yticklabels(ax2, report.burstLabels(validRows(tickRows)));

ax3 = nexttile(tl);
bar(ax3, report.medianAbsErrorHzByBurst(validRows), ...
    'FaceColor', [0.10 0.45 0.35], 'EdgeColor', 'none');
grid(ax3, 'on');
title(ax3, sprintf('Frequency-correction median abs error, overall %.1f Hz', ...
    report.overallMedianAbsErrorHz));
xlabel(ax3, 'DSB');
ylabel(ax3, 'Median abs error (Hz)');
xticks(ax3, tickRows);
xticklabels(ax3, report.burstLabels(validRows(tickRows)));
xtickangle(ax3, 20);
finishFig(fig, figOptions, '12_frequency_correction_check.png');
end

function plotTransitionValidity(sync, decision, slotReport, figOptions)
fig = newFig('13 Transition Validity', figOptions);
if numel(sync.symbols) < 2 || isempty(decision.validTransitionMask)
    text(0.5, 0.5, 'No differential transition validity data available', ...
        'HorizontalAlignment', 'center');
    axis off;
    finishFig(fig, figOptions, '13_transition_validity.png');
    return;
end

n = min([numel(sync.symbols) - 1, numel(decision.validTransitionMask), ...
    numel(decision.dibits)]);
sym = sync.symbols(:);
amp = min(abs(sym(1:n)), abs(sym(2:n+1)));
valid = logical(decision.validTransitionMask(1:n));
x = 2 .* (1:n).' - 1;
bursts = plotRows(slotReport);
inside = transitionsInsideBursts(x, bursts);
insideRatio = ratioText(valid(inside));
outsideRatio = ratioText(valid(~inside));

tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl);
ampDb = 20 .* log10(amp ./ max(max(amp), eps) + 1e-6);
ylim(ax1, [-70 5]);
shadeBurstSpans(ax1, bursts, [-70 5]);
hold(ax1, 'on');
plot(ax1, x, ampDb, 'Color', [0.20 0.20 0.20], 'LineWidth', 0.7);
grid(ax1, 'on');
title(ax1, 'Differential-transition amplitude with confirmed burst spans');
xlabel(ax1, 'Recovered bit index');
ylabel(ax1, 'Relative amp (dB)');

ax2 = nexttile(tl);
ylim(ax2, [-0.15 1.15]);
shadeBurstSpans(ax2, bursts, [-0.15 1.15]);
hold(ax2, 'on');
stairs(ax2, x, double(valid), 'Color', [0.10 0.35 0.65], 'LineWidth', 0.8);
grid(ax2, 'on');
title(ax2, sprintf('Timing-valid mask, inside bursts %s, outside bursts %s', ...
    insideRatio, outsideRatio));
xlabel(ax2, 'Recovered bit index');
ylabel(ax2, 'Valid');
yticks(ax2, [0 1]);
yticklabels(ax2, {'low energy', 'valid'});

ax3 = nexttile(tl);
plotBurstValidityRatios(ax3, x, valid, bursts);
finishFig(fig, figOptions, '13_transition_validity.png');
end

function bursts = plotRows(slotReport)
if isfield(slotReport, 'bursts')
    bursts = slotReport.bursts;
elseif isfield(slotReport, 'candidates')
    bursts = slotReport.candidates;
else
    bursts = struct([]);
end
end

function inside = transitionsInsideBursts(x, bursts)
inside = false(size(x));
for k = 1:numel(bursts)
    inside = inside | (x >= bursts(k).slotStartBit & x <= bursts(k).slotEndBit);
end
end

function txt = ratioText(mask)
if isempty(mask)
    txt = 'n/a';
else
    txt = sprintf('%.1f%%', 100 * mean(mask));
end
end

function shadeBurstSpans(ax, bursts, yRange)
if isempty(bursts)
    return;
end
for k = 1:numel(bursts)
    b = bursts(k);
    color = burstColor(b);
    patch(ax, ...
        [b.slotStartBit b.slotEndBit b.slotEndBit b.slotStartBit], ...
        [yRange(1) yRange(1) yRange(2) yRange(2)], ...
        color, 'FaceAlpha', 0.06, 'EdgeColor', 'none');
end
end

function plotBurstValidityRatios(ax, x, valid, bursts)
if isempty(bursts)
    text(ax, 0.5, 0.5, 'No confirmed bursts to compare', ...
        'HorizontalAlignment', 'center');
    axis(ax, 'off');
    return;
end
hold(ax, 'on');
for k = 1:numel(bursts)
    b = bursts(k);
    mask = x >= b.slotStartBit & x <= b.slotEndBit;
    if any(mask)
        ratio = mean(valid(mask));
    else
        ratio = NaN;
    end
    plot(ax, b.slotStartBit, ratio, 'o', ...
        'MarkerFaceColor', burstColor(b), ...
        'MarkerEdgeColor', 'none', ...
        'MarkerSize', 6);
end
ylim(ax, [0 1.05]);
grid(ax, 'on');
title(ax, 'Timing-valid transition ratio per confirmed burst');
xlabel(ax, 'Burst start bit');
ylabel(ax, 'Valid ratio');
end

function ticks = thinnedTicks(n, maxTicks)
if n <= maxTicks
    ticks = 1:n;
    return;
end
step = ceil(n / maxTicks);
ticks = 1:step:n;
if ticks(end) ~= n
    ticks = [ticks n];
end
end

function p = movingPowerDb(x, win)
nWin = floor(numel(x) / win);
if nWin < 1
    p = 10 .* log10(abs(x(:)) .^ 2 + 1e-12);
    return;
end
y = reshape(x(1:nWin * win), win, nWin);
p = 10 .* log10(mean(abs(y) .^ 2, 1).' + 1e-12);
end

function fig = newFig(name, figOptions)
visible = 'off';
if figOptions.showFigures
    visible = 'on';
end
fig = figure('Name', name, 'Color', 'w', 'Visible', visible, ...
    'Position', [100 100 1100 760]);
end

function finishFig(fig, figOptions, filename)
if figOptions.saveFigures
    path = fullfile(figOptions.outputDir, filename);
    try
        exportgraphics(fig, path, 'Resolution', 150);
    catch
        saveas(fig, path);
    end
end
if figOptions.showFigures
    drawnow;
else
    close(fig);
end
end

function writeSummaryJson(result, path)
jsonResult = result;
if isfield(jsonResult, 'training')
    jsonResult.training = rmfield(jsonResult.training, 'items');
    jsonResult.trainingItems = result.training.items;
end
try
    txt = jsonencode(jsonResult, 'PrettyPrint', true);
catch
    txt = jsonencode(jsonResult);
end
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WriteJson', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s', txt);
end

function writeBits(bits, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WriteBits', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
n = min(numel(bits), 2000);
for k = 1:n
    fprintf(fid, '%d', bits(k));
    if mod(k, 100) == 0
        fprintf(fid, '\n');
    end
end
fprintf(fid, '\n');
end

function writeSlotCandidates(slotReport, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WriteSlots', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
cands = slotReport.candidates;
fprintf(fid, 'TETRA DMO burst candidates inferred from training sequences\n');
fprintf(fid, 'candidates=%d complete=%d confirmed=%d DSB=%d DNB=%d payloadBlocks=%d macBlocks=%d schSDecoded=%d schHDecoded=%d dmacSync=%d stchDecoded=%d schFDecoded=%d timingAssigned=%d\n\n', ...
    slotReport.candidateCount, slotReport.completeCount, slotReport.confirmedCount, ...
    slotReport.dsbCount, slotReport.dnbCount, slotReport.payloadBlockCount, ...
    slotReport.macBlockCount, slotReport.schSDecodedCount, slotReport.schHDecodedCount, ...
    slotReport.dmacSyncDecodedCount, slotReport.stchDecodedCount, ...
    slotReport.schFDecodedCount, slotReport.timingAssignedCount);
for k = 1:numel(cands)
    c = cands(k);
    fprintf(fid, '#%02d %s %s slot=%d:%d complete=%d confirmed=%d aligned=%d trainingStart=%d inSlot=%d hitErr=%d/%d fieldErr=%d/%d frac=%.3f\n', ...
        k, c.burstType, c.trainingName, c.slotStartBit, c.slotEndBit, ...
        c.isComplete, c.isConfirmed, c.symbolAligned, c.trainingStartBit, ...
        c.trainingStartBitInSlot, c.trainingHitErrors, c.trainingLength, ...
        c.totalErrors, c.totalCheckedBits, c.errorFraction);
    fprintf(fid, 'fields: preamble=%d/%d training=%d/%d freq=%d/%d tail=%d\n', ...
        c.preambleErrors, c.preambleLength, c.trainingErrors, c.trainingLength, ...
        c.frequencyErrors, c.frequencyLength, c.tailErrors);
    if c.isConfirmed
        fprintf(fid, 'payload: BKN1 slot=%d:%d channel=%s, BKN2 slot=%d:%d channel=%s\n', ...
            c.bkn1StartBit, c.bkn1EndBit, c.bkn1LogicalChannel, ...
            c.bkn2StartBit, c.bkn2EndBit, c.bkn2LogicalChannel);
        if isfield(c, 'schSOk') && ~isempty(c.schS)
            fprintf(fid, 'schs: ok=%d FN=%g TN=%g blockErr=%d tailErr=%d rcpcMetric=%g type=%s comm=%s ab=%s\n', ...
                c.schS.ok, c.schS.frameNumber, c.schS.slotNumber, ...
                c.schS.blockCodeErrors, c.schS.tailErrors, c.schS.rcpcMetric, ...
                c.schS.pdu.syncPduTypeText, c.schS.communicationTypeText, ...
                c.schS.abChannelUsageText);
        end
        if isfield(c, 'schHOk') && ~isempty(c.schH)
            fprintf(fid, 'schh: ok=%d blockErr=%d tailErr=%d rcpcMetric=%g\n', ...
                c.schH.ok, c.schH.blockCodeErrors, c.schH.tailErrors, c.schH.rcpcMetric);
        end
        if isfield(c, 'dmacSyncOk') && ~isempty(c.dmacSync)
            fprintf(fid, 'sync: ok=%d msg=%s src=%s dst=%s mni=%s fc=%s dccValid=%d dcc=%s\n', ...
                c.dmacSync.ok, c.dmacSync.messageTypeText, ...
                intText(c.dmacSync.sourceAddress), intText(c.dmacSync.destinationAddress), ...
                intText(c.dmacSync.mobileNetworkIdentity), c.dmacSync.frameCountdownText, ...
                c.dmacSync.dccValid, c.dmacSync.dccText);
        end
    end
    if c.isComplete
        fprintf(fid, 'bits:\n');
        writeWrappedString(fid, c.bitString, 102);
        fprintf(fid, 'dibits:\n');
        writeWrappedString(fid, c.dibitString, 102);
    end
    fprintf(fid, '\n');
end
end

function writeSchS(slotReport, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WriteSchS', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'TETRA DMO synchronization decode preview\n');
fprintf(fid, 'confirmedBursts=%d schSDecoded=%d schHDecoded=%d dmacSync=%d dccContexts=%d\n\n', ...
    slotReport.confirmedCount, slotReport.schSDecodedCount, ...
    slotReport.schHDecodedCount, slotReport.dmacSyncDecodedCount, ...
    slotReport.dccContextCount);
for k = 1:numel(slotReport.bursts)
    b = slotReport.bursts(k);
    if ~isfield(b, 'schS') || isempty(b.schS)
        continue;
    end
    s = b.schS;
    fprintf(fid, '#%02d slot=%d:%d ok=%d FN=%g TN=%g blockErr=%d tailErr=%d rcpcMetric=%g\n', ...
        k, b.slotStartBit, b.slotEndBit, s.ok, s.frameNumber, s.slotNumber, ...
        s.blockCodeErrors, s.tailErrors, s.rcpcMetric);
    fprintf(fid, '  system=%s syncType=%s comm=%s ab=%s encryption=%s\n', ...
        s.pdu.systemCodeText, s.pdu.syncPduTypeText, ...
        s.pdu.communicationTypeText, s.pdu.abChannelUsageText, ...
        s.pdu.airInterfaceEncryptionStateText);
    if isfield(b, 'schH') && ~isempty(b.schH)
        fprintf(fid, '  schh ok=%d blockErr=%d tailErr=%d rcpcMetric=%g\n', ...
            b.schH.ok, b.schH.blockCodeErrors, b.schH.tailErrors, b.schH.rcpcMetric);
    end
    if isfield(b, 'dmacSync') && ~isempty(b.dmacSync)
        y = b.dmacSync;
        fprintf(fid, '  dmac-sync ok=%d msg=%s frameCountdown=%s src=%s dst=%s mni=%s dccValid=%d dcc=%s\n', ...
            y.ok, y.messageTypeText, y.frameCountdownText, ...
            intText(y.sourceAddress), intText(y.destinationAddress), ...
            intText(y.mobileNetworkIdentity), y.dccValid, y.dccText);
        fprintf(fid, '  addressTypes: src=%s dst=%s fill=%d frag=%d numSchF=%s\n', ...
            y.sourceAddressTypeText, y.destinationAddressTypeText, ...
            y.fillBitIndication, y.fragmentationFlag, intText(y.numberOfSchFSlots));
        if isfield(y.message, 'messageDependent')
            fprintf(fid, '  messageDependent=%s dmSdu=%s\n', ...
                compactJson(y.message.messageDependent), compactJson(y.message.dmSdu));
        end
    end
    fprintf(fid, '  bits=');
    writeWrappedString(fid, char('0' + double(s.type1Bits(:).')), 120);
    fprintf(fid, '\n');
end
end

function writeDmoMac(slotReport, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WriteDmoMac', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'TETRA DMO MAC/control decode preview\n');
fprintf(fid, 'confirmed=%d DSB=%d DNB=%d macBlocks=%d macPdus=%d stchDecoded=%d schFDecoded=%d\n\n', ...
    slotReport.confirmedCount, slotReport.dsbCount, slotReport.dnbCount, ...
    slotReport.macBlockCount, slotReport.macPduDecodedCount, ...
    slotReport.stchDecodedCount, slotReport.schFDecodedCount);

for k = 1:numel(slotReport.bursts)
    b = slotReport.bursts(k);
    timing = timingText(b);
    fprintf(fid, '#%02d %s %-8s %s bit=%d:%d\n', ...
        k, timing, b.burstType, b.trainingName, b.slotStartBit, b.slotEndBit);
    if strcmp(b.burstType, 'DSB') && isfield(b, 'dmacSync') && ~isempty(b.dmacSync)
        s = b.dmacSync;
        fprintf(fid, '  DSB/SYNC ok=%d msg=%s comm=%s ab=%s enc=%s src=%s dst=%s mni=%s fc=%s dccValid=%d\n', ...
            s.ok, s.messageTypeText, s.communicationTypeText, s.abChannelUsageText, ...
            s.airInterfaceEncryptionStateText, intText(s.sourceAddress), ...
            intText(s.destinationAddress), intText(s.mobileNetworkIdentity), ...
            s.frameCountdownText, s.dccValid);
        fprintf(fid, '  DCC=%s\n', s.dccText);
        fprintf(fid, '  messageDependent=%s dmSdu=%s\n', ...
            compactJson(s.message.messageDependent), compactJson(s.message.dmSdu));
    end
    if isfield(b, 'macBlocks') && ~isempty(b.macBlocks)
        for m = 1:numel(b.macBlocks)
            mb = b.macBlocks(m);
            fprintf(fid, '  %s %-9s %-9s attempted=%d ok=%d status=%s ctx=%s\n', ...
                mb.blockName, mb.logicalChannel, mb.trainingName, ...
                mb.decodeAttempted, mb.decodeOk, mb.status, contextText(mb));
            if ~isempty(mb.decoded)
                fprintf(fid, '    channel: blockErr=%s tailErr=%s rcpcMetric=%s\n', ...
                    intText(mb.blockCodeErrors), intText(mb.tailErrors), numText(mb.rcpcMetric));
            end
            if ~isempty(mb.pdu)
                fprintf(fid, '    pdu=%s', fieldText(mb.pdu, 'pduName'));
                if isfield(mb.pdu, 'messageTypeText')
                    fprintf(fid, ' msg=%s', mb.pdu.messageTypeText);
                end
                if isfield(mb.pdu, 'secondHalfSlotStolenFlag')
                    fprintf(fid, ' secondHalfStolen=%d', mb.pdu.secondHalfSlotStolenFlag);
                end
                if isfield(mb.pdu, 'nullPduFlag')
                    fprintf(fid, ' null=%d', mb.pdu.nullPduFlag);
                end
                fprintf(fid, '\n');
                if isfield(mb.pdu, 'sourceAddress')
                    fprintf(fid, '    addr: src=%s dst=%s mni=%s fc=%s enc=%s\n', ...
                        intText(mb.pdu.sourceAddress), intText(mb.pdu.destinationAddress), ...
                        intText(mb.pdu.mobileNetworkIdentity), ...
                        fieldText(mb.pdu, 'frameCountdownText'), ...
                        fieldText(mb.pdu, 'airInterfaceEncryptionStateText'));
                end
                if isfield(mb.pdu, 'message')
                    fprintf(fid, '    messageDependent=%s dmSdu=%s\n', ...
                        compactJson(mb.pdu.message.messageDependent), ...
                        compactJson(mb.pdu.message.dmSdu));
                elseif isfield(mb.pdu, 'uPlaneDmSduBitCount')
                    fprintf(fid, '    uPlaneDmSduBits=%d\n', mb.pdu.uPlaneDmSduBitCount);
                elseif isfield(mb.pdu, 'dmSduBitCount')
                    fprintf(fid, '    dmSduBits=%d\n', mb.pdu.dmSduBitCount);
                end
            end
        end
    end
    fprintf(fid, '\n');
end
end

function writeFrequencyCorrection(report, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WriteFrequencyCorrection', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'TETRA DSB frequency-correction verification\n');
fprintf(fid, 'field slot bits=%d:%d bursts=%d valid=%d overallMedianAbsErrorHz=%.2f overallMaxAbsErrorHz=%.2f\n\n', ...
    report.frequencyStartBitInSlot, report.frequencyEndBitInSlot, ...
    report.burstCount, report.validBurstCount, ...
    report.overallMedianAbsErrorHz, report.overallMaxAbsErrorHz);
fprintf(fid, 'expectedHz:\n');
fprintf(fid, '%8.1f', report.expectedHz);
fprintf(fid, '\n\n');
for k = 1:report.burstCount
    fprintf(fid, '#%02d %-10s slotStart=%g medianAbsErrorHz=%.2f maxAbsErrorHz=%.2f\n', ...
        k, report.burstLabels{k}, report.slotStartBits(k), ...
        report.medianAbsErrorHzByBurst(k), report.maxAbsErrorHzByBurst(k));
    if k <= size(report.observedHzByBurst, 1)
        fprintf(fid, 'observedHz:\n');
        fprintf(fid, '%8.1f', report.observedHzByBurst(k, :));
        fprintf(fid, '\nerrorHz:\n');
        fprintf(fid, '%8.1f', report.errorHzByBurst(k, :));
        fprintf(fid, '\n');
    end
end
end

function writeDmoPayloads(slotReport, path)
fid = fopen(path, 'w');
if fid < 0
    error('tetra:symbolDebug:WritePayloads', 'Unable to write %s', path);
end
cleaner = onCleanup(@() fclose(fid));
blocks = slotReport.payloadBlocks;
fprintf(fid, 'TETRA DMO extracted BKN payload blocks\n');
fprintf(fid, 'confirmedBursts=%d payloadBlocks=%d\n\n', ...
    slotReport.confirmedCount, slotReport.payloadBlockCount);
for k = 1:numel(blocks)
    b = blocks(k);
    fprintf(fid, '#%02d %s %s %s slotStart=%d abs=%d:%d inSlot=%d:%d len=%d channel=%s\n', ...
        k, b.burstType, b.trainingName, b.blockName, b.slotStartBit, ...
        b.absoluteStartBit, b.absoluteEndBit, b.startBitInSlot, b.endBitInSlot, ...
        b.length, b.logicalChannelHint);
    writeWrappedString(fid, b.bitString, 108);
    fprintf(fid, '\n');
end
end

function y = wrapToPiLocal(x)
y = mod(x + pi, 2 * pi) - pi;
end

function txt = timingText(burst)
if isfield(burst, 'timingLabel') && ~isempty(burst.timingLabel)
    txt = burst.timingLabel;
elseif isfield(burst, 'frameNumber') && ~isnan(burst.frameNumber)
    txt = sprintf('FN%d TN%d', burst.frameNumber, burst.slotNumber);
else
    txt = 'FN? TN?';
end
end

function txt = contextText(block)
if ~isfield(block, 'contextValid') || ~block.contextValid
    txt = 'no-DCC';
else
    txt = sprintf('DCC from bit %s/%s', ...
        intText(block.contextSourceSlotStartBit), block.contextMessageTypeText);
end
end

function txt = intText(value)
if islogical(value)
    value = double(value);
end
if isempty(value) || (isnumeric(value) && any(isnan(value(:))))
    txt = 'n/a';
elseif isnumeric(value) && isscalar(value)
    txt = sprintf('%.0f', value);
else
    txt = char('0' + double(value(:).'));
end
end

function txt = numText(value)
if isempty(value) || isnan(value)
    txt = 'n/a';
else
    txt = sprintf('%g', value);
end
end

function txt = fieldText(s, name)
if isstruct(s) && isfield(s, name)
    value = s.(name);
    if ischar(value) || isstring(value)
        txt = char(value);
    else
        txt = intText(value);
    end
else
    txt = 'n/a';
end
end

function txt = compactJson(value)
try
    txt = jsonencode(value);
catch
    txt = '<unprintable>';
end
if numel(txt) > 240
    txt = [txt(1:237) '...'];
end
end

function writeWrappedString(fid, txt, width)
for startIdx = 1:width:numel(txt)
    stopIdx = min(numel(txt), startIdx + width - 1);
    fprintf(fid, '%s\n', txt(startIdx:stopIdx));
end
end
