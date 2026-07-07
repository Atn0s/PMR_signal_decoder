function fig = plotOverview(iq, fs, previewIq, previewFs, frontend, result)
%PLOTOVERVIEW Draw frequency, time-frequency, frontend, and decision panels.
fig = figure('Name', 'Radio Decoder Analysis', 'Color', 'w');
layout = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(layout, 1);
[f, psd] = common.welchPsd(iq, fs, 4096);
plot(ax1, f ./ 1e3, 10 .* log10(psd + 1e-12), 'Color', [0.10 0.35 0.65], 'LineWidth', 0.7);
hold(ax1, 'on');
for k = 1:numel(result.candidatesHz)
    xline(ax1, result.candidatesHz(k) ./ 1e3, '--', 'Color', [0.80 0.20 0.10]);
end
grid(ax1, 'on');
title(ax1, 'Input Welch PSD');
xlabel(ax1, 'Baseband frequency (kHz)');
ylabel(ax1, 'PSD (dB)');

ax2 = nexttile(layout, 2);
[specT, specF, specDb] = localSpectrogram(iq, fs);
imagesc(ax2, specT, specF ./ 1e3, specDb);
axis(ax2, 'xy');
colormap(ax2, parula);
colorbar(ax2);
title(ax2, 'Input Time-Frequency');
xlabel(ax2, 'Time (s)');
ylabel(ax2, 'Frequency (kHz)');

ax3 = nexttile(layout, 3);
[nf, npsd] = common.welchPsd(previewIq, previewFs, 4096);
plot(ax3, nf ./ 1e3, 10 .* log10(npsd + 1e-12), 'Color', [0.25 0.25 0.25], 'LineWidth', 0.7);
grid(ax3, 'on');
title(ax3, sprintf('Narrowband Preview PSD (fo=%+.1fkHz)', result.previewFoHz / 1e3));
xlabel(ax3, 'Frequency (kHz)');
ylabel(ax3, 'PSD (dB)');

ax4 = nexttile(layout, 4);
if isempty(frontend)
    text(ax4, 0.5, 0.5, result.frontendError, ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');
    axis(ax4, 'off');
else
    m = min(numel(frontend), round(previewFs * 0.25));
    tMs = (0:m-1).' ./ previewFs .* 1e3;
    plot(ax4, tMs, frontend(1:m), 'Color', [0.10 0.45 0.20], 'LineWidth', 0.7);
    addLevelLines(ax4);
    grid(ax4, 'on');
    ylim(ax4, [-6 6]);
    title(ax4, 'FSK Discriminator / 4FSK Frontend');
    xlabel(ax4, 'Time (ms)');
    ylabel(ax4, 'Nominal level');
end

ax5 = nexttile(layout, 5);
if isempty(frontend)
    text(ax5, 0.5, 0.5, 'No frontend data for level decision.', ...
        'HorizontalAlignment', 'center', 'Interpreter', 'none');
    axis(ax5, 'off');
else
    plotLevelDecision(ax5, frontend, previewFs, result);
end

ax6 = nexttile(layout, 6);
axis(ax6, 'off');
lines = result.lines;
if isempty(lines)
    lines = {'No PDUs decoded.'};
end
maxLines = min(numel(lines), 18);
text(ax6, 0.0, 1.0, strjoin(lines(1:maxLines), newline), ...
    'VerticalAlignment', 'top', ...
    'HorizontalAlignment', 'left', ...
    'FontName', 'monospaced', ...
    'Interpreter', 'none');
title(ax6, sprintf('Decoded PDUs (%d)', numel(result.pdus)));
end

function [t, f, db] = localSpectrogram(x, fs)
x = x(:);
if isempty(x)
    t = 0;
    f = 0;
    db = 0;
    return;
end
maxSamples = min(numel(x), 500000);
x = x(1:maxSamples);
nfft = min(2048, max(256, 2 ^ floor(log2(numel(x)))));
if numel(x) < nfft
    x = [x; zeros(nfft - numel(x), 1)];
end
hop = max(1, floor(nfft / 4));
starts = 1:hop:(numel(x) - nfft + 1);
win = localHann(nfft);
db = zeros(nfft, numel(starts));
for k = 1:numel(starts)
    seg = x(starts(k):starts(k) + nfft - 1) .* win;
    p = abs(fftshift(fft(seg, nfft))) .^ 2;
    db(:, k) = 10 .* log10(p ./ max(sum(win .^ 2), eps) + 1e-12);
end
if mod(nfft, 2) == 0
    bins = (-nfft/2:nfft/2-1).';
else
    bins = (-(nfft-1)/2:(nfft-1)/2).';
end
f = bins .* (fs / nfft);
t = (starts - 1) ./ fs;
end

function w = localHann(n)
idx = (0:n-1).';
if n <= 1
    w = 1;
else
    w = 0.5 - 0.5 .* cos(2 .* pi .* idx ./ (n - 1));
end
end

function addLevelLines(ax)
yline(ax, 3, '--', 'Color', [0.75 0.10 0.10]);
yline(ax, 1, '--', 'Color', [0.85 0.45 0.00]);
yline(ax, -1, '--', 'Color', [0.85 0.45 0.00]);
yline(ax, -3, '--', 'Color', [0.75 0.10 0.10]);
end

function plotLevelDecision(ax, frontend, previewFs, result)
sps = protocolSps(result);
levels = [-3 -1 1 3];
[phase, sampled] = bestSymbolPhase(frontend, sps, levels);
decided = nearestLevels(sampled, levels);
n = min(numel(decided), 260);
symIndex = 0:n-1;
plot(ax, symIndex, sampled(1:n), '.', 'Color', [0.55 0.55 0.55], 'MarkerSize', 7);
hold(ax, 'on');
stairs(ax, symIndex, decided(1:n), 'Color', [0.05 0.30 0.75], 'LineWidth', 1.0);
scatter(ax, symIndex, decided(1:n), 14, decided(1:n), 'filled');
addLevelLines(ax);
grid(ax, 'on');
ylim(ax, [-4.2 4.2]);
title(ax, sprintf('4-Level Decisions (SPS=%d, phase=%d)', sps, phase));
xlabel(ax, 'Symbol index');
ylabel(ax, 'Decision level');

yyaxis(ax, 'right');
edges = [-4 -2 0 2 4];
counts = histcounts(decided, edges);
plot(ax, linspace(max(5, n - 60), n, numel(counts)), counts ./ max(counts), ...
    'Color', [0.15 0.15 0.15], 'LineStyle', ':', 'LineWidth', 1.0);
ylabel(ax, 'Level histogram (norm)');
yyaxis(ax, 'left');
end

function sps = protocolSps(result)
if isfield(result, 'protocols') && ~isempty(result.protocols)
    proto = lower(char(result.protocols{1}));
else
    proto = 'dmr';
end
if strcmp(proto, 'dpmr')
    sps = 20;
else
    sps = 10;
end
end

function [phase, sampled] = bestSymbolPhase(frontend, sps, levels)
y = frontend(:);
maxSamples = min(numel(y), 20000);
y = y(1:maxSamples);
bestErr = inf;
phase = 0;
sampled = y(1:sps:end);
for ph = 0:sps-1
    cand = y(ph + 1:sps:end);
    if isempty(cand)
        continue;
    end
    near = nearestLevels(cand, levels);
    err = median(abs(cand(:) - near(:)));
    if err < bestErr
        bestErr = err;
        phase = ph;
        sampled = cand;
    end
end
end

function out = nearestLevels(values, levels)
[~, idx] = min(abs(values(:) - levels), [], 2);
out = levels(idx).';
end
