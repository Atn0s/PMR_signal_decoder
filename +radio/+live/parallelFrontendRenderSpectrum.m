function parallelFrontendRenderSpectrum(view, snapshot, selections)
%PARALLELFRONTENDRENDERSPECTRUM Draw the latest PSD and carrier markers.
if isempty(snapshot) || ~snapshot.hasEstimate, return; end
count = numel(snapshot.displayFrequencyHz);
factor = numel(snapshot.averagePsd) / count;
displayPsd = mean(reshape(snapshot.averagePsd, factor, count), 1).';
view.psdLine.XData = snapshot.displayFrequencyHz / 1e6;
view.psdLine.YData = 10 * log10(displayPsd + 1e-20);
xlim(view.axes, [snapshot.frequencyHz(1), ...
    snapshot.frequencyHz(end)] / 1e6);

if isempty(selections)
    view.markerLine.XData = NaN;
    view.markerLine.YData = NaN;
    return;
end
frequencies = [selections.refinedFrequencyHz];
powers = zeros(size(frequencies));
for selectionIndex = 1:numel(frequencies)
    [~, index] = min(abs( ...
        snapshot.frequencyHz - frequencies(selectionIndex)));
    powers(selectionIndex) = 10 * log10( ...
        snapshot.averagePsd(index) + 1e-20);
end
view.markerLine.XData = frequencies / 1e6;
view.markerLine.YData = powers;
end
