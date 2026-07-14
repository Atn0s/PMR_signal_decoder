function app = carrier_scope(varargin)
%CARRIER_SCOPE Locate up to five carriers in a wideband IQ recording.
%   carrier_scope opens a lightweight spectrum/waterfall viewer.  It reads
%   BVSP and headerless interleaved-int16 IQ recordings in bounded blocks;
%   it does not run the PFB scanner or any protocol decoder.
%
%   Click the average/max-hold spectrum or the waterfall to add a carrier.
%   The selected position is refined by integrating energy over the chosen
%   channel bandwidth.  "Copy scanner config" places absolute RF hints and
%   the recording center frequency on the clipboard.
%
%   APP = carrier_scope(...) returns a small programmatic API:
%       APP.Figure
%       APP.Analyze()
%       APP.AddFrequencyHz(rfFrequencyHz)
%       APP.GetState()
%       APP.GetScannerConfig()
%
%   Name-value options:
%       DefaultFile   Initial BVSP/rawiq path.  Defaults to DMR_signal/1.bvsp
%                     when that sample is available.
%       AutoAnalyze   Analyze DefaultFile immediately (default true).
%       Visible       'on' or 'off' (default 'on').
%       StartTimeSec  Initial analysis start (default 0).
%       DurationSec   Initial analysis duration (default 1).
%       Nfft          32768, 65536, or 131072 (default 65536).

%   BVSP support currently covers the observed USRP layout used by
%   /home/lzkj/lzkj_workspace/DMR_signal: a 112-byte header followed by
%   interleaved little-endian int16 I/Q samples.

%   See also SCANNER.

