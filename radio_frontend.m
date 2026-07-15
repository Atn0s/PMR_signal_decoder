function app = radio_frontend(varargin)
%RADIO_FRONTEND Live file-replay spectrum selection and protocol decode UI.
%
%   APP = RADIO_FRONTEND() opens the interactive frontend. The first phase
%   uses a pull-based looping file source; future SDR sources can provide the
%   same radio.stream IqChunk contract.
%
%   Programmatic methods used by tests and automation:
%       APP.LoadFile(path)
%       APP.StartPreview('StartTimer', false)
%       APP.SelectOffsetHz(offsetHz)
%       APP.RunIdentification('StartTimer', false)
%       APP.Step(count)
%       APP.Stop()
%       STATE = APP.GetState()
%       APP.Close()

p = inputParser;
p.addParameter('DefaultFile', defaultCapture());
p.addParameter('Visible', 'on');
p.addParameter('SampleRate', []);
p.addParameter('CenterFrequencyHz', []);
p.addParameter('IqDType', 'int16');
p.addParameter('ReplayMode', 'continuous-test');
p.addParameter('ReplaySpeed', 1.0);
p.addParameter('MaxLoops', 10);
p.addParameter('EpochSilenceSec', 0.400);
p.addParameter('ProtocolNames', {});
p.addParameter('ParallelMode', 'parallel');
p.addParameter('NumWorkers', 5);
p.addParameter('PoolType', 'processes');
p.addParameter('PrewarmDdc', true);
p.addParameter('WarmParallelPool', true);
p.addParameter('ContinueAfterLockSec', 0.0);
p.addParameter('MaxLogicalDurationSec', 0.0);
p.addParameter('SpectrumConfig', radio.scope.defaultConfig());
p.addParameter('TunedConfig', radio.tuned.defaultConfig());
p.addParameter('StreamConfig', radio.stream.defaultConfig());
p.addParameter('TaskFcn', []);
p.addParameter('TaskContext', struct());
p.addParameter('LockedDecodeFcn', []);
p.addParameter('Deduplicate', false);
p.addParameter('AutoStartPreview', false);
p.parse(varargin{:});
options = p.Results;
validateOptions(options);

fig = uifigure( ...
    'Name', 'PMR Live Spectrum and Protocol Frontend', ...
    'Position', [80 50 1460 900], ...
    'Visible', char(options.Visible));
root = uigridlayout(fig, [3 2]);
root.RowHeight = {82, '1x', 210};
root.ColumnWidth = {'2.7x', '1x'};
root.Padding = [8 8 8 8];
root.RowSpacing = 7;
root.ColumnSpacing = 7;

controls = uigridlayout(root, [2 12]);
controls.Layout.Row = 1;
controls.Layout.Column = [1 2];
controls.RowHeight = {30, 30};
controls.ColumnWidth = {45, '1x', 72, 42, 100, 42, 110, 48, 82, 42, 72, 100};
controls.Padding = [0 0 0 0];

placeLabel(controls, 'File', 1, 1);
pathField = uieditfield(controls, 'text');
pathField.Layout.Row = 1;
pathField.Layout.Column = [2 10];
browseButton = uibutton(controls, 'Text', 'Browse', ...
    'ButtonPushedFcn', @onBrowse);
browseButton.Layout.Row = 1;
browseButton.Layout.Column = 11;
previewButton = uibutton(controls, 'Text', 'Preview', ...
    'ButtonPushedFcn', @onPreview);
previewButton.Layout.Row = 1;
previewButton.Layout.Column = 12;

placeLabel(controls, 'Fs Hz', 2, 1);
sampleRateField = uieditfield(controls, 'numeric', ...
    'Limits', [0 Inf], 'Value', scalarOr(options.SampleRate, 0));
sampleRateField.Layout.Row = 2;
sampleRateField.Layout.Column = 2;
placeLabel(controls, 'RF Hz', 2, 3);
centerField = uieditfield(controls, 'numeric', ...
    'Value', scalarOr(options.CenterFrequencyHz, 0));
centerField.Layout.Row = 2;
centerField.Layout.Column = 4;
placeLabel(controls, 'Replay', 2, 5);
replayDrop = uidropdown(controls, ...
    'Items', {'once', 'continuous-test', 'epoch-repeat'}, ...
    'Value', normalizeReplayMode(options.ReplayMode));
replayDrop.Layout.Row = 2;
replayDrop.Layout.Column = 6;
placeLabel(controls, 'Speed', 2, 7);
speedDrop = uidropdown(controls, ...
    'Items', {'0.1x', '0.25x', '0.5x', '1x', 'unlimited'}, ...
    'Value', speedText(options.ReplaySpeed), ...
    'ValueChangedFcn', @onSpeedChanged);
speedDrop.Layout.Row = 2;
speedDrop.Layout.Column = 8;
placeLabel(controls, 'Loops', 2, 9);
loopField = uieditfield(controls, 'numeric', ...
    'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
    'Value', options.MaxLoops);
loopField.Layout.Row = 2;
loopField.Layout.Column = 10;
metadataLabel = uilabel(controls, 'Text', 'No capture loaded');
metadataLabel.Layout.Row = 2;
metadataLabel.Layout.Column = [11 12];

