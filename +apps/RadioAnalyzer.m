function fig = RadioAnalyzer(varargin)
%RADIOANALYZER Programmatic MATLAB UI for the migrated decoder workflow.
p = inputParser;
p.addParameter('DefaultFile', fullfile(pybackend.defaultPythonRoot(), 'data', 'dmr_1_78125.rawiq'));
p.parse(varargin{:});

fig = uifigure('Name', 'DMR/P25/dPMR Radio Analyzer', 'Position', [100 100 1180 720]);
grid = uigridlayout(fig, [4 4]);
grid.RowHeight = {32, 32, '1x', 190};
grid.ColumnWidth = {'1x', 110, 130, 120};
grid.Padding = [10 10 10 10];
grid.RowSpacing = 8;
grid.ColumnSpacing = 8;

fileField = uieditfield(grid, 'text', 'Value', char(p.Results.DefaultFile));
fileField.Layout.Row = 1;
fileField.Layout.Column = 1;

browseButton = uibutton(grid, 'Text', 'Browse', 'ButtonPushedFcn', @browseFile);
browseButton.Layout.Row = 1;
browseButton.Layout.Column = 2;

protocolDrop = uidropdown(grid, ...
    'Items', {'all', 'dmr', 'p25', 'dpmr'}, ...
    'Value', 'all');
protocolDrop.Layout.Row = 1;
protocolDrop.Layout.Column = 3;

runButton = uibutton(grid, 'Text', 'Analyze', 'ButtonPushedFcn', @runAnalysis);
runButton.Layout.Row = 1;
runButton.Layout.Column = 4;

backendDrop = uidropdown(grid, ...
    'Items', {'matlab', 'python'}, ...
    'Value', 'matlab');
backendDrop.Layout.Row = 2;
backendDrop.Layout.Column = 3;

blindCheck = uicheckbox(grid, 'Text', 'Blind search', 'Value', false);
blindCheck.Layout.Row = 2;
blindCheck.Layout.Column = 4;

statusArea = uitextarea(grid, 'Editable', 'off', 'Value', {'Ready'});
statusArea.Layout.Row = 2;
statusArea.Layout.Column = [1 2];

ax = uiaxes(grid);
ax.Layout.Row = 3;
ax.Layout.Column = [1 4];
title(ax, 'PSD');
xlabel(ax, 'Frequency (kHz)');
ylabel(ax, 'PSD (dB)');

pduTable = uitable(grid);
pduTable.Layout.Row = 4;
pduTable.Layout.Column = [1 4];

    function browseFile(~, ~)
        [file, folder] = uigetfile({'*.rawiq;*.wav;*.wave', 'IQ files'}, 'Select IQ file');
        if isequal(file, 0)
            return;
        end
        fileField.Value = fullfile(folder, file);
    end

    function runAnalysis(~, ~)
        try
            statusArea.Value = {'Reading IQ and decoding...'};
            drawnow;
            protocol = protocolDrop.Value;
            if strcmp(protocol, 'all')
                protocolNames = {};
            else
                protocolNames = {protocol};
            end
            result = viz.analyzeFile(fileField.Value, ...
                'ProtocolNames', protocolNames, ...
                'PipelineBackend', backendDrop.Value, ...
                'DecoderBackend', backendDrop.Value, ...
                'BlindSearch', blindCheck.Value, ...
                'CreateFigure', false);
            [f, psd] = common.welchPsd(common.readRawIq(fileField.Value), result.sampleRate, 4096);
            plot(ax, f ./ 1e3, 10 .* log10(psd + 1e-12), 'LineWidth', 0.7);
            grid(ax, 'on');
            title(ax, sprintf('PSD - %s', fileField.Value), 'Interpreter', 'none');
            pduTable.Data = result.table;
            statusArea.Value = {sprintf('Decoded %d PDUs.', numel(result.pdus))};
        catch err
            statusArea.Value = {err.message};
        end
    end
end
