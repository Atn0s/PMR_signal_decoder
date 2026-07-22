function view = parallelFrontendCreateView(visible, sampleRate, centerHz, callbacks)
%PARALLELFRONTENDCREATEVIEW Build the parallel frontend's passive UI.
fig = uifigure('Name', 'PMR Parallel Live Frontend', ...
    'Position', [100 80 1320 760], 'Visible', char(visible));
root = uigridlayout(fig, [3 2]);
root.RowHeight = {72, '1x', 190};
root.ColumnWidth = {'3x', '1x'};
root.Padding = [8 8 8 8];

controls = uigridlayout(root, [2 10]);
controls.Layout.Row = 1;
controls.Layout.Column = [1 2];
controls.RowHeight = {28, 28};
controls.ColumnWidth = {42, '1x', 68, 76, 76, 72, 72, 64, 80, 110};
placeLabel(controls, 'File', 1, 1);
pathField = uieditfield(controls, 'text');
pathField.Layout.Row = 1; pathField.Layout.Column = [2 8];
browseButton = uibutton(controls, 'Text', 'Browse', ...
    'ButtonPushedFcn', callbacks.browse);
browseButton.Layout.Row = 1; browseButton.Layout.Column = 9;
previewButton = uibutton(controls, 'Text', 'Preview 1x', ...
    'ButtonPushedFcn', callbacks.preview);
previewButton.Layout.Row = 1; previewButton.Layout.Column = 10;

placeLabel(controls, 'Fs', 2, 1);
fsField = uieditfield(controls, 'numeric', 'Limits', [0 Inf], ...
    'Value', sampleRate);
fsField.Layout.Row = 2; fsField.Layout.Column = 2;
placeLabel(controls, 'Center', 2, 3);
centerField = uieditfield(controls, 'numeric', 'Value', centerHz);
centerField.Layout.Row = 2; centerField.Layout.Column = 4;
clearButton = uibutton(controls, 'Text', 'Clear carriers', ...
    'ButtonPushedFcn', callbacks.clear);
clearButton.Layout.Row = 2; clearButton.Layout.Column = 5;
runButton = uibutton(controls, 'Text', 'Run decode', 'Enable', 'off', ...
    'ButtonPushedFcn', callbacks.run);
runButton.Layout.Row = 2; runButton.Layout.Column = 6;
stopButton = uibutton(controls, 'Text', 'Stop', ...
    'ButtonPushedFcn', callbacks.stop);
stopButton.Layout.Row = 2; stopButton.Layout.Column = 7;
placeLabel(controls, 'BW', 2, 8);
bwDrop = uidropdown(controls, 'Items', ...
    {'6.25 kHz','12.5 kHz','25 kHz'}, ...
    'ItemsData', [6250 12500 25000], 'Value', 12500);
bwDrop.Layout.Row = 2; bwDrop.Layout.Column = 9;
metadataLabel = uilabel(controls, 'Text', 'No capture');
metadataLabel.Layout.Row = 2; metadataLabel.Layout.Column = 10;

ax = uiaxes(root);
ax.Layout.Row = 2; ax.Layout.Column = 1;
ax.Title.String = 'Live PSD — click peaks to add carrier paths';
ax.XLabel.String = 'Frequency / offset (MHz)';
ax.YLabel.String = 'PSD (dB/Hz)';
grid(ax, 'on'); hold(ax, 'on');
psdLine = plot(ax, NaN, NaN, 'Color', [0.10 0.45 0.90], ...
    'LineWidth', 1, 'HitTest', 'off');
markerLine = plot(ax, NaN, NaN, 'v', 'LineStyle', 'none', ...
    'MarkerFaceColor', [0.1 0.75 0.2], ...
    'MarkerEdgeColor', [0.05 0.35 0.1], ...
    'MarkerSize', 8, 'HitTest', 'off');
hold(ax, 'off');
ax.ButtonDownFcn = callbacks.spectrum;

side = uipanel(root, 'Title', 'Runtime');
side.Layout.Row = 2; side.Layout.Column = 2;
sideGrid = uigridlayout(side, [10 2]);
sideGrid.RowHeight = {24,24,24,24,24,24,24,24,'1x',24};
sideGrid.ColumnWidth = {105, '1x'};
placeLabel(sideGrid, 'State', 1, 1);
stateLabel = uilabel(sideGrid, 'Text', 'IDLE', 'FontWeight', 'bold');
stateLabel.Layout.Row = 1; stateLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Carriers', 2, 1);
carrierLabel = uilabel(sideGrid, 'Text', '0');
carrierLabel.Layout.Row = 2; carrierLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Winners', 3, 1);
winnerLabel = uilabel(sideGrid, 'Text', '-');
winnerLabel.Layout.Row = 3; winnerLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Logical time', 4, 1);
timeLabel = uilabel(sideGrid, 'Text', '0.000 s');
timeLabel.Layout.Row = 4; timeLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Input lag', 5, 1);
lagLabel = uilabel(sideGrid, 'Text', '0 ms');
lagLabel.Layout.Row = 5; lagLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Input RTF', 6, 1);
rtfLabel = uilabel(sideGrid, 'Text', '-');
rtfLabel.Layout.Row = 6; rtfLabel.Layout.Column = 2;
placeLabel(sideGrid, 'PDU count', 7, 1);
pduLabel = uilabel(sideGrid, 'Text', '0');
pduLabel.Layout.Row = 7; pduLabel.Layout.Column = 2;
placeLabel(sideGrid, 'DDC rate', 8, 1);
ddcLabel = uilabel(sideGrid, 'Text', '-');
ddcLabel.Layout.Row = 8; ddcLabel.Layout.Column = 2;
selectionArea = uitextarea(sideGrid, 'Editable', 'off', ...
    'Value', {'Click one or more PSD peaks.'});
selectionArea.Layout.Row = 9; selectionArea.Layout.Column = [1 2];
hintLabel = uilabel(sideGrid, 'Text', 'Parallel protocol workers.');
hintLabel.Layout.Row = 10; hintLabel.Layout.Column = [1 2];

console = uitextarea(root, 'Editable', 'off', ...
    'Value', {'Load a capture and start 1x preview.'});
console.Layout.Row = 3; console.Layout.Column = [1 2];

view = struct( ...
    'figure', fig, 'path', pathField, 'sampleRate', fsField, ...
    'centerHz', centerField, 'bandwidth', bwDrop, ...
    'metadata', metadataLabel, 'axes', ax, 'psdLine', psdLine, ...
    'markerLine', markerLine, 'runButton', runButton, ...
    'state', stateLabel, 'carrierCount', carrierLabel, ...
    'winners', winnerLabel, 'logicalTime', timeLabel, ...
    'inputLag', lagLabel, 'rtf', rtfLabel, 'pduCount', pduLabel, ...
    'ddcRate', ddcLabel, 'selections', selectionArea, ...
    'hint', hintLabel, 'console', console);
end

function label = placeLabel(parent, text, row, column)
label = uilabel(parent, 'Text', text);
label.Layout.Row = row;
label.Layout.Column = column;
end
