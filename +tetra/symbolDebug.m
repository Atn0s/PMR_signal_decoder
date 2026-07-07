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
p.parse(varargin{:});

cfg = tetra.config();
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
    plotDecisionPreview(bestDecision, figOptions);
    plotTraining(bestTraining, variantReports, figOptions);
end

save(fullfile(outputDir, 'summary.mat'), 'result', 'cfg');
writeSummaryJson(result, fullfile(outputDir, 'summary.json'));
writeBits(bestDecision.bits, fullfile(outputDir, 'bits_preview.txt'));
end

function small = stripLargeFields(info)
small = rmfield(info, intersect(fieldnames(info), {'windowPowerDb', 'windowTimesSec'}));
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
plot(info.windowTimesSec, info.windowPowerDb, 'Color', [0.15 0.40 0.70]);
hold on;
yline(info.thresholdDb, '--', 'Threshold', 'Color', [0.80 0.20 0.10]);
xline(info.startSec, '--', 'Start', 'Color', [0.10 0.55 0.20]);
xline(info.endSec, '--', 'End', 'Color', [0.10 0.55 0.20]);
grid on;
title(sprintf('Active window: %s, active ratio %.3f', info.mode, info.activeRatio));
xlabel('Time (s)');
ylabel('1 ms power (dB)');
finishFig(fig, figOptions, '02_active_window.png');
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

function plotDecisionPreview(decision, figOptions)
fig = newFig('09 Decision Preview', figOptions);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
n = min(numel(decision.dibits), 260);
ax1 = nexttile(tl);
stem(ax1, 1:n, decision.dibits(1:n), '.', 'Color', [0.10 0.35 0.65]);
grid(ax1, 'on');
ylim(ax1, [-0.5 3.5]);
title(ax1, 'Dibit preview');
xlabel(ax1, 'Dibit index');
ylabel(ax1, 'Dibit value');
ax2 = nexttile(tl);
nb = min(numel(decision.bits), 520);
stairs(ax2, 1:nb, double(decision.bits(1:nb)), 'Color', [0.15 0.45 0.20]);
ylim(ax2, [-0.2 1.2]);
grid(ax2, 'on');
title(ax2, 'Hard bit preview');
xlabel(ax2, 'Bit index');
ylabel(ax2, 'Bit');
finishFig(fig, figOptions, '09_decision_preview.png');
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