plots = uigridlayout(root, [2 1]);
plots.Layout.Row = 2;
plots.Layout.Column = 1;
plots.RowHeight = {'1x', '1x'};
plots.Padding = [0 0 0 0];
psdAx = uiaxes(plots);
psdAx.Layout.Row = 1;
psdAx.Title.String = 'Live spectrum';
psdAx.XLabel.String = 'Frequency (MHz)';
psdAx.YLabel.String = 'PSD (dB/Hz)';
psdAx.ButtonDownFcn = @onSpectrumClick;
grid(psdAx, 'on');
hold(psdAx, 'on');
averageLine = plot(psdAx, NaN, NaN, '-', ...
    'Color', [0.10 0.45 0.90], 'LineWidth', 1.0, ...
    'HitTest', 'off', 'DisplayName', 'Average');
maxLine = plot(psdAx, NaN, NaN, '-', ...
    'Color', [0.90 0.35 0.10], 'LineWidth', 0.8, ...
    'HitTest', 'off', 'DisplayName', 'Max Hold');
selectionMarker = plot(psdAx, NaN, NaN, 'v', ...
    'LineStyle', 'none', 'MarkerSize', 8, ...
    'MarkerFaceColor', [0.10 0.75 0.20], ...
    'MarkerEdgeColor', [0.05 0.35 0.10], ...
    'HitTest', 'off', 'DisplayName', 'Selected');
legend(psdAx, 'Location', 'best');
hold(psdAx, 'off');

waterfallAx = uiaxes(plots);
waterfallAx.Layout.Row = 2;
waterfallAx.Title.String = 'Waterfall';
waterfallAx.XLabel.String = 'Frequency (MHz)';
waterfallAx.YLabel.String = 'Logical time (s)';
waterfallAx.ButtonDownFcn = @onSpectrumClick;
waterfallImage = imagesc(waterfallAx, [0 1], [0 1], nan(2));
waterfallImage.HitTest = 'off';
waterfallAx.YDir = 'normal';
colormap(waterfallAx, turbo(256));
colorbar(waterfallAx);

side = uigridlayout(root, [16 2]);
side.Layout.Row = 2;
side.Layout.Column = 2;
side.RowHeight = repmat({28}, 1, 16);
side.ColumnWidth = {110, '1x'};
side.Padding = [8 6 8 6];
sidePanel = uipanel(side, 'Title', 'Selected carrier and decoder');
sidePanel.Layout.Row = [1 16];
sidePanel.Layout.Column = [1 2];
sideGrid = uigridlayout(sidePanel, [15 2]);
sideGrid.RowHeight = {25,25,25,25,25,25,32,32,25,25,25,25,25,'1x',32};
sideGrid.ColumnWidth = {120, '1x'};

placeLabel(sideGrid, 'Offset', 1, 1);
offsetLabel = uilabel(sideGrid, 'Text', '-');
offsetLabel.Layout.Row = 1; offsetLabel.Layout.Column = 2;
placeLabel(sideGrid, 'RF frequency', 2, 1);
rfLabel = uilabel(sideGrid, 'Text', '-');
rfLabel.Layout.Row = 2; rfLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Refine BW', 3, 1);
bandwidthDrop = uidropdown(sideGrid, ...
    'Items', {'6.25 kHz', '12.5 kHz', '25 kHz'}, ...
    'ItemsData', [6250 12500 25000], 'Value', 12500);
bandwidthDrop.Layout.Row = 3; bandwidthDrop.Layout.Column = 2;
placeLabel(sideGrid, 'Protocols', 4, 1);
protocolField = uieditfield(sideGrid, 'text', ...
    'Value', protocolText(options.ProtocolNames));
protocolField.Layout.Row = 4; protocolField.Layout.Column = 2;

runButton = uibutton(sideGrid, 'Text', 'Run identification', ...
    'Enable', 'off', 'ButtonPushedFcn', @onRun);
runButton.Layout.Row = 5; runButton.Layout.Column = [1 2];
stopButton = uibutton(sideGrid, 'Text', 'Stop', ...
    'ButtonPushedFcn', @onStop);
stopButton.Layout.Row = 6; stopButton.Layout.Column = 1;
resetButton = uibutton(sideGrid, 'Text', 'Reset', ...
    'ButtonPushedFcn', @onReset);
resetButton.Layout.Row = 6; resetButton.Layout.Column = 2;
holdButton = uibutton(sideGrid, 'Text', 'Reset Max Hold', ...
    'ButtonPushedFcn', @onResetMaxHold);
holdButton.Layout.Row = 7; holdButton.Layout.Column = [1 2];

placeLabel(sideGrid, 'State', 8, 1);
stateLabel = uilabel(sideGrid, 'Text', 'IDLE', 'FontWeight', 'bold');
stateLabel.Layout.Row = 8; stateLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Winner', 9, 1);
winnerLabel = uilabel(sideGrid, 'Text', '-');
winnerLabel.Layout.Row = 9; winnerLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Epoch', 10, 1);
epochLabel = uilabel(sideGrid, 'Text', '-');
epochLabel.Layout.Row = 10; epochLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Loop', 11, 1);
loopLabel = uilabel(sideGrid, 'Text', '0 / 0');
loopLabel.Layout.Row = 11; loopLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Logical time', 12, 1);
logicalLabel = uilabel(sideGrid, 'Text', '0.000 s');
logicalLabel.Layout.Row = 12; logicalLabel.Layout.Column = 2;
placeLabel(sideGrid, 'Real-time factor', 13, 1);
factorLabel = uilabel(sideGrid, 'Text', '-');
factorLabel.Layout.Row = 13; factorLabel.Layout.Column = 2;
statusArea = uitextarea(sideGrid, 'Editable', 'off', ...
    'Value', {'Open a capture and start preview.'});