p = inputParser;
p.addParameter('DefaultFile', defaultCapturePath(), ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter('AutoAnalyze', true, @(x) islogical(x) && isscalar(x));
p.addParameter('Visible', 'on', @(x) any(strcmpi(char(x), {'on', 'off'})));
p.addParameter('StartTimeSec', 0, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.addParameter('DurationSec', 1, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
p.addParameter('Nfft', 65536, ...
    @(x) isnumeric(x) && isscalar(x) && any(x == [32768 65536 131072]));
p.parse(varargin{:});

maxSelectedCarriers = 5;
maxWaterfallRows = 300;
maxWaterfallBins = 16384;
defaultFile = char(p.Results.DefaultFile);

state = struct( ...
    'metadata', emptyMetadata(), ...
    'frequencyHz', zeros(0, 1), ...
    'averagePsd', zeros(0, 1), ...
    'maxHoldPsd', zeros(0, 1), ...
    'waterfallFrequencyHz', zeros(0, 1), ...
    'waterfallTimeSec', zeros(0, 1), ...
    'waterfallPsd', zeros(0, 0, 'single'), ...
    'selected', emptySelection(), ...
    'selectedTableRow', [], ...
    'markerHandles', gobjects(0), ...
    'lastStatus', 'Ready');

fig = uifigure( ...
    'Name', 'Carrier Scope - Wideband Frequency Locator', ...
    'Position', [80 60 1400 880], ...
    'Visible', char(p.Results.Visible));
outer = uigridlayout(fig, [4 2]);
outer.RowHeight = {92, 300, '1x', 48};
outer.ColumnWidth = {'1x', 340};
outer.Padding = [10 10 10 10];
outer.RowSpacing = 7;

controlsContainer = uipanel(outer, 'BorderType', 'none');
controlsContainer.Layout.Row = 1;
controlsContainer.Layout.Column = [1 2];
controls = uigridlayout(controlsContainer, [2 10]);
controls.ColumnWidth = {56, '1x', 82, 74, 86, 88, 78, 88, 102, 108};
controls.RowHeight = {32, 32};
controls.Padding = [0 0 0 0];
controls.RowSpacing = 6;
controls.ColumnSpacing = 6;

uilabel(controls, 'Text', 'File');
fileField = uieditfield(controls, 'text', ...
    'Value', defaultFile, 'ValueChangedFcn', @onFileFieldChanged);
fileField.Layout.Column = [2 7];
browseButton = uibutton(controls, 'Text', 'Browse', ...
    'ButtonPushedFcn', @onBrowse);
browseButton.Layout.Column = 8;
analyzeButton = uibutton(controls, 'Text', 'Analyze', ...
    'ButtonPushedFcn', @onAnalyze);
analyzeButton.Layout.Column = [9 10];

centerLabel = uilabel(controls, 'Text', 'Center MHz');
centerLabel.Layout.Row = 2;
centerLabel.Layout.Column = 1;
centerField = uieditfield(controls, 'numeric', ...
    'Value', 0, 'LowerLimitInclusive', 'on', ...
    'ValueDisplayFormat', '%.6f');
centerField.Layout.Row = 2;
centerField.Layout.Column = 2;

fsLabel = uilabel(controls, 'Text', 'Fs MHz');
fsLabel.Layout.Row = 2;
fsLabel.Layout.Column = 3;
fsField = uieditfield(controls, 'numeric', ...
    'Value', 61.44, 'Limits', [eps inf], 'LowerLimitInclusive', 'off', ...
    'ValueDisplayFormat', '%.6f');
fsField.Layout.Row = 2;
fsField.Layout.Column = 4;

startLabel = uilabel(controls, 'Text', 'Start s');
startLabel.Layout.Row = 2;
startLabel.Layout.Column = 5;
startField = uieditfield(controls, 'numeric', ...
    'Value', p.Results.StartTimeSec, 'Limits', [0 inf], ...
    'ValueDisplayFormat', '%.3f');
startField.Layout.Row = 2;
startField.Layout.Column = 6;

durationLabel = uilabel(controls, 'Text', 'Duration s');
durationLabel.Layout.Row = 2;
durationLabel.Layout.Column = 7;
durationField = uieditfield(controls, 'numeric', ...
    'Value', p.Results.DurationSec, 'Limits', [eps inf], ...
    'LowerLimitInclusive', 'off', 'ValueDisplayFormat', '%.3f');
durationField.Layout.Row = 2;
durationField.Layout.Column = 8;

nfftDrop = uidropdown(controls, ...
    'Items', {'NFFT 32768', 'NFFT 65536', 'NFFT 131072'}, ...
    'ItemsData', [32768 65536 131072], ...
    'Value', p.Results.Nfft);
nfftDrop.Layout.Row = 2;
nfftDrop.Layout.Column = 9;

bandwidthDrop = uidropdown(controls, ...
    'Items', {'Center 12.5 kHz', 'Center 6.25 kHz', 'Center 25 kHz'}, ...
    'ItemsData', [12500 6250 25000], ...
    'Value', 12500, ...
    'Tooltip', ['Bandwidth used to refine a clicked spectral position. ', ...
        'Use 25 kHz for TETRA.']);
bandwidthDrop.Layout.Row = 2;
bandwidthDrop.Layout.Column = 10;

psdAx = uiaxes(outer);
psdAx.Layout.Row = 2;
psdAx.Layout.Column = [1 2];
title(psdAx, 'Average and Max-Hold Spectrum');
xlabel(psdAx, 'Absolute RF (MHz)');
ylabel(psdAx, 'Relative PSD (dB)');
grid(psdAx, 'on');
psdAx.ButtonDownFcn = @onSpectrumClick;

waterfallAx = uiaxes(outer);
waterfallAx.Layout.Row = 3;
waterfallAx.Layout.Column = 1;
title(waterfallAx, 'Waterfall');
xlabel(waterfallAx, 'Time (s)');
ylabel(waterfallAx, 'Absolute RF (MHz)');
waterfallAx.ButtonDownFcn = @onWaterfallClick;

selectionContainer = uipanel(outer, 'BorderType', 'none');
selectionContainer.Layout.Row = 3;
selectionContainer.Layout.Column = 2;
selectionPanel = uigridlayout(selectionContainer, [2 1]);
selectionPanel.RowHeight = {'1x', 132};
selectionPanel.Padding = [0 0 0 0];
selectionPanel.RowSpacing = 8;

selectionTable = uitable(selectionPanel, ...
    'ColumnName', {'RF (MHz)', 'Offset (kHz)', 'Refine BW (kHz)'}, ...
    'ColumnEditable', [false false false], ...
    'CellSelectionCallback', @onTableSelection);
selectionTable.Layout.Row = 1;
selectionTable.Layout.Column = 1;

buttonGrid = uigridlayout(selectionPanel, [4 1]);
buttonGrid.Layout.Row = 2;
buttonGrid.Layout.Column = 1;
buttonGrid.RowHeight = {'1x', '1x', '1x', '1x'};
buttonGrid.Padding = [0 0 0 0];
uibutton(buttonGrid, 'Text', 'Remove selected', ...
    'ButtonPushedFcn', @onRemoveSelected);
uibutton(buttonGrid, 'Text', 'Clear all', ...
    'ButtonPushedFcn', @onClearSelected);
uibutton(buttonGrid, 'Text', 'Copy scanner config', ...
    'ButtonPushedFcn', @onCopyConfig);
uibutton(buttonGrid, 'Text', 'Save hints...', ...
    'ButtonPushedFcn', @onSaveHints);

statusArea = uitextarea(outer, 'Editable', 'off', ...
    'Value', {'Ready. Load a capture, then click the spectrum or waterfall.'});
statusArea.Layout.Row = 4;
statusArea.Layout.Column = [1 2];

app = struct( ...
    'Figure', fig, ...
    'Analyze', @runAnalysis, ...
    'AddFrequencyHz', @addFrequency, ...
    'GetState', @getPublicState, ...
    'GetScannerConfig', @scannerConfigText);

if ~isempty(defaultFile) && exist(defaultFile, 'file') == 2
    try
        applyFileMetadata(defaultFile);
        if p.Results.AutoAnalyze
            runAnalysis();
        end
    catch ME
        setStatus(sprintf('Unable to initialize capture: %s', ME.message));
    end
end

    function onBrowse(~, ~)
        [name, folder] = uigetfile( ...
            {'*.bvsp;*.rawiq;*.bin', 'Wideband IQ (*.bvsp, *.rawiq, *.bin)'; ...
             '*.*', 'All files'}, ...
            'Select a wideband IQ capture');
        if isequal(name, 0)
            return;
        end
        fileField.Value = fullfile(folder, name);
        onFileFieldChanged();
    end

    function onFileFieldChanged(~, ~)
        path = char(fileField.Value);
        if exist(path, 'file') ~= 2
            setStatus(sprintf('File not found: %s', path));
            return;
        end
        try
            applyFileMetadata(path);
        catch ME
            setStatus(sprintf('Metadata error: %s', ME.message));
        end
    end

    function applyFileMetadata(path)
        metadata = inspectCapture(path, fsField.Value * 1e6, ...
            centerField.Value * 1e6);
        state.metadata = metadata;
        fsField.Value = metadata.sampleRateHz / 1e6;
        centerField.Value = metadata.centerFrequencyHz / 1e6;
        durationField.Value = min(durationField.Value, ...
            max(metadata.durationSec, eps));
        setStatus(metadataSummary(metadata));
    end

    function onAnalyze(~, ~)
        runAnalysis();
    end

    function runAnalysis()
        path = char(fileField.Value);
        if exist(path, 'file') ~= 2
            setStatus(sprintf('File not found: %s', path));
            return;
        end
        analyzeButton.Enable = 'off';
        cleanup = onCleanup(@() set(analyzeButton, 'Enable', 'on'));
        try
            metadata = inspectCapture(path, fsField.Value * 1e6, ...
                centerField.Value * 1e6);
            metadata.sampleRateHz = fsField.Value * 1e6;
            metadata.centerFrequencyHz = centerField.Value * 1e6;
            metadata.durationSec = double(metadata.totalSamples) / ...
                metadata.sampleRateHz;
            startSec = min(startField.Value, metadata.durationSec);
            durationSec = min(durationField.Value, ...
                metadata.durationSec - startSec);
            if durationSec <= 0
                error('carrier_scope:EmptyInterval', ...
                    'The selected time interval is outside the capture.');
            end
            nfft = double(nfftDrop.Value);
            setStatus(sprintf( ...
                'Analyzing %.3f s from %.3f s (NFFT=%d)...', ...
                durationSec, startSec, nfft));
            drawnow;
            result = computeSpectrum(metadata, startSec, durationSec, ...
                nfft, maxWaterfallRows, maxWaterfallBins, @progressUpdate);
            state.metadata = metadata;
            state.frequencyHz = result.frequencyHz;
            state.averagePsd = result.averagePsd;
            state.maxHoldPsd = result.maxHoldPsd;
            state.waterfallFrequencyHz = result.waterfallFrequencyHz;
            state.waterfallTimeSec = result.waterfallTimeSec;
            state.waterfallPsd = result.waterfallPsd;
            state.selected = emptySelection();
            state.selectedTableRow = [];
            updatePlots();
            updateSelectionTable();
            setStatus(sprintf( ...
                ['Analyzed %.3f s: %d waterfall rows, %.1f Hz PSD bins. ', ...
                 'Click a carrier to add it (maximum %d).'], ...
                durationSec, numel(result.waterfallTimeSec), ...
                metadata.sampleRateHz / nfft, maxSelectedCarriers));
        catch ME
            setStatus(sprintf('Analysis failed: %s', ME.message));
        end
        clear cleanup;
    end

    function progressUpdate(completed, total)
        if completed == 1 || completed == total || mod(completed, 20) == 0
            setStatus(sprintf('Computing spectrum row %d/%d...', ...
                completed, total));
            drawnow limitrate;
        end
    end

    function updatePlots()
        delete(psdAx.Children);
        delete(waterfallAx.Children);
        state.markerHandles = gobjects(0);
        if isempty(state.frequencyHz)
            return;
        end

        avgDb = 10 .* log10(double(state.averagePsd) + 1e-20);
        maxDb = 10 .* log10(double(state.maxHoldPsd) + 1e-20);
        rfMHz = state.frequencyHz ./ 1e6;
        avgLine = plot(psdAx, rfMHz, avgDb, ...
            'Color', [0.10 0.35 0.70], 'LineWidth', 0.8, ...
            'DisplayName', 'Average', ...
            'ButtonDownFcn', @onSpectrumClick, ...
            'PickableParts', 'all');
        hold(psdAx, 'on');
        maxLine = plot(psdAx, rfMHz, maxDb, ...
            'Color', [0.85 0.30 0.10], 'LineWidth', 0.55, ...
            'DisplayName', 'Max hold', ...
            'ButtonDownFcn', @onSpectrumClick, ...
            'PickableParts', 'all');
        avgLine.HitTest = 'on';
        maxLine.HitTest = 'on';
        legend(psdAx, 'Location', 'northeast');
        grid(psdAx, 'on');
        title(psdAx, sprintf('%s | center %.6f MHz | Fs %.3f MHz', ...
            state.metadata.format, ...
            state.metadata.centerFrequencyHz / 1e6, ...
            state.metadata.sampleRateHz / 1e6));
        xlabel(psdAx, 'Absolute RF (MHz)');
        ylabel(psdAx, 'PSD (dB)');
        drawReferenceLines(psdAx);

        waterDb = 10 .* log10(double(state.waterfallPsd) + 1e-20);
        imageHandle = imagesc(waterfallAx, state.waterfallTimeSec, ...
            state.waterfallFrequencyHz ./ 1e6, waterDb.');
        imageHandle.ButtonDownFcn = @onWaterfallClick;
        imageHandle.PickableParts = 'all';
        axis(waterfallAx, 'xy');
        colormap(waterfallAx, turbo);
        colorbar(waterfallAx);
        values = waterDb(isfinite(waterDb));
        if ~isempty(values)
            limits = [localPercentile(values, 10), ...
                localPercentile(values, 99.5)];
            if limits(2) <= limits(1)
                limits(2) = limits(1) + 1;
            end
            clim(waterfallAx, limits);
        end
        title(waterfallAx, 'Wideband Waterfall (click to add a carrier)');
        xlabel(waterfallAx, 'Time (s)');
        ylabel(waterfallAx, 'Absolute RF (MHz)');
        hold(psdAx, 'off');
        redrawMarkers();
    end

    function drawReferenceLines(ax)
        centerMHz = state.metadata.centerFrequencyHz / 1e6;
        xline(ax, centerMHz, ':', 'Center', ...
            'Color', [0.30 0.30 0.30], 'HandleVisibility', 'off', ...
            'HitTest', 'off');
        if state.metadata.bandwidthHz > 0
            halfBwMHz = state.metadata.bandwidthHz / 2e6;
            xline(ax, centerMHz - halfBwMHz, '--', 'Usable-band edge', ...
                'Color', [0.45 0.45 0.45], 'HandleVisibility', 'off', ...
                'HitTest', 'off');
            xline(ax, centerMHz + halfBwMHz, '--', '', ...
                'Color', [0.45 0.45 0.45], 'HandleVisibility', 'off', ...
                'HitTest', 'off');
        end
    end

    function onSpectrumClick(~, event)
        if isempty(state.frequencyHz)
            return;
        end
        point = event.IntersectionPoint;
        addFrequency(point(1) * 1e6);
    end

    function onWaterfallClick(~, event)
        if isempty(state.frequencyHz)
            return;
        end
        point = event.IntersectionPoint;
        addFrequency(point(2) * 1e6);
    end

    function addFrequency(rfFrequencyHz)
        if isempty(state.frequencyHz)
            setStatus('Analyze a capture before selecting carriers.');
            return;
        end
        if numel(state.selected) >= maxSelectedCarriers
            setStatus(sprintf('At most %d carrier hints are allowed.', ...
                maxSelectedCarriers));
            return;
        end
        if rfFrequencyHz < state.frequencyHz(1) || ...
                rfFrequencyHz > state.frequencyHz(end)
            setStatus('The selected frequency is outside the displayed band.');
            return;
        end
        refineBandwidthHz = double(bandwidthDrop.Value);
        refinedHz = refineCarrierCenter(rfFrequencyHz, refineBandwidthHz);
        duplicateToleranceHz = max(2500, refineBandwidthHz / 4);
        if ~isempty(state.selected) && any(abs( ...
                [state.selected.rfFrequencyHz] - refinedHz) <= ...
                duplicateToleranceHz)
            setStatus(sprintf('A carrier near %.6f MHz is already selected.', ...
                refinedHz / 1e6));
            return;
        end
        item = struct( ...
            'rfFrequencyHz', double(refinedHz), ...
            'offsetHz', double(refinedHz - ...
                state.metadata.centerFrequencyHz), ...
            'refineBandwidthHz', refineBandwidthHz, ...
            'clickedFrequencyHz', double(rfFrequencyHz));
        state.selected(end+1, 1) = item;
        [~, order] = sort([state.selected.rfFrequencyHz]);
        state.selected = state.selected(order);
        updateSelectionTable();
        redrawMarkers();
        setStatus(sprintf( ...
            'Added %.6f MHz (clicked %.6f MHz, offset %+.3f kHz).', ...
            item.rfFrequencyHz / 1e6, item.clickedFrequencyHz / 1e6, ...
            item.offsetHz / 1e3));
    end

    function refinedHz = refineCarrierCenter(clickedHz, bandwidthHz)
        f = state.frequencyHz(:);
        pwr = double(state.averagePsd(:));
        binHz = median(diff(f));
        searchRadiusHz = max(50e3, 2 * bandwidthHz);
        searchMask = abs(f - clickedHz) <= searchRadiusHz;
        if ~any(searchMask)
            refinedHz = clickedHz;
            return;
        end
        smoothingBins = max(3, round(bandwidthHz / binHz));
        smoothed = movmean(pwr, smoothingBins, 'Endpoints', 'shrink');
        indices = find(searchMask);
        [~, localIndex] = max(smoothed(indices));
        peakIndex = indices(localIndex);

        % The moving-energy peak is more stable than a single 4FSK spectral
        % line.  A short energy-centroid pass removes sub-bin quantization
        % without allowing distant spurs to pull the result away.
        halfBins = max(1, floor(smoothingBins / 2));
        region = max(1, peakIndex-halfBins):min(numel(f), peakIndex+halfBins);
        localNoise = median(pwr(indices));
        weights = max(0, pwr(region) - localNoise);
        if sum(weights) > 0
            refinedHz = sum(f(region) .* weights) / sum(weights);
        else
            refinedHz = f(peakIndex);
        end
    end

    function updateSelectionTable()
        if isempty(state.selected)
            selectionTable.Data = zeros(0, 3);
        else
            selectionTable.Data = [ ...
                [state.selected.rfFrequencyHz].' ./ 1e6, ...
                [state.selected.offsetHz].' ./ 1e3, ...
                [state.selected.refineBandwidthHz].' ./ 1e3];
        end
        state.selectedTableRow = [];
    end

    function redrawMarkers()
        if ~isempty(state.markerHandles)
            delete(state.markerHandles(isgraphics(state.markerHandles)));
        end
        state.markerHandles = gobjects(0);
        if isempty(state.selected) || isempty(state.frequencyHz)
            return;
        end
        hold(psdAx, 'on');
        hold(waterfallAx, 'on');
        for k = 1:numel(state.selected)
            rfMHz = state.selected(k).rfFrequencyHz / 1e6;
            [~, spectrumIndex] = min(abs( ...
                state.frequencyHz - state.selected(k).rfFrequencyHz));
            markerDb = 10 * log10(double( ...
                state.maxHoldPsd(spectrumIndex)) + 1e-20);
            h1 = plot(psdAx, rfMHz, markerDb, 'v', ...
                'LineStyle', 'none', 'MarkerSize', 7, ...
                'MarkerFaceColor', [0.10 0.75 0.20], ...
                'MarkerEdgeColor', [0.05 0.35 0.10], ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            hLabel = text(psdAx, rfMHz, markerDb, sprintf('  %d', k), ...
                'Color', [0.05 0.45 0.10], ...
                'VerticalAlignment', 'middle', ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            h2 = yline(waterfallAx, rfMHz, '--', sprintf('%d', k), ...
                'Color', [0.20 1.00 0.20], 'LineWidth', 0.8, ...
                'HandleVisibility', 'off', 'HitTest', 'off');
            state.markerHandles(end+1:end+3) = [h1 hLabel h2];
        end
        hold(psdAx, 'off');
        hold(waterfallAx, 'off');
    end

    function onTableSelection(~, event)
        if isempty(event.Indices)
            state.selectedTableRow = [];
        else
            state.selectedTableRow = event.Indices(1, 1);
        end
    end

    function onRemoveSelected(~, ~)
        row = state.selectedTableRow;
        if isempty(row) || row < 1 || row > numel(state.selected)
            setStatus('Select a row in the carrier table first.');
            return;
        end
        removed = state.selected(row);
        state.selected(row) = [];
        updateSelectionTable();
        redrawMarkers();
        setStatus(sprintf('Removed %.6f MHz.', ...
            removed.rfFrequencyHz / 1e6));
    end

    function onClearSelected(~, ~)
        state.selected = emptySelection();
        updateSelectionTable();
        redrawMarkers();
        setStatus('Cleared all carrier hints.');
    end

    function onCopyConfig(~, ~)
        if isempty(state.selected)
            setStatus('Select at least one carrier first.');
            return;
        end
        textValue = scannerConfigText();
        try
            clipboard('copy', textValue);
            setStatus(['Copied scanner configuration:' newline textValue]);
        catch ME
            setStatus(sprintf('Clipboard unavailable: %s\n%s', ...
                ME.message, textValue));
        end
    end

    function value = scannerConfigText()
        frequencies = [state.selected.rfFrequencyHz];
        offsets = [state.selected.offsetHz];
        frequencyItems = arrayfun(@(x) sprintf('%.3f', x), frequencies, ...
            'UniformOutput', false);
        offsetItems = arrayfun(@(x) sprintf('%+.3f', x), offsets, ...
            'UniformOutput', false);
        additionalText = '';
        if numel(offsetItems) > 1
            additionalText = sprintf([ ...
                '\n%% Additional selected offsets (run separately in the ', ...
                'current single-carrier phase): [%s]'], ...
                strjoin(offsetItems(2:end), ', '));
        end
        value = sprintf([ ...
            'EXECUTION_MODE = ''tuned-parallel'';\n', ...
            'WIDEBAND_CENTER_FREQUENCY_HZ = %.3f;\n', ...
            'FREQUENCY_HINTS_HZ = [%s];\n', ...
            'FREQ_LIST = %s; %% one relative offset (Hz)\n', ...
            'BLIND_SEARCH = false;\n', ...
            '%% Set SAMPLE_RATE only for headerless IQ; BVSP supplies it.%s'], ...
            state.metadata.centerFrequencyHz, ...
            strjoin(frequencyItems, ', '), offsetItems{1}, additionalText);
    end

    function onSaveHints(~, ~)
        if isempty(state.selected)
            setStatus('Select at least one carrier first.');
            return;
        end
        [~, stem] = fileparts(state.metadata.path);
        [name, folder] = uiputfile('*.mat', 'Save carrier hints', ...
            [stem '.carriers.mat']);
        if isequal(name, 0)
            return;
        end
        hints = struct( ...
            'formatVersion', 1, ...
            'sourcePath', state.metadata.path, ...
            'sourceFormat', state.metadata.format, ...
            'sampleRateHz', state.metadata.sampleRateHz, ...
            'centerFrequencyHz', state.metadata.centerFrequencyHz, ...
            'rfFrequencyHz', [state.selected.rfFrequencyHz], ...
            'offsetHz', [state.selected.offsetHz], ...
            'refineBandwidthHz', [state.selected.refineBandwidthHz], ...
            'createdAt', char(datetime('now', 'TimeZone', 'local')));
        save(fullfile(folder, name), 'hints');
        setStatus(sprintf('Saved %d carrier hints to %s.', ...
            numel(state.selected), fullfile(folder, name)));
    end

    function public = getPublicState()
        public = struct( ...
            'metadata', state.metadata, ...
            'frequencyHz', state.frequencyHz, ...
            'averagePsd', state.averagePsd, ...
            'maxHoldPsd', state.maxHoldPsd, ...
            'waterfallFrequencyHz', state.waterfallFrequencyHz, ...
            'waterfallTimeSec', state.waterfallTimeSec, ...
            'waterfallPsd', state.waterfallPsd, ...
            'selected', state.selected, ...
            'status', state.lastStatus);
    end

    function setStatus(message)
        state.lastStatus = char(message);
        statusArea.Value = splitlines(string(message));
    end
end

function result = computeSpectrum(metadata, startSec, durationSec, nfft, ...
        maxRows, maxDisplayBins, progressFcn)
fs = metadata.sampleRateHz;
firstSample = floor(startSec * fs);
availableSamples = double(metadata.totalSamples) - firstSample;
requestedSamples = min(availableSamples, ceil(durationSec * fs));
if requestedSamples < nfft
    error('carrier_scope:IntervalTooShort', ...
        'The selected interval must contain at least one NFFT block.');
end

rowDurationSec = max(0.010, durationSec / maxRows);
samplesPerRow = max(nfft, round(rowDurationSec * fs));
rowCount = ceil(requestedSamples / samplesPerRow);
rowCount = min(rowCount, maxRows);

displayFactor = max(1, ceil(nfft / maxDisplayBins));
while mod(nfft, displayFactor) ~= 0
    displayFactor = displayFactor + 1;
end
displayBinCount = nfft / displayFactor;
waterfall = zeros(rowCount, displayBinCount, 'single');
sumPsd = zeros(nfft, 1);
maxPsd = zeros(nfft, 1);
window = single(0.5 - 0.5 .* cos( ...
    2 .* pi .* (0:nfft-1).' ./ max(nfft-1, 1)));
normalization = double(sum(abs(window) .^ 2) * fs);

fid = fopen(metadata.path, 'rb', 'ieee-le');
if fid < 0
    error('carrier_scope:OpenFailed', ...
        'Unable to open capture: %s', metadata.path);
end
cleanup = onCleanup(@() fclose(fid));
byteOffset = metadata.headerBytes + firstSample * metadata.bytesPerComplexSample;
if fseek(fid, byteOffset, 'bof') ~= 0
    error('carrier_scope:SeekFailed', ...
        'Unable to seek to the selected capture interval.');
end

processedPsdRows = 0;
samplesRemaining = requestedSamples;
actualTimes = zeros(rowCount, 1);
for row = 1:rowCount
    count = min(samplesPerRow, samplesRemaining);
    raw = fread(fid, [2, count], 'int16=>single');
    count = size(raw, 2);
    if count < nfft
        break;
    end
    iq = complex(raw(1, :).', raw(2, :).') ./ single(32768);
    segmentCount = floor(count / nfft);
    iq = iq(1:segmentCount*nfft);
    segments = reshape(iq, nfft, segmentCount);
    spectrum = fftshift(fft(segments .* window, nfft, 1), 1);
    rowPsd = mean(abs(spectrum) .^ 2, 2) ./ normalization;
    sumPsd = sumPsd + double(rowPsd);
    maxPsd = max(maxPsd, double(rowPsd));
    displayPsd = mean(reshape(rowPsd, displayFactor, []), 1);
    waterfall(row, :) = single(displayPsd);
    processedPsdRows = processedPsdRows + 1;
    actualTimes(row) = startSec + ...
        (double(firstSample + (row-0.5)*count) - firstSample) / fs;
    samplesRemaining = samplesRemaining - count;
    if nargin >= 7 && ~isempty(progressFcn)
        progressFcn(row, rowCount);
    end
    if samplesRemaining <= 0
        break;
    end
end
clear cleanup;

if processedPsdRows == 0
    error('carrier_scope:NoSpectrumRows', ...
        'No complete FFT rows were available in the selected interval.');
end
waterfall = waterfall(1:processedPsdRows, :);
actualTimes = actualTimes(1:processedPsdRows);
bins = (-nfft/2:nfft/2-1).';
basebandFrequencyHz = bins .* (fs / nfft);
frequencyHz = metadata.centerFrequencyHz + basebandFrequencyHz;
displayFrequencyHz = mean(reshape(frequencyHz, displayFactor, []), 1).';

result = struct( ...
    'frequencyHz', frequencyHz, ...
    'averagePsd', sumPsd ./ processedPsdRows, ...
    'maxHoldPsd', maxPsd, ...
    'waterfallFrequencyHz', displayFrequencyHz, ...
    'waterfallTimeSec', actualTimes, ...
    'waterfallPsd', waterfall);
end

function metadata = inspectCapture(path, fallbackSampleRateHz, ...
        fallbackCenterFrequencyHz)
path = char(path);
info = dir(path);
if isempty(info)
    error('carrier_scope:NotFound', 'Capture does not exist: %s', path);
end
[~, ~, extension] = fileparts(path);
isBvsp = strcmpi(extension, '.bvsp');
metadata = emptyMetadata();
metadata.path = path;
metadata.bytesPerComplexSample = 4;
metadata.fileBytes = double(info.bytes);

if isBvsp
    if info.bytes < 112
        error('carrier_scope:BvspTooShort', ...
            'BVSP file is shorter than its 112-byte header.');
    end
    fid = fopen(path, 'rb', 'ieee-le');
    if fid < 0
        error('carrier_scope:OpenFailed', 'Unable to open BVSP file.');
    end
    cleanup = onCleanup(@() fclose(fid));
    metadata.format = 'BVSP/USRP int16 IQ';
    metadata.headerBytes = 112;
    metadata.signature = readScalar(fid, 0, 'uint32=>double');
    metadata.declaredFileBytes = readScalar(fid, 8, 'uint64=>double');
    metadata.durationNs = readScalar(fid, 24, 'uint32=>double');
    metadata.fileIndex = readScalar(fid, 28, 'uint32=>double');
    fseek(fid, 32, 'bof');
    deviceBytes = fread(fid, 16, '*uint8').';
    zeroIndex = find(deviceBytes == 0, 1);
    if ~isempty(zeroIndex)
        deviceBytes = deviceBytes(1:zeroIndex-1);
    end
    metadata.device = char(deviceBytes);
    metadata.sampleRateHz = readScalar(fid, 48, 'uint32=>double');
    metadata.bandwidthHz = readScalar(fid, 52, 'uint32=>double');
    metadata.centerFrequencyHz = ...
        1e3 * readScalar(fid, 56, 'uint32=>double');
    metadata.gain = readScalar(fid, 60, 'int32=>double');
    clear cleanup;
    if metadata.declaredFileBytes ~= 0 && ...
            metadata.declaredFileBytes ~= info.bytes
        error('carrier_scope:BvspSizeMismatch', ...
            'BVSP header declares %.0f bytes, file contains %.0f bytes.', ...
            metadata.declaredFileBytes, info.bytes);
    end
else
    metadata.format = 'RAW interleaved int16 IQ';
    metadata.headerBytes = 0;
    metadata.sampleRateHz = fallbackSampleRateHz;
    metadata.centerFrequencyHz = fallbackCenterFrequencyHz;
    metadata.bandwidthHz = 0;
end

payloadBytes = info.bytes - metadata.headerBytes;
if mod(payloadBytes, metadata.bytesPerComplexSample) ~= 0
    error('carrier_scope:PayloadAlignment', ...
        'IQ payload is not aligned to interleaved int16 I/Q samples.');
end
metadata.totalSamples = payloadBytes / metadata.bytesPerComplexSample;
metadata.durationSec = metadata.totalSamples / metadata.sampleRateHz;
end

function value = readScalar(fid, byteOffset, precision)
if fseek(fid, byteOffset, 'bof') ~= 0
    error('carrier_scope:BvspHeaderSeek', 'Unable to seek in BVSP header.');
end
value = fread(fid, 1, precision);
if isempty(value)
    error('carrier_scope:BvspHeaderRead', 'Incomplete BVSP header.');
end
end

function textValue = metadataSummary(metadata)
if startsWith(metadata.format, 'BVSP')
    textValue = sprintf([ ...
        '%s | device=%s file=%d | Fs=%.3f MHz BW=%.3f MHz ', ...
        'center=%.6f MHz | %.3f s, %.0f IQ samples'], ...
        metadata.format, metadata.device, metadata.fileIndex, ...
        metadata.sampleRateHz / 1e6, metadata.bandwidthHz / 1e6, ...
        metadata.centerFrequencyHz / 1e6, metadata.durationSec, ...
        metadata.totalSamples);
else
    textValue = sprintf('%s | Fs=%.3f MHz center=%.6f MHz | %.3f s', ...
        metadata.format, metadata.sampleRateHz / 1e6, ...
        metadata.centerFrequencyHz / 1e6, metadata.durationSec);
end
end

function metadata = emptyMetadata()
metadata = struct( ...
    'path', '', ...
    'format', '', ...
    'headerBytes', 0, ...
    'bytesPerComplexSample', 4, ...
    'fileBytes', 0, ...
    'declaredFileBytes', 0, ...
    'signature', 0, ...
    'durationNs', 0, ...
    'fileIndex', 0, ...
    'device', '', ...
    'sampleRateHz', 0, ...
    'bandwidthHz', 0, ...
    'centerFrequencyHz', 0, ...
    'gain', 0, ...
    'totalSamples', 0, ...
    'durationSec', 0);
end

function selected = emptySelection()
selected = struct( ...
    'rfFrequencyHz', {}, ...
    'offsetHz', {}, ...
    'refineBandwidthHz', {}, ...
    'clickedFrequencyHz', {});
end

function value = localPercentile(values, percentile)
values = sort(double(values(:)));
if isempty(values)
    value = NaN;
    return;
end
position = 1 + (numel(values) - 1) * percentile / 100;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    value = values(lowerIndex);
else
    alpha = position - lowerIndex;
    value = (1 - alpha) * values(lowerIndex) + ...
        alpha * values(upperIndex);
end
end

function path = defaultCapturePath()
candidate = '/home/lzkj/lzkj_workspace/DMR_signal/1.bvsp';
if exist(candidate, 'file') == 2
    path = candidate;
else
    path = '';
end
end