statusArea.Layout.Row = 14;
statusArea.Layout.Column = [1 2];
saveButton = uibutton(sideGrid, 'Text', 'Save PDU JSON', ...
    'ButtonPushedFcn', @onSaveJson);
saveButton.Layout.Row = 15; saveButton.Layout.Column = [1 2];

pduTable = uitable(root, ...
    'ColumnName', {'Time s','RF MHz','Protocol','Type','Source', ...
        'Destination','Epoch','Summary'}, ...
    'ColumnWidth', {70,90,70,130,75,85,55,'auto'}, ...
    'Data', cell(0, 8));
pduTable.Layout.Row = 3;
pduTable.Layout.Column = [1 2];

state = struct( ...
    'mode', 'IDLE', ...
    'metadata', [], ...
    'source', [], ...
    'spectrum', [], ...
    'spectrumSnapshot', [], ...
    'scanner', [], ...
    'selection', [], ...
    'pdus', struct([]), ...
    'closedEpochs', struct([]), ...
    'lastDecodeOutput', [], ...
    'lastMessage', '', ...
    'busy', false, ...
    'runTimerToken', [], ...
    'lockInputSample', [], ...
    'replaySpeed', double(options.ReplaySpeed), ...
    'timer', [], ...
    'closing', false);

timerObject = timer( ...
    'ExecutionMode', 'fixedSpacing', ...
    'BusyMode', 'drop', ...
    'Period', 0.04, ...
    'TimerFcn', @onTimerTick, ...
    'ErrorFcn', @onTimerError, ...
    'Name', 'PMRRadioFrontendReplay');
state.timer = timerObject;
fig.CloseRequestFcn = @onClose;

app = struct( ...
    'Figure', fig, ...
    'LoadFile', @loadFilePublic, ...
    'StartPreview', @startPreviewPublic, ...
    'SelectOffsetHz', @selectOffsetPublic, ...
    'SelectFrequencyHz', @selectFrequencyPublic, ...
    'RunIdentification', @runIdentificationPublic, ...
    'Step', @stepPublic, ...
    'Stop', @stopPublic, ...
    'Reset', @resetPublic, ...
    'GetState', @getPublicState, ...
    'Close', @closePublic);

if ~isempty(options.DefaultFile) && exist(options.DefaultFile, 'file') == 2
    pathField.Value = char(options.DefaultFile);
    try
        loadCapture(char(options.DefaultFile));
    catch ME
        setStatus(sprintf('Unable to load default capture: %s', ME.message));
    end
end
if options.AutoStartPreview && ~isempty(state.metadata)
    startPreviewPublic();
end

    function onBrowse(~, ~)
        [name, folder] = uigetfile( ...
            {'*.bvsp;*.rawiq;*.bin;*.wav', 'IQ captures'; '*.*', 'All files'}, ...
            'Select IQ capture');
        if isequal(name, 0), return; end
        pathField.Value = fullfile(folder, name);
        try
            loadCapture(pathField.Value);
        catch ME
            setStatus(ME.message);
        end
    end

    function onPreview(~, ~)
        try
            startPreviewPublic();
        catch ME
            setStatus(sprintf('%s: %s', ME.identifier, ME.message));
        end
    end

    function onRun(~, ~)
        try
            runIdentificationPublic();
        catch ME
            setStatus(sprintf('%s: %s', ME.identifier, ME.message));
            setMode('ERROR');
        end
    end

    function onStop(~, ~)
        stopPublic();
    end

    function onReset(~, ~)
        resetPublic();
    end

    function onResetMaxHold(~, ~)
        if ~isempty(state.spectrum)
            state.spectrum = radio.scope.resetMaxHold(state.spectrum);
            state.spectrumSnapshot = radio.scope.spectrumSnapshot(state.spectrum);
            updateSpectrumPlots();
        end
    end

    function onSpeedChanged(~, ~)
        state.replaySpeed = speedValue(speedDrop.Value);
        if isTimerRunning()
            stop(state.timer);
            configureTimer();
            start(state.timer);
        end
    end

    function onSpectrumClick(sourceAxes, ~)
        if any(strcmp(state.mode, {'WARMING','CLASSIFYING','LOCKED', ...
                'LOSS_PENDING','RECLASSIFYING'}))
            setStatus('Stop the current decoder before changing frequency.');
            return;
        end
        point = sourceAxes.CurrentPoint;
        clickedFrequencyHz = point(1, 1) * 1e6;
        try
            selection = radio.scope.refineCarrier( ...
                state.spectrumSnapshot, clickedFrequencyHz, ...
                'BandwidthHz', bandwidthDrop.Value);
            setSelection(selection);
        catch ME
            setStatus(ME.message);
        end
    end

    function onSaveJson(~, ~)
        if isempty(state.pdus)
            setStatus('No PDU is available to save.');
            return;
        end
        [name, folder] = uiputfile('*.json', 'Save decoded PDUs', ...
            'radio_frontend_pdus.json');
        if isequal(name, 0), return; end
        radio.writeJson(state.pdus, fullfile(folder, name));
        setStatus(sprintf('Saved %d PDUs to %s.', ...
            numel(state.pdus), fullfile(folder, name)));
    end

    function onTimerTick(~, ~)
        if state.busy || state.closing, return; end
        state.busy = true;
        try
            processOneChunk();
        catch ME
            stopTimer();
            setMode('ERROR');
            setStatus(sprintf('%s: %s', ME.identifier, ME.message));
        end
        state.busy = false;
        drawnow limitrate;
    end

    function onTimerError(~, event)
        stopTimer();
        setMode('ERROR');
        message = 'Timer callback failed.';
        try
            message = event.Data.Message;
        catch
        end
        setStatus(message);
    end

    function loadFilePublic(path)
        pathField.Value = char(path);
        loadCapture(char(path));
    end

    function loadCapture(path)
        stopTimer();
        closeSource();
        sampleRate = sampleRateField.Value;
        if sampleRate <= 0, sampleRate = []; end
        centerHz = centerField.Value;
        if centerHz == 0, centerHz = []; end
        metadata = radio.tuned.captureInfo(path, ...
            'SampleRate', sampleRate, ...
            'CenterFrequencyHz', centerHz, ...
            'IqDType', options.IqDType);
        state.metadata = metadata;
        state.spectrum = radio.scope.spectrumInit( ...
            metadata.sampleRateHz, metadata.centerFrequencyHz, ...
            'Config', options.SpectrumConfig);
        state.spectrumSnapshot = radio.scope.spectrumSnapshot(state.spectrum);
        state.scanner = [];
        state.selection = [];
        state.pdus = struct([]);
        state.closedEpochs = struct([]);
        state.lastDecodeOutput = [];
        sampleRateField.Value = metadata.sampleRateHz;
        centerField.Value = metadata.centerFrequencyHz;
        pathField.Value = path;
        metadataLabel.Text = sprintf('%.3f MHz | %.3f s', ...
            metadata.sampleRateHz / 1e6, metadata.durationSec);
        runButton.Enable = 'off';
        pduTable.Data = cell(0, 8);
        averageLine.XData = NaN; averageLine.YData = NaN;
        maxLine.XData = NaN; maxLine.YData = NaN;
        selectionMarker.XData = NaN; selectionMarker.YData = NaN;
        waterfallImage.CData = nan(2);
        setMode('IDLE');
        setStatus(sprintf(['Loaded %s | Fs %.3f MHz | center %.6f MHz | ', ...
            '%d samples.'], metadata.format, metadata.sampleRateHz / 1e6, ...
            metadata.centerFrequencyHz / 1e6, metadata.totalSamples));
    end

    function startPreviewPublic(varargin)
        args = inputParser;
        args.addParameter('StartTimer', true);
        args.parse(varargin{:});
        ensureCaptureCurrent();
        stopTimer();
        closeSource();
        state.source = createSource();
        state.spectrum = radio.scope.spectrumInit( ...
            state.metadata.sampleRateHz, state.metadata.centerFrequencyHz, ...
            'Config', options.SpectrumConfig);
        state.spectrumSnapshot = radio.scope.spectrumSnapshot(state.spectrum);
        state.scanner = [];
        state.pdus = struct([]);
        state.closedEpochs = struct([]);
        state.lockInputSample = [];
        state.runTimerToken = tic;
        pduTable.Data = cell(0, 8);
        setMode('PREVIEW');
        setStatus('Preview replay started. Click a carrier peak to select it.');
        configureTimer();
        if args.Results.StartTimer, start(state.timer); end
    end

    function source = createSource()
        mode = replayDrop.Value;
        maxLoops = loopField.Value;
        if strcmp(mode, 'once'), maxLoops = 1; end
        source = radio.replay.fileLoopSourceInit(state.metadata.path, ...
            'SampleRate', state.metadata.sampleRateHz, ...
            'CenterFrequencyHz', state.metadata.centerFrequencyHz, ...
            'IqDType', options.IqDType, ...
            'HeaderBytes', state.metadata.headerBytes, ...
            'ChunkDurationSec', options.TunedConfig.chunkDurationSec, ...
            'ReplayMode', mode, ...
            'MaxLoops', maxLoops, ...
            'EpochSilenceSec', options.EpochSilenceSec);
    end

    function selection = selectOffsetPublic(offsetHz, varargin)
        args = inputParser;
        args.addParameter('Refine', false);
        args.addParameter('BandwidthHz', bandwidthDrop.Value);
        args.parse(varargin{:});
        validateattributes(offsetHz, {'numeric'}, ...
            {'scalar', 'real', 'finite'});
        ensureSelectionAllowed();
        clickedHz = state.metadata.centerFrequencyHz + offsetHz;
        if args.Results.Refine
            selection = radio.scope.refineCarrier( ...
                state.spectrumSnapshot, clickedHz, ...
                'BandwidthHz', args.Results.BandwidthHz);
        else
            selection = makeSelection(clickedHz, clickedHz, ...
                args.Results.BandwidthHz);
        end
        setSelection(selection);
    end

    function selection = selectFrequencyPublic(frequencyHz, varargin)
        args = inputParser;
        args.addParameter('Refine', true);
        args.addParameter('BandwidthHz', bandwidthDrop.Value);
        args.parse(varargin{:});
        validateattributes(frequencyHz, {'numeric'}, ...
            {'scalar', 'real', 'finite'});
        ensureSelectionAllowed();
        if args.Results.Refine
            selection = radio.scope.refineCarrier( ...
                state.spectrumSnapshot, frequencyHz, ...
                'BandwidthHz', args.Results.BandwidthHz);
        else
            selection = makeSelection( ...
                frequencyHz, frequencyHz, args.Results.BandwidthHz);
        end
        setSelection(selection);
    end

    function ensureSelectionAllowed()
        if isempty(state.metadata)
            error('radio_frontend:NoCapture', 'Load a capture first.');
        end
        if any(strcmp(state.mode, {'WARMING','CLASSIFYING','LOCKED', ...
                'LOSS_PENDING','RECLASSIFYING'}))
            error('radio_frontend:SelectionLocked', ...
                'Stop the decoder before changing frequency.');
        end
    end

    function selection = makeSelection(clickedHz, refinedHz, bandwidthHz)
        selection = struct( ...
            'clickedFrequencyHz', double(clickedHz), ...
            'refinedFrequencyHz', double(refinedHz), ...
            'offsetHz', double(refinedHz - state.metadata.centerFrequencyHz), ...
            'bandwidthHz', double(bandwidthHz), ...
            'searchRadiusHz', 0, ...
            'peakBinFrequencyHz', double(refinedHz), ...
            'peakPower', NaN, ...
            'noisePower', NaN);
    end

    function setSelection(selection)
        state.selection = selection;
        offsetLabel.Text = sprintf('%+.6f MHz', selection.offsetHz / 1e6);
        if state.metadata.centerFrequencyHz ~= 0
            rfLabel.Text = sprintf('%.6f MHz', ...
                selection.refinedFrequencyHz / 1e6);
        else
            rfLabel.Text = 'unknown (offset only)';
        end
        runButton.Enable = 'on';
        updateSelectionMarker();
        setStatus(sprintf('Selected offset %+.3f kHz%s.', ...
            selection.offsetHz / 1e3, rfSuffix(selection.refinedFrequencyHz)));
    end

    function runIdentificationPublic(varargin)
        args = inputParser;
        args.addParameter('StartTimer', true);
        args.parse(varargin{:});
        ensureCaptureCurrent();
        if isempty(state.selection)
            error('radio_frontend:NoCarrier', ...
                'Select a carrier before starting identification.');
        end
        stopTimer();
        closeSource();
        setMode('WARMING');
        setStatus('Warming DDC and protocol worker pool...');
        drawnow;
        protocols = parseProtocols(protocolField.Value);
        tunedConfig = radio.tuned.resolveInputConfig( ...
            state.metadata.sampleRateHz, options.TunedConfig);
        state.scanner = radio.tuned.streamScannerInit( ...
            state.metadata.sampleRateHz, state.selection.offsetHz, ...
            'InputCenterFrequencyHz', state.metadata.centerFrequencyHz, ...
            'Config', tunedConfig, ...
            'StreamConfig', options.StreamConfig, ...
            'ProtocolNames', protocols, ...
            'Mode', options.ParallelMode, ...
            'NumWorkers', options.NumWorkers, ...
            'PoolType', options.PoolType, ...
            'TaskFcn', options.TaskFcn, ...
            'TaskContext', options.TaskContext, ...
            'LockedDecodeFcn', options.LockedDecodeFcn, ...
            'Deduplicate', options.Deduplicate, ...
            'PrewarmDdc', options.PrewarmDdc, ...
            'WarmParallelPool', options.WarmParallelPool);
        state.source = createSource();
        state.spectrum = radio.scope.spectrumInit( ...
            state.metadata.sampleRateHz, state.metadata.centerFrequencyHz, ...
            'Config', options.SpectrumConfig);
        state.spectrumSnapshot = radio.scope.spectrumSnapshot(state.spectrum);
        state.pdus = struct([]);
        state.closedEpochs = struct([]);
        state.lastDecodeOutput = [];
        state.lockInputSample = [];
        state.runTimerToken = tic;
        pduTable.Data = cell(0, 8);
        setMode('CLASSIFYING');
        setStatus(sprintf('Classifying offset %+.3f kHz.', ...
            state.selection.offsetHz / 1e3));
        configureTimer();
        if args.Results.StartTimer, start(state.timer); end
    end

    function public = stepPublic(count)
        if nargin < 1, count = 1; end
        validateattributes(count, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'integer', 'positive'});
        stopTimer();
        for k = 1:count
            if isempty(state.source) || state.source.closed || state.source.terminal
                break;
            end
            processOneChunk();
        end
        public = getPublicState();
    end

    function processOneChunk()
        if isempty(state.source)
            error('radio_frontend:NoSource', ...
                'Start preview or identification before processing data.');
        end
        [state.source, chunk, done, replayEvent] = ...
            radio.replay.fileLoopSourceRead(state.source);
        if isempty(chunk)
            finishAtSourceEnd();
            return;
        end
        [state.spectrum, spectrumOutput] = ...
            radio.scope.spectrumFeed(state.spectrum, chunk);
        if spectrumOutput.updated
            state.spectrumSnapshot = ...
                radio.scope.spectrumSnapshot(state.spectrum);
            updateSpectrumPlots();
        end

        if ~isempty(state.scanner) && ~state.scanner.finalized
            [state.scanner, decodeOutput] = ...
                radio.tuned.streamScannerFeed(state.scanner, chunk);
            state.lastDecodeOutput = decodeOutput;
            if ~isempty(decodeOutput.newPdus)
                state.pdus = state.scanner.pdus;
                updatePduTable();
            end
            if ~isempty(decodeOutput.closedEpochs)
                state.closedEpochs = state.scanner.closedEpochs;
            end
            applyDecoderState(decodeOutput, chunk);
        end
        updateRuntimeLabels(replayEvent);

        if shouldAutoStop(chunk)
            finishIdentification('post-lock interval completed');
            return;
        end
        logicalSec = double(state.source.globalNextSample) / ...
            state.metadata.sampleRateHz;
        if ~isempty(state.scanner) && options.MaxLogicalDurationSec > 0 && ...
                logicalSec >= options.MaxLogicalDurationSec
            finishIdentification('maximum logical duration reached');
            return;
        end
        if done
            finishAtSourceEnd();
        end
    end

    function applyDecoderState(output, chunk)
        coordinatorState = output.state;
        if ~isempty(output.selectedProtocol)
            winnerLabel.Text = output.selectedProtocol;
        elseif ~isempty(state.scanner.lastSelectedProtocol)
            winnerLabel.Text = state.scanner.lastSelectedProtocol;
        end
        if output.epochId ~= 0
            epochLabel.Text = sprintf('%d', output.epochId);
        end
        switch coordinatorState
            case 'LOCKED'
                setMode('LOCKED');
                if isempty(state.lockInputSample)
                    state.lockInputSample = chunk.sourceSampleEnd;
                    setStatus(sprintf('Protocol locked: %s.', ...
                        state.scanner.lastSelectedProtocol));
                end
            case {'LOSS_PENDING','RECLASSIFYING','AMBIGUOUS','UNKNOWN','ERROR'}
                setMode(coordinatorState);
            case {'CLASSIFYING','CATCHING_UP','ACTIVITY_PENDING'}
                if ~strcmp(state.mode, 'LOCKED')
                    setMode(coordinatorState);
                end
            case 'NO_SIGNAL'
                if ~strcmp(state.mode, 'PREVIEW')
                    setMode('NO_SIGNAL');
                end
        end
    end

    function stopPublic()
        stopTimer();
        if ~isempty(state.scanner) && ~state.scanner.finalized
            try
                [state.scanner, report] = ...
                    radio.tuned.streamScannerFinalize( ...
                        state.scanner, 'WaitForTasks', false);
                state.pdus = state.scanner.pdus;
                state.closedEpochs = state.scanner.closedEpochs;
                updatePduTable();
                if ~isempty(report.selectedProtocol)
                    winnerLabel.Text = report.selectedProtocol;
                end
            catch ME
                setStatus(sprintf('Finalize warning: %s', ME.message));
            end
        end
        closeSource();
        setMode('STOPPED');
        setStatus('Replay stopped.');
    end

    function finishIdentification(reason)
        stopTimer();
        if ~isempty(state.scanner) && ~state.scanner.finalized
            setMode('FINALIZING');
            setStatus('Waiting for pending protocol and catch-up tasks...');
            drawnow;
            [state.scanner, report] = ...
                radio.tuned.streamScannerFinalize(state.scanner);
            state.pdus = state.scanner.pdus;
            state.closedEpochs = state.scanner.closedEpochs;
            updatePduTable();
            if ~isempty(report.selectedProtocol)
                winnerLabel.Text = report.selectedProtocol;
            end
            if report.finalizeTaskWaitTimedOut
                reason = sprintf('%s; asynchronous task wait timed out', reason);
            end
        end
        closeSource();
        setMode('COMPLETED');
        setStatus(sprintf('Identification completed: %s.', reason));
    end

    function finishAtSourceEnd()
        if isempty(state.scanner)
            stopTimer();
            closeSource();
            setMode('COMPLETED');
            setStatus('Preview source reached its configured end.');
        else
            finishIdentification('replay source completed');
        end
    end

    function tf = shouldAutoStop(chunk)
        tf = false;
        if isempty(state.scanner) || isempty(state.lockInputSample) || ...
                options.ContinueAfterLockSec <= 0
            return;
        end
        elapsedSamples = double(chunk.sourceSampleEnd - ...
            uint64(state.lockInputSample));
        tf = elapsedSamples / state.metadata.sampleRateHz >= ...
            options.ContinueAfterLockSec;
    end

    function resetPublic()
        stopTimer();
        closeSource();
        state.scanner = [];
        state.pdus = struct([]);
        state.closedEpochs = struct([]);
        state.lastDecodeOutput = [];
        state.lockInputSample = [];
        pduTable.Data = cell(0, 8);
        winnerLabel.Text = '-';
        epochLabel.Text = '-';
        loopLabel.Text = '0 / 0';
        logicalLabel.Text = '0.000 s';
        factorLabel.Text = '-';
        if ~isempty(state.metadata)
            state.spectrum = radio.scope.spectrumInit( ...
                state.metadata.sampleRateHz, ...
                state.metadata.centerFrequencyHz, ...
                'Config', options.SpectrumConfig);
            state.spectrumSnapshot = ...
                radio.scope.spectrumSnapshot(state.spectrum);
        end
        setMode('IDLE');
        setStatus('Frontend state reset. The carrier selection is retained.');
    end

    function closePublic()
        onClose([], []);
    end

    function onClose(~, ~)
        if state.closing, return; end
        state.closing = true;
        stopTimer();
        closeSource();
        try
            if isvalid(state.timer), delete(state.timer); end
        catch
        end
        if isvalid(fig), delete(fig); end
    end

    function closeSource()
        if ~isempty(state.source) && isstruct(state.source) && ...
                isfield(state.source, 'closed') && ~state.source.closed
            state.source = radio.replay.fileLoopSourceClose(state.source);
        end
    end

    function ensureCaptureCurrent()
        path = char(pathField.Value);
        if isempty(path)
            error('radio_frontend:NoPath', 'Choose an IQ capture first.');
        end
        fieldsChanged = false;
        if ~isempty(state.metadata)
            fieldsChanged = (sampleRateField.Value > 0 && ...
                sampleRateField.Value ~= state.metadata.sampleRateHz) || ...
                centerField.Value ~= state.metadata.centerFrequencyHz;
        end
        if isempty(state.metadata) || ~strcmp(state.metadata.path, path) || ...
                fieldsChanged
            loadCapture(path);
        end
    end

    function configureTimer()
        if isTimerRunning(), stop(state.timer); end
        chunkSec = options.TunedConfig.chunkDurationSec;
        if isinf(state.replaySpeed)
            period = 0.001;
        else
            period = max(0.001, chunkSec / state.replaySpeed);
        end
        state.timer.Period = period;
    end

    function stopTimer()
        if isTimerRunning(), stop(state.timer); end
    end

    function tf = isTimerRunning()
        tf = false;
        try
            tf = isvalid(state.timer) && strcmp(state.timer.Running, 'on');
        catch
        end
    end

    function updateSpectrumPlots()
        snapshot = state.spectrumSnapshot;
        if isempty(snapshot) || ~snapshot.hasEstimate, return; end
        xMHz = snapshot.frequencyHz ./ 1e6;
        averageLine.XData = xMHz;
        averageLine.YData = 10 .* log10(snapshot.averagePsd + 1e-20);
        maxLine.XData = xMHz;
        maxLine.YData = 10 .* log10(snapshot.maxHoldPsd + 1e-20);
        xlim(psdAx, [xMHz(1), xMHz(end)]);
        updateSelectionMarker();

        if ~isempty(snapshot.waterfallPsd)
            waterfallImage.XData = [snapshot.displayFrequencyHz(1), ...
                snapshot.displayFrequencyHz(end)] ./ 1e6;
            times = snapshot.waterfallTimeSec;
            if numel(times) == 1
                waterfallImage.YData = times(1) + [-0.001 0.001];
            else
                waterfallImage.YData = [times(1), times(end)];
            end
            waterfallImage.CData = 10 .* log10( ...
                double(snapshot.waterfallPsd) + 1e-20);
            xlim(waterfallAx, [xMHz(1), xMHz(end)]);
        end
    end

    function updateSelectionMarker()
        if isempty(state.selection) || isempty(state.spectrumSnapshot) || ...
                ~state.spectrumSnapshot.hasEstimate
            return;
        end
        frequency = state.selection.refinedFrequencyHz;
        [~, index] = min(abs( ...
            state.spectrumSnapshot.frequencyHz - frequency));
        markerDb = 10 .* log10( ...
            state.spectrumSnapshot.maxHoldPsd(index) + 1e-20);
        selectionMarker.XData = frequency / 1e6;
        selectionMarker.YData = markerDb;
    end

    function updatePduTable()
        rows = cell(numel(state.pdus), 8);
        lines = radio.formatLines(state.pdus);
        basebandRateHz = state.scanner.basebandSampleRateHz;
        for k = 1:numel(state.pdus)
            sample = radio.getNestedField( ...
                state.pdus(k), 'extra.stream.source_sample', uint64(0));
            rows{k, 1} = double(sample) / basebandRateHz;
            rows{k, 2} = state.selection.refinedFrequencyHz / 1e6;
            rows{k, 3} = state.pdus(k).protocol;
            rows{k, 4} = state.pdus(k).type;
            rows{k, 5} = valueText(radio.getField(state.pdus(k), 'src', ''));
            rows{k, 6} = valueText(radio.getField(state.pdus(k), 'dst', ''));
            rows{k, 7} = double(radio.getNestedField( ...
                state.pdus(k), 'extra.stream.epoch_id', uint64(0)));
            if k <= numel(lines), rows{k, 8} = lines{k}; else, rows{k, 8} = ''; end
        end
        pduTable.Data = rows;
    end

    function updateRuntimeLabels(event)
        if isempty(state.source), return; end
        loopLabel.Text = sprintf('%d / %s', state.source.completedLoops, ...
            loopLimitText(state.source.maxLoops));
        logicalSec = double(state.source.globalNextSample) / ...
            state.metadata.sampleRateHz;
        logicalLabel.Text = sprintf('%.3f s', logicalSec);
        if ~isempty(state.runTimerToken) && logicalSec > 0
            factorLabel.Text = sprintf('%.3f', toc(state.runTimerToken) / logicalSec);
        end
        if event.loopEnded
            setStatus(sprintf('Replay loop %d completed (%s).', ...
                event.completedLoops, valueOr(event.boundary, 'next loop')));
        end
    end

    function setMode(mode)
        state.mode = char(mode);
        stateLabel.Text = state.mode;
    end

    function setStatus(message)
        state.lastMessage = char(message);
        statusArea.Value = splitlines(string(message));
    end

    function public = getPublicState()
        sourceInfo = [];
        if ~isempty(state.source)
            sourceInfo = struct( ...
                'replayMode', state.source.replayMode, ...
                'currentLoop', state.source.currentLoop, ...
                'completedLoops', state.source.completedLoops, ...
                'globalNextSample', state.source.globalNextSample, ...
                'terminal', state.source.terminal, ...
                'closed', state.source.closed);
        end
        scannerInfo = [];
        if ~isempty(state.scanner)
            scannerInfo = struct( ...
                'state', state.scanner.coordinator.state, ...
                'selectedProtocol', state.scanner.lastSelectedProtocol, ...
                'feedCount', state.scanner.feedCount, ...
                'inputSampleCount', state.scanner.inputSampleCount, ...
                'basebandSampleCount', state.scanner.basebandSampleCount, ...
                'basebandPendingSampleCount', ...
                    uint64(state.scanner.basebandPendingCount), ...
                'coordinatorChunkSamples', ...
                    state.scanner.coordinatorChunkSamples, ...
                'finalized', state.scanner.finalized, ...
                'finalizeTaskWaitElapsedSec', ...
                    state.scanner.finalizeTaskWaitElapsedSec, ...
                'finalizeTaskWaitTimedOut', ...
                    state.scanner.finalizeTaskWaitTimedOut, ...
                'warmupElapsedSec', state.scanner.warmupElapsedSec, ...
                'poolInfo', state.scanner.poolInfo);
        end
        public = struct( ...
            'mode', state.mode, ...
            'metadata', state.metadata, ...
            'source', sourceInfo, ...
            'selection', state.selection, ...
            'spectrum', state.spectrumSnapshot, ...
            'scanner', scannerInfo, ...
            'pdus', state.pdus, ...
            'closedEpochs', state.closedEpochs, ...
            'lastMessage', state.lastMessage, ...
            'timerRunning', isTimerRunning());
    end

    function text = rfSuffix(frequencyHz)
        if state.metadata.centerFrequencyHz == 0
            text = '';
        else
            text = sprintf(', RF %.6f MHz', frequencyHz / 1e6);
        end
    end
end

function validateOptions(options)
validateattributes(options.ReplaySpeed, {'numeric'}, ...
    {'scalar', 'real', 'positive'});
validateattributes(options.MaxLoops, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(options.EpochSilenceSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(options.ContinueAfterLockSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(options.MaxLogicalDurationSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});
end

function path = defaultCapture()
candidate = '/home/lzkj/lzkj_workspace/DMR_signal/1.bvsp';
if exist(candidate, 'file') == 2
    path = candidate;
else
    path = '';
end
end

function value = scalarOr(value, fallback)
if isempty(value), value = fallback; end
value = double(value);
end

function mode = normalizeReplayMode(value)
mode = lower(strrep(char(value), '_', '-'));
if strcmp(mode, 'continuous'), mode = 'continuous-test'; end
if strcmp(mode, 'epoch'), mode = 'epoch-repeat'; end
if ~any(strcmp(mode, {'once','continuous-test','epoch-repeat'}))
    error('radio_frontend:ReplayMode', 'Unsupported replay mode: %s', mode);
end
end

function text = speedText(speed)
if isinf(speed), text = 'unlimited'; return; end
items = [0.1 0.25 0.5 1];
[distance, index] = min(abs(items - speed));
if distance > 1e-9
    error('radio_frontend:ReplaySpeed', ...
        'ReplaySpeed must be 0.1, 0.25, 0.5, 1, or Inf.');
end
text = sprintf('%gx', items(index));
end

function value = speedValue(text)
if strcmp(text, 'unlimited')
    value = inf;
else
    value = sscanf(text, '%fx', 1);
end
end

function text = protocolText(protocols)
if isempty(protocols)
    text = 'all';
else
    text = strjoin(protocols, ',');
end
end

function protocols = parseProtocols(text)
text = strtrim(char(text));
if isempty(text) || strcmpi(text, 'all')
    protocols = {};
    return;
end
protocols = regexp(text, '[,;\s]+', 'split');
protocols = protocols(~cellfun(@isempty, protocols));
protocols = radio.normalizeProtocolNames(protocols);
end

function text = valueText(value)
if ischar(value) || isstring(value)
    text = char(value);
elseif isnumeric(value) && isscalar(value)
    text = num2str(value);
else
    text = '';
end
end

function text = loopLimitText(value)
if isinf(value), text = 'Inf'; else, text = sprintf('%d', value); end
end

function value = valueOr(value, fallback)
if isempty(value), value = fallback; end
end

function label = placeLabel(parent, text, row, column)
%PLACELABEL Create a label using syntax supported by MATLAB R2022b.
label = uilabel(parent, 'Text', text);
label.Layout.Row = row;
label.Layout.Column = column;
end
