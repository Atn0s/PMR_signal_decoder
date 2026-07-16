function app = radio_live_frontend(varargin)
%RADIO_LIVE_FRONTEND Lean 1x file-replay spectrum and multi-carrier UI.
% File production and PSD run on background workers.  A shared-memory IQ
% ring connects the producer to a reserved DDC process without UI relay;
% protocol work uses the remaining process workers.
p = inputParser;
p.addParameter('DefaultFile', defaultCapture());
p.addParameter('Visible', 'on');
p.addParameter('SampleRate', []);
p.addParameter('CenterFrequencyHz', []);
p.addParameter('IqDType', 'int16');
p.addParameter('ReplayMode', 'continuous-test');
p.addParameter('MaxLoops', inf);
p.addParameter('EpochSilenceSec', 0.4);
p.addParameter('InputChunkDurationSec', 0.020);
p.addParameter('PlayoutDelaySec', 0.10);
p.addParameter('MaxChunksPerTick', 16);
p.addParameter('MaxCarrierPaths', 5);
p.addParameter('DecoderQueueLimitSec', 15.0);
p.addParameter('DecoderCatchupChunksPerTick', 8);
p.addParameter('DecoderCatchupBudgetSec', 0.030);
p.addParameter('DecoderCatchupMaxBudgetSec', 0.080);
p.addParameter('UseAsyncFrontend', true);
p.addParameter('FrontendWorkerReserve', 1);
p.addParameter('ProducerQueueLimitSec', 2.0);
p.addParameter('SpectrumQueueLimitChunks', 12);
p.addParameter('ProtocolNames', {});
p.addParameter('ParallelMode', 'parallel');
p.addParameter('NumWorkers', 5);
p.addParameter('PoolType', 'processes');
p.addParameter('SpectrumConfig', radio.scope.defaultConfig());
p.addParameter('TunedConfig', radio.tuned.defaultConfig());
p.addParameter('StreamConfig', radio.stream.defaultConfig());
p.addParameter('TaskFcn', []);
p.addParameter('TaskContext', struct());
p.addParameter('LockedDecodeFcn', []);
p.addParameter('Deduplicate', false);
p.addParameter('PrintToCommandWindow', true);
p.addParameter('PrewarmDdc', true);
p.addParameter('UseFusedDdc', true);
p.addParameter('WarmParallelPool', true);
p.addParameter('PrewarmProtocols', true);
p.addParameter('ProbeMaxInFlightPerChannel', []);
p.addParameter('EarlyProbeConfirm', true);
p.addParameter('EarlyProbeConfirmMinConfidence', 0.99);
p.addParameter('CandidateGateEnabled', true);
p.addParameter('AutoStartPreview', false);
p.parse(varargin{:});
options = p.Results;
validateOptions(options);
parallelMode = lower(char(options.ParallelMode));
asyncConfigured = logical(options.UseAsyncFrontend) && ...
    logical(options.UseFusedDdc) && ...
    any(strcmp(parallelMode, {'auto', 'parallel'}));

fig = uifigure('Name', 'PMR 1x Live Multi-Carrier Frontend', ...
    'Position', [100 80 1320 760], 'Visible', char(options.Visible));
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
    'ButtonPushedFcn', @onBrowse);
browseButton.Layout.Row = 1; browseButton.Layout.Column = 9;
previewButton = uibutton(controls, 'Text', 'Preview 1x', ...
    'ButtonPushedFcn', @onPreview);
previewButton.Layout.Row = 1; previewButton.Layout.Column = 10;

placeLabel(controls, 'Fs', 2, 1);
fsField = uieditfield(controls, 'numeric', 'Limits', [0 Inf], ...
    'Value', scalarOr(options.SampleRate, 0));
fsField.Layout.Row = 2; fsField.Layout.Column = 2;
placeLabel(controls, 'Center', 2, 3);
centerField = uieditfield(controls, 'numeric', ...
    'Value', scalarOr(options.CenterFrequencyHz, 0));
centerField.Layout.Row = 2; centerField.Layout.Column = 4;
clearButton = uibutton(controls, 'Text', 'Clear carriers', ...
    'ButtonPushedFcn', @onClearCarriers);
clearButton.Layout.Row = 2; clearButton.Layout.Column = 5;
runButton = uibutton(controls, 'Text', 'Run decode', 'Enable', 'off', ...
    'ButtonPushedFcn', @onRun);
runButton.Layout.Row = 2; runButton.Layout.Column = 6;
stopButton = uibutton(controls, 'Text', 'Stop', ...
    'ButtonPushedFcn', @onStop);
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
ax.ButtonDownFcn = @onSpectrumClick;

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
hintLabel = uilabel(sideGrid, ...
    'Text', 'Protocol workers are asynchronous; semantic dedup is off.');
hintLabel.Layout.Row = 10; hintLabel.Layout.Column = [1 2];

console = uitextarea(root, 'Editable', 'off', ...
    'Value', {'Load a capture and start 1x preview.'});
console.Layout.Row = 3; console.Layout.Column = [1 2];

state = struct( ...
    'mode', 'IDLE', ...
    'metadata', [], ...
    'source', [], ...
    'spectrum', [], ...
    'snapshot', [], ...
    'asyncEnabled', asyncConfigured, ...
    'producerActor', [], ...
    'spectrumActor', [], ...
    'ddcActor', [], ...
    'sharedIqRing', [], ...
    'producerRunning', false, ...
    'producerTerminal', false, ...
    'ddcResultQueue', {cell(0, 1)}, ...
    'ddcResultQueueHead', 1, ...
    'ddcResultQueueSamples', uint64(0), ...
    'ddcFlushComplete', false, ...
    'selections', emptySelections(), ...
    'scanner', [], ...
    'scannerBuildFuture', [], ...
    'scannerBuildToken', [], ...
    'scannerRequestedSample', uint64(0), ...
    'scannerReadySample', [], ...
    'decoderQueue', {cell(0, 1)}, ...
    'decoderQueueHead', 1, ...
    'decoderQueueSamples', uint64(0), ...
    'runtimePrepared', false, ...
    'runtimeWorkersWarmed', false, ...
    'runtimePoolInfo', [], ...
    'runtimeWarmReport', [], ...
    'runtimeClientWarmReport', [], ...
    'preparedDdcStates', {cell(0, 1)}, ...
    'preparedFusedDdcState', [], ...
    'pdus', struct([]), ...
    'log', {cell(0, 1)}, ...
    'timer', [], ...
    'clockToken', [], ...
    'clockBaseSample', uint64(0), ...
    'busy', false, ...
    'closing', false, ...
    'inputLagSec', 0, ...
    'maxInputLagSec', 0, ...
    'maxProducerLagSec', 0, ...
    'maxProducerQueueSec', 0, ...
    'maxDdcInputQueueSec', 0, ...
    'maxDdcResultQueueSec', 0, ...
    'maxDecoderPipelineQueueSec', 0, ...
    'asyncCoordinatorCount', uint64(0), ...
    'asyncCoordinatorTotalSec', 0, ...
    'asyncCoordinatorMaxSec', 0, ...
    'lastUiUpdateSec', 0, ...
    'lastDecoderSummaryKey', '', ...
    'lastSpectrumDrawCount', uint64(0));
timerObject = timer('ExecutionMode', 'fixedRate', 'BusyMode', 'drop', ...
    'Period', options.InputChunkDurationSec, 'TimerFcn', @onTimer, ...
    'ErrorFcn', @onTimerError, 'Name', 'PMRLeanLiveReplay');
state.timer = timerObject;
fig.CloseRequestFcn = @onClose;
fig.DeleteFcn = @onFigureDeleted;

app = struct( ...
    'Figure', fig, ...
    'LoadFile', @loadFilePublic, ...
    'StartPreview', @startPreviewPublic, ...
    'AddOffsetHz', @addOffsetPublic, ...
    'AddFrequencyHz', @addFrequencyPublic, ...
    'ClearCarriers', @clearCarriersPublic, ...
    'RunIdentification', @runPublic, ...
    'Step', @stepPublic, ...
    'Stop', @stopPublic, ...
    'GetState', @getStatePublic, ...
    'Close', @closePublic);

if ~isempty(options.DefaultFile) && exist(options.DefaultFile, 'file') == 2
    pathField.Value = char(options.DefaultFile);
    try
        loadCapture(pathField.Value);
    catch ME
        appendLog(sprintf('Load failed: %s', ME.message));
    end
end
if options.AutoStartPreview && ~isempty(state.metadata)
    startPreviewPublic();
end

    function onBrowse(~, ~)
        [name, folder] = uigetfile( ...
            {'*.bvsp;*.rawiq;*.bin;*.wav','IQ captures';'*.*','All files'});
        if isequal(name, 0), return; end
        loadFilePublic(fullfile(folder, name));
    end

    function onPreview(~, ~)
        try, startPreviewPublic(); catch ME, fail(ME); end
    end

    function onRun(~, ~)
        try, runPublic(); catch ME, fail(ME); end
    end

    function onStop(~, ~)
        try, stopPublic(); catch ME, fail(ME); end
    end

    function onClearCarriers(~, ~)
        try, clearCarriersPublic(); catch ME, fail(ME); end
    end

    function onSpectrumClick(source, ~)
        if isempty(state.snapshot) || ~state.snapshot.hasEstimate, return; end
        clickedHz = source.CurrentPoint(1, 1) * 1e6;
        try
            addFrequencyPublic(clickedHz, 'Refine', true, ...
                'BandwidthHz', bwDrop.Value);
        catch ME
            fail(ME);
        end
    end

    function onTimer(~, ~)
        upgradeState();
        if state.busy || state.closing, return; end
        state.busy = true;
        try
            processDueChunks();
        catch ME
            stopTimer();
            fail(ME);
        end
        state.busy = false;
    end

    function onTimerError(~, event)
        stopTimer();
        message = 'Timer callback failed.';
        try, message = event.Data.Message; catch, end
        setMode('ERROR');
        appendLog(message);
    end

    function loadFilePublic(path)
        pathField.Value = char(path);
        loadCapture(char(path));
    end

    function loadCapture(path)
        upgradeState();
        stopTimer(); discardDecoder('capture_changed'); closeSource();
        sampleRate = fsField.Value;
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
        state.snapshot = radio.scope.spectrumSnapshot( ...
            state.spectrum, 'IncludeWaterfall', false);
        state.scanner = [];
        state.runtimePrepared = false;
        state.runtimeWorkersWarmed = false;
        state.runtimePoolInfo = [];
        state.preparedDdcStates = cell(0, 1);
        state.pdus = struct([]);
        state.selections = emptySelections();
        fsField.Value = metadata.sampleRateHz;
        centerField.Value = metadata.centerFrequencyHz;
        metadataLabel.Text = sprintf('%.3f MHz | %.1f s', ...
            metadata.sampleRateHz / 1e6, metadata.durationSec);
        [resolved, rateReport] = radio.tuned.resolveInputConfig( ...
            metadata.sampleRateHz, options.TunedConfig);
        ddcLabel.Text = sprintf('%.0f kS/s (/%d)', ...
            resolved.outputSampleRateHz / 1e3, rateReport.decimationFactor);
        clearSelectionUi();
        setMode('IDLE');
        appendLog(sprintf('Loaded %s, Fs %.3f MHz, duration %.3f s.', ...
            metadata.format, metadata.sampleRateHz / 1e6, ...
            metadata.durationSec));
    end

    function startPreviewPublic(varargin)
        upgradeState();
        q = inputParser; q.addParameter('StartTimer', true); q.parse(varargin{:});
        ensureCapture();
        stopTimer(); discardDecoder('preview_restarted'); closeSource();
        ensureDecodeRuntimePrepared();
        if state.asyncEnabled
            startAsyncSource();
        else
            state.source = createSource();
            state.spectrum = radio.scope.spectrumInit( ...
                state.metadata.sampleRateHz, ...
                state.metadata.centerFrequencyHz, ...
                'Config', options.SpectrumConfig);
            state.snapshot = radio.scope.spectrumSnapshot( ...
                state.spectrum, 'IncludeWaterfall', false);
        end
        state.pdus = struct([]);
        state.clockToken = tic;
        state.clockBaseSample = uint64(0);
        state.inputLagSec = 0; state.maxInputLagSec = 0;
        state.maxProducerLagSec = 0;
        state.maxProducerQueueSec = 0;
        state.maxDdcInputQueueSec = 0;
        state.maxDdcResultQueueSec = 0;
        state.maxDecoderPipelineQueueSec = 0;
        state.asyncCoordinatorCount = uint64(0);
        state.asyncCoordinatorTotalSec = 0;
        state.asyncCoordinatorMaxSec = 0;
        state.lastUiUpdateSec = 0;
        setMode('PREVIEW');
        appendLog('1x preview started; click PSD peaks to add carriers.');
        if q.Results.StartTimer
            resumeReplayClock();
            start(state.timer);
        end
    end

    function selection = addOffsetPublic(offsetHz, varargin)
        ensureCapture();
        selection = addFrequencyPublic( ...
            state.metadata.centerFrequencyHz + offsetHz, varargin{:});
    end

    function selection = addFrequencyPublic(frequencyHz, varargin)
        q = inputParser;
        q.addParameter('Refine', true);
        q.addParameter('BandwidthHz', bwDrop.Value);
        q.parse(varargin{:});
        ensureCapture();
        if isDecoderActive()
            error('radio_live_frontend:DecoderRunning', ...
                'Clear the active decoder before changing carrier selections.');
        end
        if q.Results.Refine
            selection = radio.scope.refineCarrier( ...
                state.snapshot, frequencyHz, ...
                'BandwidthHz', q.Results.BandwidthHz);
        else
            selection = makeSelection(frequencyHz, q.Results.BandwidthHz);
        end
        updatedSelections = upsertSelection(state.selections, selection);
        if numel(updatedSelections) > options.MaxCarrierPaths
            error('radio_live_frontend:TooManyCarriers', ...
                'At most %d carrier paths can be selected.', ...
                options.MaxCarrierPaths);
        end
        state.selections = updatedSelections;
        updateSelectionUi();
        appendLog(sprintf('Carrier %+.3f kHz selected.', ...
            selection.offsetHz / 1e3));
    end

    function clearCarriersPublic()
        upgradeState();
        decoderWasActive = isDecoderActive();
        discardDecoder('carrier_selection_cleared');
        state.selections = emptySelections();
        state.pdus = struct([]);
        clearSelectionUi();
        if hasLiveSource()
            setMode('PREVIEW');
            if decoderWasActive
                appendLog(sprintf([ ...
                    'Decoder detached and carriers cleared at %.3f s; ', ...
                    'spectrum replay continues without rewind.'], ...
                    sourceLogicalSec()));
            else
                appendLog('Carrier selections cleared; spectrum replay continues.');
            end
        else
            appendLog('Carrier selections cleared.');
        end
    end

    function runPublic(varargin)
        upgradeState();
        q = inputParser; q.addParameter('StartTimer', true); q.parse(varargin{:});
        ensureCapture();
        if isempty(state.selections)
            error('radio_live_frontend:NoCarrier', ...
                'Select at least one carrier first.');
        end
        if isDecoderActive()
            error('radio_live_frontend:DecoderRunning', ...
                'A decoder is already active. Clear carriers before rerunning.');
        end
        if ~hasLiveSource()
            appendLog('No active preview source; starting a new replay explicitly.');
            startPreviewPublic('StartTimer', false);
        else
            ensureDecodeRuntimePrepared();
        end
        [tunedConfig, rateReport] = radio.tuned.resolveInputConfig( ...
            state.metadata.sampleRateHz, options.TunedConfig);
        offsets = [state.selections.offsetHz].';
        state.pdus = struct([]);
        pduLabel.Text = '0'; winnerLabel.Text = '-';
        ddcLabel.Text = sprintf('%.0f kS/s (/%d)', ...
            rateReport.outputSampleRateHz / 1e3, rateReport.decimationFactor);
        startScannerBuild(offsets, tunedConfig);
        runButton.Enable = 'off';
        if q.Results.StartTimer && ~isTimerRunning()
            resumeReplayClock();
            start(state.timer);
        end
    end

    function public = stepPublic(count)
        upgradeState();
        if nargin < 1, count = 1; end
        stopTimer();
        if state.asyncEnabled
            startSample = state.source.globalNextSample;
            state.producerActor = radio.live.fileProducerCommand( ...
                state.producerActor, 'step', count);
            targetSample = startSample + uint64(round( ...
                count * options.InputChunkDurationSec * ...
                state.metadata.sampleRateHz));
            token = tic;
            while state.source.globalNextSample < targetSample && ...
                    ~state.source.terminal && toc(token) < 30
                processAsyncPipeline();
                pause(0.001);
            end
            while asyncDecoderQueueSamples() > 0 && toc(token) < 30
                processAsyncPipeline();
                pause(0.001);
            end
            processAsyncPipeline();
        else
            for k = 1:count
                if isempty(state.source) || state.source.terminal, break; end
                pollScannerBuild();
                processOneChunk();
                drainDecoderQueue(inf, inf);
            end
            pollScannerBuild();
            drainDecoderQueue(inf, inf);
        end
        if ~isempty(state.source) && state.source.terminal
            finishSource();
        end
        public = getStatePublic();
    end

    function processDueChunks()
        if isempty(state.source), return; end
        if state.asyncEnabled
            processAsyncPipeline();
            return;
        end
        pollScannerBuild();
        elapsed = toc(state.clockToken);
        targetSec = max(0, elapsed - options.PlayoutDelaySec);
        targetSample = state.clockBaseSample + ...
            uint64(floor(targetSec * state.metadata.sampleRateHz));
        processed = 0;
        while state.source.globalNextSample < targetSample && ...
                processed < options.MaxChunksPerTick && ...
                ~state.source.terminal
            processOneChunk();
            if ~isempty(state.scanner) && ...
                    isempty(state.scannerBuildFuture) && ...
                    ~decoderQueueIsEmpty()
                % Keep the normal 1x path block-synchronous.  The queue is
                % retained for asynchronous attachment and exceptional
                % catch-up, not as an avoidable second playout buffer.
                drainDecoderQueue(1, inf);
            end
            processed = processed + 1;
        end
        pollScannerBuild();
        drainDecoderQueue(options.DecoderCatchupChunksPerTick, ...
            options.DecoderCatchupBudgetSec);
        elapsed = toc(state.clockToken);
        currentTargetSample = state.clockBaseSample + uint64(floor( ...
            max(0, elapsed - options.PlayoutDelaySec) * ...
            state.metadata.sampleRateHz));
        state.inputLagSec = max(0, double(currentTargetSample - min( ...
            currentTargetSample, state.source.globalNextSample)) / ...
            state.metadata.sampleRateHz);
        state.maxInputLagSec = max(state.maxInputLagSec, state.inputLagSec);
        if elapsed - state.lastUiUpdateSec >= 0.1 || state.source.terminal
            updateRuntimeLabels(elapsed);
            state.lastUiUpdateSec = elapsed;
        end
        if state.source.terminal
            finishSource();
        end
    end

    function processOneChunk()
        [state.source, chunk, done, event] = ...
            radio.replay.fileLoopSourceRead(state.source);
        if isempty(chunk), return; end
        [state.spectrum, spectrumOutput] = ...
            radio.scope.spectrumFeed(state.spectrum, chunk);
        if spectrumOutput.updated
            state.snapshot = radio.scope.spectrumSnapshot( ...
                state.spectrum, 'IncludeWaterfall', false);
            updateSpectrum();
        end
        if isDecoderActive()
            enqueueDecoderChunk(chunk);
        end
        if event.loopEnded
            appendLog(sprintf('Replay loop %d completed.', event.completedLoops));
        end
        if done
            state.source.terminal = true;
        end
    end

    function startAsyncSource()
        if ~isempty(state.sharedIqRing)
            radio.live.sharedIqRingDelete(state.sharedIqRing);
        end
        chunkSamples = max(1, round(options.InputChunkDurationSec * ...
            state.metadata.sampleRateHz));
        state.sharedIqRing = radio.live.sharedIqRingCreate( ...
            state.metadata.sampleRateHz, chunkSamples, ...
            'CenterFrequencyHz', state.metadata.centerFrequencyHz, ...
            'CapacitySec', options.ProducerQueueLimitSec);
        state.spectrumActor = radio.live.spectrumActorStart( ...
            state.metadata.sampleRateHz, ...
            state.metadata.centerFrequencyHz, ...
            'Config', options.SpectrumConfig, ...
            'MaxQueueChunks', options.SpectrumQueueLimitChunks);
        startPreviewDdcActor();
        waitForSpectrumActor();
        producerCfg = struct( ...
            'path', state.metadata.path, ...
            'sampleRateHz', state.metadata.sampleRateHz, ...
            'centerFrequencyHz', state.metadata.centerFrequencyHz, ...
            'iqDType', options.IqDType, ...
            'headerBytes', state.metadata.headerBytes, ...
            'chunkDurationSec', options.InputChunkDurationSec, ...
            'replayMode', options.ReplayMode, ...
            'maxLoops', options.MaxLoops, ...
            'epochSilenceSec', options.EpochSilenceSec, ...
            'playoutDelaySec', options.PlayoutDelaySec, ...
            'directFanout', true, ...
            'sharedRing', state.sharedIqRing, ...
            'maxQueueChunks', max(2, ceil( ...
                options.ProducerQueueLimitSec / ...
                options.InputChunkDurationSec)));
        state.producerActor = radio.live.fileProducerStart(producerCfg);
        state.producerActor = radio.live.fileProducerAttachSpectrum( ...
            state.producerActor, state.spectrumActor);
        initialSpectrum = radio.scope.spectrumInit( ...
            state.metadata.sampleRateHz, ...
            state.metadata.centerFrequencyHz, ...
            'Config', options.SpectrumConfig);
        state.snapshot = radio.scope.spectrumSnapshot( ...
            initialSpectrum, 'IncludeWaterfall', false);
        state.source = struct( ...
            'globalNextSample', uint64(0), ...
            'completedLoops', uint64(0), ...
            'terminal', false, ...
            'closed', false);
        state.producerRunning = false;
        state.producerTerminal = false;
        state.ddcResultQueue = cell(0, 1);
        state.ddcResultQueueHead = 1;
        state.ddcResultQueueSamples = uint64(0);
        state.ddcFlushComplete = false;
        state.spectrum = [];
    end

    function waitForSpectrumActor()
        token = tic;
        while ~state.spectrumActor.ready && ...
                ~state.spectrumActor.failed && toc(token) < 5
            [state.spectrumActor, snapshot] = ...
                radio.live.spectrumActorPoll(state.spectrumActor);
            if ~isempty(snapshot), state.snapshot = snapshot; end
            if ~state.spectrumActor.ready, pause(0.001); end
        end
        if ~state.spectrumActor.ready
            error('radio_live_frontend:SpectrumActorStartup', ...
                'Spectrum consumer did not become ready: %s', ...
                state.spectrumActor.errorReason);
        end
    end

    function startPreviewDdcActor()
        if ~isempty(state.ddcActor) && state.ddcActor.ready && ...
                ~state.ddcActor.failed && ~state.ddcActor.stopped && ...
                state.ddcActor.processedInputSamples == 0
            return;
        end
        [tunedConfig, ~] = radio.tuned.resolveInputConfig( ...
            state.metadata.sampleRateHz, options.TunedConfig);
        [pool, info] = radio.stream.acquireParallelPool( ...
            'NumWorkers', runtimeWorkerCount(), ...
            'PoolType', options.PoolType, ...
            'AllowCreate', false);
        if isempty(pool) || ~info.available || ...
                pool.NumWorkers <= options.NumWorkers
            error('radio_live_frontend:AsyncDdcPool', ...
                ['The separated DDC consumer requires %d protocol workers ', ...
                 'plus at least one reserved process worker.'], ...
                options.NumWorkers);
        end
        spec = struct( ...
            'buildOnWorker', true, ...
            'initialConfigured', false, ...
            'inputSampleRateHz', state.metadata.sampleRateHz, ...
            'frequencyOffsetsHz', 0, ...
            'config', tunedConfig, ...
            'inputCenterFrequencyHz', ...
                state.metadata.centerFrequencyHz, ...
            'capacity', options.MaxCarrierPaths, ...
            'prewarm', logical(options.PrewarmDdc));
        state.ddcActor = radio.live.ddcActorStart( ...
            pool, spec, 'MaxQueueSec', options.DecoderQueueLimitSec);
        appendLog('Prewarming the reserved DDC worker before replay.');
        token = tic;
        while ~state.ddcActor.ready && ~state.ddcActor.failed && ...
                toc(token) < 30
            [state.ddcActor, ~] = radio.live.ddcActorPoll(state.ddcActor);
            if ~state.ddcActor.ready
                pause(0.005);
                drawnow limitrate;
            end
        end
        if ~state.ddcActor.ready
            error('radio_live_frontend:AsyncDdcStartup', ...
                'Reserved DDC worker failed to start: %s', ...
                state.ddcActor.errorReason);
        end
        appendLog(sprintf('Reserved DDC worker ready in %.3f s.', toc(token)));
    end

    function processAsyncPipeline()
        coordinatorToken = tic;
        pollScannerBuild();
        [state.producerActor, producerEvents] = ...
            radio.live.fileProducerPoll(state.producerActor, ...
                'MaxEvents', options.MaxChunksPerTick);
        for eventIndex = 1:numel(producerEvents)
            handleProducerEvent(producerEvents{eventIndex});
        end

        % Acquisition and ordered decoder consumption take precedence over
        % best-effort rendering.  PSD computation continues independently
        % even when this coordinator needs a short catch-up burst.
        pollAsyncDdc();
        pollScannerBuild();
        [drainChunks, drainBudgetSec] = asyncDrainAllowance();
        drainAsyncDdcResults(drainChunks, drainBudgetSec);

        [state.spectrumActor, latestSnapshot] = ...
            radio.live.spectrumActorPoll(state.spectrumActor);
        if ~isempty(latestSnapshot)
            state.snapshot = latestSnapshot;
            updateSpectrum();
        end

        producerQueueSec = double(asyncProducerRelaySamples()) / ...
            state.metadata.sampleRateHz;
        producerLagSec = state.producerActor.productionLagSec;
        ddcInputQueueSec = 0;
        if ~isempty(state.ddcActor)
            ddcInputQueueSec = double(asyncDdcInputQueueSamples()) / ...
                state.metadata.sampleRateHz;
        end
        ddcResultQueueSec = double(state.ddcResultQueueSamples) / ...
            state.metadata.sampleRateHz;
        decoderPipelineQueueSec = ddcInputQueueSec + ddcResultQueueSec;
        state.inputLagSec = max([ ...
            producerLagSec, ...
            producerQueueSec, ...
            decoderPipelineQueueSec]);
        state.maxInputLagSec = max(state.maxInputLagSec, state.inputLagSec);
        state.maxProducerLagSec = max( ...
            state.maxProducerLagSec, producerLagSec);
        state.maxProducerQueueSec = max( ...
            state.maxProducerQueueSec, producerQueueSec);
        state.maxDdcInputQueueSec = max( ...
            state.maxDdcInputQueueSec, ddcInputQueueSec);
        state.maxDdcResultQueueSec = max( ...
            state.maxDdcResultQueueSec, ddcResultQueueSec);
        state.maxDecoderPipelineQueueSec = max( ...
            state.maxDecoderPipelineQueueSec, decoderPipelineQueueSec);
        coordinatorElapsedSec = toc(coordinatorToken);
        state.asyncCoordinatorCount = state.asyncCoordinatorCount + uint64(1);
        state.asyncCoordinatorTotalSec = ...
            state.asyncCoordinatorTotalSec + coordinatorElapsedSec;
        state.asyncCoordinatorMaxSec = max( ...
            state.asyncCoordinatorMaxSec, coordinatorElapsedSec);
        elapsed = toc(state.clockToken);
        if elapsed - state.lastUiUpdateSec >= 0.1 || ...
                state.source.terminal
            updateRuntimeLabels(elapsed);
            state.lastUiUpdateSec = elapsed;
        end

        if state.producerTerminal
            if isDecoderActive() && ~isempty(state.ddcActor)
                if ~state.ddcActor.ringAttached && ...
                        ~state.ddcActor.ringDrained && ...
                        ~state.ddcActor.flushRequested
                    state.ddcActor = ...
                        radio.live.ddcActorFlush(state.ddcActor);
                end
                if state.ddcActor.flushed && ...
                        asyncDecoderQueueSamples() == 0 && ...
                        asyncDdcResultQueueIsEmpty()
                    finishSource();
                end
            elseif asyncDdcResultQueueIsEmpty()
                finishSource();
            end
        end
    end

    function [maxChunks, budgetSec] = asyncDrainAllowance()
        maxChunks = options.DecoderCatchupChunksPerTick;
        budgetSec = options.DecoderCatchupBudgetSec;
        readySec = double(state.ddcResultQueueSamples) / ...
            state.metadata.sampleRateHz;
        if readySec <= options.InputChunkDurationSec
            return;
        end
        % A single long classification submission can temporarily create
        % several ready blocks.  Give the control plane a bounded burst to
        % recover instead of processing exactly one block forever.
        readyChunks = ceil(readySec / options.InputChunkDurationSec);
        maxChunks = min(options.MaxChunksPerTick, ...
            max(maxChunks, readyChunks));
        budgetSec = max(budgetSec, min( ...
            options.DecoderCatchupMaxBudgetSec, readySec));
    end

    function handleProducerEvent(event)
        switch char(event.type)
            case 'chunk'
                transport = struct('chunk', event.chunk, ...
                    'payload', event.payload);
                if ~state.producerActor.directFanout
                    state.spectrumActor = radio.live.spectrumActorSubmit( ...
                        state.spectrumActor, transport);
                end
                if isDecoderActive() && ...
                        (isempty(state.sharedIqRing) || ...
                         ~state.producerActor.sharedRingEnabled)
                    if isempty(state.ddcActor)
                        error('radio_live_frontend:AsyncDdcMissing', ...
                            'Decoder is active without its DDC consumer.');
                    end
                    state.ddcActor = radio.live.ddcActorSubmit( ...
                        state.ddcActor, transport);
                end
                state.source.globalNextSample = ...
                    uint64(event.sourceSampleEnd);
                state.source.completedLoops = ...
                    uint64(event.completedLoops);
                if event.event.loopEnded
                    appendLog(sprintf('Replay loop %d completed.', ...
                        event.event.completedLoops));
                end
            case 'progress'
                state.source.globalNextSample = ...
                    uint64(event.sourceSampleEnd);
                state.source.completedLoops = ...
                    uint64(event.completedLoops);
                if event.event.loopEnded
                    appendLog(sprintf('Replay loop %d completed.', ...
                        event.event.completedLoops));
                end
            case 'terminal'
                state.producerTerminal = true;
                state.source.terminal = true;
                state.source.globalNextSample = ...
                    uint64(event.sourceSampleEnd);
                state.source.completedLoops = ...
                    uint64(event.completedLoops);
            case 'error'
                state.producerTerminal = true;
                state.source.terminal = true;
                error('radio_live_frontend:ProducerFailed', ...
                    '%s', event.errorReason);
        end
    end

    function pollAsyncDdc()
        if isempty(state.ddcActor), return; end
        [state.ddcActor, ddcEvents] = radio.live.ddcActorPoll( ...
            state.ddcActor, 'MaxEvents', options.MaxChunksPerTick);
        for eventIndex = 1:numel(ddcEvents)
            event = ddcEvents{eventIndex};
            switch char(event.type)
                case {'baseband', 'flushed'}
                    state.ddcResultQueue{end+1, 1} = event;
                    count = uint64(radio.getField( ...
                        event.widebandDescriptor, ...
                        'transportSampleCount', uint64(0)));
                    state.ddcResultQueueSamples = ...
                        state.ddcResultQueueSamples + count;
                    if strcmp(event.type, 'flushed')
                        state.ddcFlushComplete = true;
                    end
                case 'error'
                    error('radio_live_frontend:DdcActorFailed', ...
                        '%s', event.errorReason);
            end
        end
    end

    function drainAsyncDdcResults(maxChunks, budgetSec)
        if isempty(state.scanner) || state.scanner.finalized || ...
                asyncDdcResultQueueIsEmpty()
            return;
        end
        token = tic;
        processed = 0;
        while ~asyncDdcResultQueueIsEmpty() && processed < maxChunks
            if processed > 0 && toc(token) >= budgetSec, break; end
            event = state.ddcResultQueue{state.ddcResultQueueHead};
            state.ddcResultQueue{state.ddcResultQueueHead} = [];
            state.ddcResultQueueHead = state.ddcResultQueueHead + 1;
            count = uint64(radio.getField(event.widebandDescriptor, ...
                'transportSampleCount', uint64(0)));
            state.ddcResultQueueSamples = ...
                state.ddcResultQueueSamples - ...
                min(state.ddcResultQueueSamples, count);
            [state.scanner, multiOutput] = ...
                radio.tuned.multiStreamScannerFeedBasebands( ...
                    state.scanner, event.widebandDescriptor, ...
                    event.basebandChunks, ...
                    'DdcElapsedSec', event.computeSec);
            if ~isempty(multiOutput.newPdus)
                state.pdus = state.scanner.pdus;
                printPdus(multiOutput.newPdus);
            end
            printStateEvents(multiOutput);
            processed = processed + 1;
        end
        compactAsyncDdcResultQueue();
        if processed > 0 && ~isempty(state.scanner)
            updateDecoderSummary();
        end
    end

    function tf = asyncDdcResultQueueIsEmpty()
        tf = state.ddcResultQueueHead > numel(state.ddcResultQueue);
    end

    function compactAsyncDdcResultQueue()
        if asyncDdcResultQueueIsEmpty()
            state.ddcResultQueue = cell(0, 1);
            state.ddcResultQueueHead = 1;
        elseif state.ddcResultQueueHead > 64 && ...
                state.ddcResultQueueHead > numel(state.ddcResultQueue) / 2
            state.ddcResultQueue = state.ddcResultQueue( ...
                state.ddcResultQueueHead:end);
            state.ddcResultQueueHead = 1;
        end
    end

    function count = asyncDecoderQueueSamples()
        count = asyncDdcInputQueueSamples() + state.ddcResultQueueSamples;
    end

    function count = asyncDdcInputQueueSamples()
        count = asyncProducerRelaySamples();
        if ~isempty(state.ddcActor)
            count = count + state.ddcActor.pendingInputSamples;
        end
    end

    function count = asyncProducerRelaySamples()
        count = uint64(0);
        if ~isempty(state.producerActor) && ...
                state.producerActor.sharedRingEnabled
            return;
        end
        if isempty(state.producerActor) || ...
                ~state.producerActor.decoderArmed
            return;
        end
        count = uint64(state.producerActor.outputQueue.QueueLength) * ...
            uint64(round(options.InputChunkDurationSec * ...
                state.metadata.sampleRateHz));
    end

    function ensureDecodeRuntimePrepared()
        if state.runtimePrepared, return; end
        state.runtimePrepared = true;
        state.runtimeWorkersWarmed = false;
        mode = lower(char(options.ParallelMode));
        if ~options.WarmParallelPool || ...
                ~any(strcmp(mode, {'auto', 'parallel'}))
            return;
        end

        setMode('PREPARING');
        appendLog([ ...
            'Preparing process workers and DDC runtime before preview; ', ...
            'this one-time step prevents Run Decode from freezing the PSD.']);
        drawnow;
        token = tic;
        requestedWorkers = runtimeWorkerCount();
        [pool, info] = radio.stream.acquireParallelPool( ...
            'NumWorkers', requestedWorkers, ...
            'PoolType', options.PoolType);
        if state.asyncEnabled && ~isempty(pool) && ...
                pool.NumWorkers < requestedWorkers
            appendLog(sprintf([ ...
                'Existing pool has %d workers; recreating it with %d so ', ...
                'DDC has a reserved process.'], ...
                pool.NumWorkers, requestedWorkers));
            delete(pool);
            [pool, info] = radio.stream.acquireParallelPool( ...
                'NumWorkers', requestedWorkers, ...
                'PoolType', options.PoolType);
        end
        state.runtimePoolInfo = info;
        if isempty(pool) || ~info.available
            appendLog(sprintf([ ...
                'Parallel runtime unavailable (%s); protocol probes will ', ...
                'fall back according to their execution mode.'], info.reason));
        elseif options.PrewarmProtocols && isempty(options.TaskFcn)
            warmReport = radio.stream.prewarmProtocolWorkers( ...
                options.ProtocolNames, ...
                'Pool', pool, ...
                'NumWorkers', requestedWorkers, ...
                'PoolType', options.PoolType);
            state.runtimeWarmReport = warmReport;
            state.runtimeWorkersWarmed = warmReport.success;
            if warmReport.success
                appendLog(sprintf([ ...
                    'All protocol entry points warmed on %d workers in ', ...
                    '%.3f s.'], warmReport.numWorkers, ...
                    warmReport.elapsedSec));
            else
                appendLog(sprintf('Protocol worker warm-up incomplete: %s', ...
                    warmReport.errorReason));
            end
            clientWarm = radio.stream.prewarmClientRuntime( ...
                pool, options.ProtocolNames, 'PoolType', options.PoolType);
            state.runtimeClientWarmReport = clientWarm;
            if ~clientWarm.success
                appendLog(sprintf('Client runtime warm-up incomplete: %s', ...
                    clientWarm.errorReason));
            end
        else
            state.runtimeWorkersWarmed = true;
        end

        [tunedConfig, ~] = radio.tuned.resolveInputConfig( ...
            state.metadata.sampleRateHz, options.TunedConfig);
        if options.PrewarmDdc && ~state.asyncEnabled
            if options.UseFusedDdc
                state.preparedFusedDdcState = ...
                    radio.tuned.multiDdcInit( ...
                        state.metadata.sampleRateHz, ...
                        zeros(options.MaxCarrierPaths, 1), ...
                        'Config', tunedConfig, ...
                        'InputCenterFrequencyHz', ...
                            state.metadata.centerFrequencyHz, ...
                        'Capacity', options.MaxCarrierPaths, ...
                        'Prewarm', true);
            else
                prepared = cell(options.MaxCarrierPaths, 1);
                for pathIndex = 1:options.MaxCarrierPaths
                    ddc = radio.tuned.ddcInit( ...
                        state.metadata.sampleRateHz, 0, ...
                        'Config', tunedConfig, ...
                        'InputCenterFrequencyHz', ...
                            state.metadata.centerFrequencyHz, ...
                        'ChannelId', pathIndex, ...
                        'MixerMode', 'external');
                    converter = ddc.converter;
                    converter(complex(zeros(ddc.inputBlockSamples, 1)));
                    reset(converter);
                    ddc.converter = converter;
                    prepared{pathIndex} = ddc;
                end
                state.preparedDdcStates = prepared;
            end
        end
        appendLog(sprintf('Decoder runtime prepared in %.3f s.', ...
            toc(token)));
    end

    function startScannerBuild(offsets, tunedConfig)
        ringSnapshot = [];
        if state.asyncEnabled && ~isempty(state.sharedIqRing)
            ringSnapshot = ...
                radio.live.sharedIqRingSnapshot(state.sharedIqRing);
            state.scannerRequestedSample = ringSnapshot.sourceSampleEnd;
        else
            state.scannerRequestedSample = state.source.globalNextSample;
        end
        state.scannerReadySample = [];
        state.decoderQueue = cell(0, 1);
        state.decoderQueueHead = 1;
        state.decoderQueueSamples = uint64(0);
        if ~decoderQueueIsEmpty()
            error('radio_live_frontend:DecoderQueueReset', ...
                'Decoder queue reset left %d entries.', ...
                numel(state.decoderQueue));
        end
        state.scannerBuildToken = tic;
        if state.asyncEnabled
            startAsyncDdc(offsets, tunedConfig, ringSnapshot);
        end
        args = scannerInitArguments(offsets, tunedConfig);

        hasPreparedFused = options.UseFusedDdc && ...
            ~isempty(state.preparedFusedDdcState);
        if state.asyncEnabled || hasPreparedFused || ...
                numel(state.preparedDdcStates) >= numel(offsets)
            setMode('ATTACHING');
            scanner = radio.tuned.multiStreamScannerInit(args{:});
            attachScanner(scanner);
            return;
        end

        [pool, poolInfo] = availableBuildPool();
        if ~isempty(pool) && poolInfo.available
            state.scannerBuildFuture = parfeval(pool, ...
                @radio.tuned.multiStreamScannerInit, 1, args{:});
            setMode('ATTACHING');
            appendLog(sprintf([ ...
                'Decoder build queued for %d carrier(s) at logical %.3f s; ', ...
                'PSD replay remains live and IQ is queued from this sample.'], ...
                numel(offsets), sourceLogicalSec()));
            return;
        end

        setMode('ATTACHING');
        appendLog(sprintf([ ...
            'Attaching %d carrier(s) on the client process; the input ', ...
            'source will not be reopened.'], numel(offsets)));
        scanner = radio.tuned.multiStreamScannerInit(args{:});
        attachScanner(scanner);
    end

    function args = scannerInitArguments(offsets, tunedConfig)
        prepared = cell(0, 1);
        fusedState = state.preparedFusedDdcState;
        if state.asyncEnabled, fusedState = []; end
        if ~options.UseFusedDdc && ...
                numel(state.preparedDdcStates) >= numel(offsets)
            prepared = state.preparedDdcStates(1:numel(offsets));
        end
        args = {state.metadata.sampleRateHz, offsets, ...
            'InputCenterFrequencyHz', state.metadata.centerFrequencyHz, ...
            'Config', tunedConfig, ...
            'StreamConfig', options.StreamConfig, ...
            'ProtocolNames', options.ProtocolNames, ...
            'Mode', options.ParallelMode, ...
            'NumWorkers', options.NumWorkers, ...
            'PoolType', options.PoolType, ...
            'TaskFcn', options.TaskFcn, ...
            'TaskContext', options.TaskContext, ...
            'LockedDecodeFcn', options.LockedDecodeFcn, ...
            'Deduplicate', options.Deduplicate, ...
            'PrewarmDdc', options.PrewarmDdc && ~state.asyncEnabled, ...
            'WarmParallelPool', false, ...
            'DdcStates', prepared, ...
            'ProbeMaxInFlightPerChannel', ...
                options.ProbeMaxInFlightPerChannel, ...
            'EarlyProbeConfirm', options.EarlyProbeConfirm, ...
            'EarlyProbeConfirmMinConfidence', ...
                options.EarlyProbeConfirmMinConfidence, ...
            'CandidateGateEnabled', options.CandidateGateEnabled};
        args = [args, { ...
            'UseFusedDdc', options.UseFusedDdc, ...
            'FusedDdcState', fusedState, ...
            'ExternalBaseband', state.asyncEnabled}];
    end

    function [pool, info] = availableBuildPool()
        pool = [];
        info = struct('available', false, 'reason', 'serial_mode');
        mode = lower(char(options.ParallelMode));
        if ~any(strcmp(mode, {'auto', 'parallel'})), return; end
        if options.WarmParallelPool && ~state.runtimeWorkersWarmed, return; end
        [pool, info] = radio.stream.acquireParallelPool( ...
            'NumWorkers', options.NumWorkers, ...
            'PoolType', options.PoolType, ...
            'AllowCreate', false);
    end

    function count = runtimeWorkerCount()
        count = double(options.NumWorkers);
        if state.asyncEnabled
            count = count + double(options.FrontendWorkerReserve);
        end
    end

    function startAsyncDdc(offsets, tunedConfig, ringSnapshot)
        state.ddcResultQueue = cell(0, 1);
        state.ddcResultQueueHead = 1;
        state.ddcResultQueueSamples = uint64(0);
        state.ddcFlushComplete = false;
        if ~isempty(state.ddcActor) && state.ddcActor.ready && ...
                ~state.ddcActor.failed && ~state.ddcActor.stopped && ...
                state.ddcActor.processedInputSamples == 0
            state.ddcActor = radio.live.ddcActorRetarget( ...
                state.ddcActor, offsets, ...
                state.metadata.centerFrequencyHz);
            state.ddcActor = radio.live.ddcActorAttachRing( ...
                state.ddcActor, state.sharedIqRing, ...
                ringSnapshot.nextSequence, ringSnapshot.sourceSampleEnd);
            return;
        end
        if ~isempty(state.ddcActor)
            state.ddcActor = radio.live.ddcActorStop(state.ddcActor);
        end
        ddcState = struct( ...
            'buildOnWorker', true, ...
            'initialConfigured', true, ...
            'inputSampleRateHz', state.metadata.sampleRateHz, ...
            'frequencyOffsetsHz', double(offsets(:)), ...
            'config', tunedConfig, ...
            'inputCenterFrequencyHz', ...
                state.metadata.centerFrequencyHz, ...
            'capacity', options.MaxCarrierPaths, ...
            'prewarm', logical(options.PrewarmDdc));
        [pool, info] = radio.stream.acquireParallelPool( ...
            'NumWorkers', runtimeWorkerCount(), ...
            'PoolType', options.PoolType, ...
            'AllowCreate', false);
        if isempty(pool) || ~info.available || ...
                pool.NumWorkers <= options.NumWorkers
            error('radio_live_frontend:AsyncDdcPool', ...
                ['The separated DDC consumer requires %d protocol workers ', ...
                 'plus at least one reserved process worker.'], ...
                options.NumWorkers);
        end
        state.ddcActor = radio.live.ddcActorStart( ...
            pool, ddcState, 'MaxQueueSec', options.DecoderQueueLimitSec);
        state.ddcActor = radio.live.ddcActorAttachRing( ...
            state.ddcActor, state.sharedIqRing, ...
            ringSnapshot.nextSequence, ringSnapshot.sourceSampleEnd);
    end

    function pollScannerBuild()
        if isempty(state.scannerBuildFuture), return; end
        future = state.scannerBuildFuture;
        try
            finished = strcmp(char(future.State), 'finished');
        catch
            finished = true;
        end
        if ~finished, return; end
        state.scannerBuildFuture = [];
        try
            scanner = fetchOutputs(future);
        catch ME
            state.decoderQueue = cell(0, 1);
            state.decoderQueueHead = 1;
            state.decoderQueueSamples = uint64(0);
            setMode('ERROR');
            runButton.Enable = valueOnOff(~isempty(state.selections));
            appendLog(sprintf('Decoder attachment failed: %s', ME.message));
            return;
        end
        attachScanner(scanner);
    end

    function attachScanner(scanner)
        scanner.timerToken = tic;
        for channelIndex = 1:scanner.channelCount
            scanner.channels{channelIndex}.timerToken = tic;
        end
        state.scanner = scanner;
        state.lastDecoderSummaryKey = '';
        if state.decoderQueueSamples == 0 && ~decoderQueueIsEmpty()
            error('radio_live_frontend:DecoderQueueAttach', ...
                'Decoder attachment introduced %d queue entries.', ...
                numel(state.decoderQueue));
        end
        if hasLiveSource() || (~isempty(state.source) && state.source.terminal)
            state.scannerReadySample = state.source.globalNextSample;
        else
            state.scannerReadySample = state.scannerRequestedSample;
        end
        buildSec = toc(state.scannerBuildToken);
        queuedSec = double(state.decoderQueueSamples) / ...
            state.metadata.sampleRateHz;
        setMode('RUNNING');
        appendLog(sprintf([ ...
            'Decoder attached in %.3f s at logical %.3f s; %.3f s of ', ...
            'post-click IQ is queued for ordered catch-up (no replay rewind).'], ...
            buildSec, double(state.scannerReadySample) / ...
            state.metadata.sampleRateHz, queuedSec));
    end

    function enqueueDecoderChunk(chunk)
        radio.stream.validateIqChunk(chunk);
        queuedChunk = chunk;
        queuedChunk.iq = single(chunk.iq);
        queueIndex = numel(state.decoderQueue) + 1;
        state.decoderQueue{queueIndex, 1} = queuedChunk;
        if ~isstruct(state.decoderQueue{queueIndex})
            error('radio_live_frontend:DecoderQueueWrite', ...
                'Decoder queue stored %s instead of an IQ chunk.', ...
                class(state.decoderQueue{queueIndex}));
        end
        state.decoderQueueSamples = state.decoderQueueSamples + ...
            uint64(numel(chunk.iq));
        queueSamples = state.decoderQueueSamples;
        if state.asyncEnabled
            queueSamples = asyncDecoderQueueSamples();
        end
        queueSec = double(queueSamples) / state.metadata.sampleRateHz;
        if queueSec <= options.DecoderQueueLimitSec, return; end
        discardDecoder('decoder_queue_overrun');
        setMode('ERROR');
        runButton.Enable = valueOnOff(~isempty(state.selections));
        appendLog(sprintf([ ...
            'Decoder queue exceeded %.3f s. Decode was canceled rather ', ...
            'than silently dropping IQ; spectrum replay continues.'], ...
            options.DecoderQueueLimitSec));
    end

    function drainDecoderQueue(maxChunks, budgetSec)
        if isempty(state.scanner) || state.scanner.finalized || ...
                decoderQueueIsEmpty()
            return;
        end
        token = tic;
        processed = 0;
        while ~decoderQueueIsEmpty() && processed < maxChunks
            if processed > 0 && toc(token) >= budgetSec, break; end
            chunk = state.decoderQueue{state.decoderQueueHead};
            if ~isstruct(chunk)
                error('radio_live_frontend:DecoderQueueType', ...
                    ['Decoder queue returned %s instead of an IQ chunk ', ...
                    '(remaining=%d, processed=%d).'], ...
                    class(chunk), decoderQueueCount(), processed);
            end
            state.decoderQueue{state.decoderQueueHead} = [];
            state.decoderQueueHead = state.decoderQueueHead + 1;
            state.decoderQueueSamples = state.decoderQueueSamples - ...
                uint64(numel(chunk.iq));
            chunk.iq = double(chunk.iq);
            try
                [state.scanner, multiOutput] = ...
                    radio.tuned.multiStreamScannerFeed(state.scanner, chunk);
            catch ME
                discardDecoder('decoder_feed_error');
                setMode('ERROR');
                runButton.Enable = valueOnOff(~isempty(state.selections));
                appendLog(sprintf([ ...
                    'Decoder feed failed while PSD replay continues: %s'], ...
                    ME.message));
                return;
            end
            if ~isempty(multiOutput.newPdus)
                state.pdus = state.scanner.pdus;
                printPdus(multiOutput.newPdus);
            end
            printStateEvents(multiOutput);
            processed = processed + 1;
        end
        compactDecoderQueue();
        if processed > 0 && ~isempty(state.scanner)
            updateDecoderSummary();
        end
    end

    function updateRuntimeLabels(wallSec)
        if isempty(state.source), return; end
        logicalSec = double(state.source.globalNextSample) / ...
            state.metadata.sampleRateHz;
        timeLabel.Text = sprintf('%.3f s', logicalSec);
        lagLabel.Text = sprintf('%.0f ms (max %.0f)', ...
            1e3 * state.inputLagSec, 1e3 * state.maxInputLagSec);
        if logicalSec > 0
            rtfLabel.Text = sprintf('%.3f', wallSec / logicalSec);
        end
        queueSec = double(state.decoderQueueSamples) / ...
            state.metadata.sampleRateHz;
        if ~isempty(state.scannerBuildFuture)
            hintLabel.Text = sprintf([ ...
                'Decoder attaching; %.2f s IQ queued (limit %.1f s). ', ...
                'PSD remains live.'], queueSec, options.DecoderQueueLimitSec);
        elseif queueSec > 0
            hintLabel.Text = sprintf( ...
                'Decoder catching up: %.2f s backlog; PSD remains live.', ...
                queueSec);
        else
            hintLabel.Text = ...
                'Protocol workers are asynchronous; semantic dedup is off.';
        end
    end

    function printStateEvents(output)
        for channel = 1:numel(output.channelOutputs)
            item = output.channelOutputs{channel};
            c = item.coordinator;
            if isempty(c), continue; end
            if isfield(c, 'channel') && ~isempty(c.channel)
                events = c.channel.events;
                for n = 1:numel(events)
                    if strcmp(events(n).toState, 'CLASSIFYING')
                        appendLog(sprintf('SIGNAL_ON ch%d %+.3f kHz epoch %d', ...
                            channel, state.selections(channel).offsetHz / 1e3, ...
                            c.epochId));
                    end
                end
            end
            for n = 1:numel(c.events)
                if any(strcmp(c.events(n).type, ...
                        {'PROTOCOL_CONFIRMED','PROTOCOL_SWITCH_CONFIRMED'}))
                    appendLog(sprintf('LOCK ch%d %s epoch %d', ...
                        channel, c.events(n).protocol, c.epochId));
                end
            end
        end
    end

    function printPdus(pdus)
        lines = radio.formatLines(pdus);
        for k = 1:numel(pdus)
            channel = double(radio.getNestedField( ...
                pdus(k), 'extra.tuned.channel_id', uint64(0)));
            if k <= numel(lines), body = lines{k}; else, body = pdus(k).type; end
            appendLog(sprintf('PDU ch%d %s', channel, body), false);
        end
        refreshLog();
        pduLabel.Text = sprintf('%d', numel(state.pdus));
    end

    function updateDecoderSummary()
        winners = cell(state.scanner.channelCount, 1);
        states = cell(state.scanner.channelCount, 1);
        for k = 1:state.scanner.channelCount
            channel = state.scanner.channels{k};
            winners{k} = valueOr(channel.lastSelectedProtocol, '-');
            states{k} = channel.coordinator.state;
        end
        summaryKey = strjoin([states(:); winners(:)], '|');
        if strcmp(summaryKey, state.lastDecoderSummaryKey)
            return;
        end
        state.lastDecoderSummaryKey = summaryKey;
        winnerLabel.Text = strjoin(winners, ' | ');
        if all(strcmp(states, 'LOCKED'))
            setMode('LOCKED');
        elseif any(strcmp(states, 'ERROR'))
            setMode('ERROR');
        elseif ~strcmp(state.mode, 'RUNNING')
            setMode('RUNNING');
        end
    end

    function stopPublic()
        upgradeState();
        stopTimer();
        discardDecoder('manual_stop');
        closeSource();
        setMode('STOPPED');
        appendLog('Replay stopped.');
    end

    function finishSource()
        if ~isempty(state.source) && state.source.closed && ...
                strcmp(state.mode, 'COMPLETED')
            return;
        end
        stopTimer();
        if ~isempty(state.scannerBuildFuture)
            setMode('FINALIZING');
            appendLog([ ...
                'Input ended while decoder attachment was pending; ', ...
                'waiting so queued IQ is not discarded.']);
            drawnow;
            try
                wait(state.scannerBuildFuture);
                pollScannerBuild();
            catch ME
                discardDecoder('scanner_build_failed_at_eof');
                appendLog(sprintf('Decoder attachment warning: %s', ME.message));
            end
        end
        drainDecoderQueue(inf, inf);
        if state.asyncEnabled
            pollAsyncDdc();
            drainAsyncDdcResults(inf, inf);
        end
        if ~isempty(state.scanner) && ~state.scanner.finalized
            setMode('FINALIZING');
            previousPduCount = numel(state.pdus);
            [state.scanner, ~] = ...
                radio.tuned.multiStreamScannerFinalize(state.scanner, ...
                    'FlushDdc', ~state.asyncEnabled);
            state.pdus = state.scanner.pdus;
            if numel(state.pdus) > previousPduCount
                printPdus(state.pdus(previousPduCount+1:end));
            end
            pduLabel.Text = sprintf('%d', numel(state.pdus));
        end
        if state.asyncEnabled && ~isempty(state.ddcActor)
            state.ddcActor = radio.live.ddcActorStop(state.ddcActor);
        end
        closeSource();
        setMode('COMPLETED');
        appendLog('Configured replay completed.');
    end

    function source = createSource()
        source = radio.replay.fileLoopSourceInit(state.metadata.path, ...
            'SampleRate', state.metadata.sampleRateHz, ...
            'CenterFrequencyHz', state.metadata.centerFrequencyHz, ...
            'IqDType', options.IqDType, ...
            'HeaderBytes', state.metadata.headerBytes, ...
            'ChunkDurationSec', options.InputChunkDurationSec, ...
            'ReplayMode', options.ReplayMode, ...
            'MaxLoops', options.MaxLoops, ...
            'EpochSilenceSec', options.EpochSilenceSec);
    end

    function selection = makeSelection(frequencyHz, bandwidthHz)
        selection = struct( ...
            'clickedFrequencyHz', double(frequencyHz), ...
            'refinedFrequencyHz', double(frequencyHz), ...
            'offsetHz', double(frequencyHz - state.metadata.centerFrequencyHz), ...
            'bandwidthHz', double(bandwidthHz), ...
            'searchRadiusHz', 0, 'peakBinFrequencyHz', double(frequencyHz), ...
            'peakPower', NaN, 'noisePower', NaN);
    end

    function updateSpectrum()
        if isempty(state.snapshot) || ~state.snapshot.hasEstimate, return; end
        displayCount = numel(state.snapshot.displayFrequencyHz);
        factor = numel(state.snapshot.averagePsd) / displayCount;
        displayPsd = mean(reshape(state.snapshot.averagePsd, ...
            factor, displayCount), 1).';
        psdLine.XData = state.snapshot.displayFrequencyHz / 1e6;
        psdLine.YData = 10 * log10(displayPsd + 1e-20);
        xlim(ax, [state.snapshot.frequencyHz(1), ...
            state.snapshot.frequencyHz(end)] / 1e6);
        updateMarkers();
    end

    function updateMarkers()
        if isempty(state.selections) || isempty(state.snapshot) || ...
                ~state.snapshot.hasEstimate
            markerLine.XData = NaN; markerLine.YData = NaN; return;
        end
        frequencies = [state.selections.refinedFrequencyHz];
        powers = zeros(size(frequencies));
        for k = 1:numel(frequencies)
            [~, index] = min(abs(state.snapshot.frequencyHz - frequencies(k)));
            powers(k) = 10 * log10(state.snapshot.averagePsd(index) + 1e-20);
        end
        markerLine.XData = frequencies / 1e6;
        markerLine.YData = powers;
    end

    function updateSelectionUi()
        carrierLabel.Text = sprintf('%d', numel(state.selections));
        values = arrayfun(@(s) sprintf('%+.3f kHz', s.offsetHz / 1e3), ...
            state.selections, 'UniformOutput', false);
        selectionArea.Value = values;
        runButton.Enable = valueOnOff(~isDecoderActive());
        updateMarkers();
    end

    function clearSelectionUi()
        carrierLabel.Text = '0';
        selectionArea.Value = {'Click one or more PSD peaks.'};
        markerLine.XData = NaN; markerLine.YData = NaN;
        runButton.Enable = 'off';
        winnerLabel.Text = '-'; pduLabel.Text = '0';
        hintLabel.Text = ...
            'Protocol workers are asynchronous; semantic dedup is off.';
    end

    function ensureCapture()
        if isempty(state.metadata)
            error('radio_live_frontend:NoCapture', 'Load a capture first.');
        end
    end

    function public = getStatePublic()
        upgradeState();
        scannerSummary = [];
        if ~isempty(state.scanner)
            protocols = cell(state.scanner.channelCount, 1);
            states = cell(state.scanner.channelCount, 1);
            for k = 1:state.scanner.channelCount
                protocols{k} = state.scanner.channels{k}.lastSelectedProtocol;
                states{k} = state.scanner.channels{k}.coordinator.state;
            end
            decoderCounts = max(1, ...
                double(state.scanner.decoderCompletionCount));
            scannerSummary = struct( ...
                'channelCount', state.scanner.channelCount, ...
                'selectedProtocols', {protocols}, ...
                'states', {states}, ...
                'feedCount', state.scanner.feedCount, ...
                'inputSampleCount', state.scanner.inputSampleCount, ...
                'meanFeedElapsedSec', state.scanner.totalFeedElapsedSec / ...
                    max(1, double(state.scanner.feedCount)), ...
                'maxFeedElapsedSec', state.scanner.maxFeedElapsedSec, ...
                'maxFeedBreakdown', state.scanner.maxFeedBreakdown, ...
                'meanDdcElapsedSec', state.scanner.totalDdcElapsedSec / ...
                    max(1, double(state.scanner.feedCount)), ...
                'maxDdcElapsedSec', state.scanner.maxDdcElapsedSec, ...
                'decoderCompletionCount', ...
                    state.scanner.decoderCompletionCount, ...
                'meanDecoderComputeSec', ...
                    state.scanner.totalDecoderComputeSec ./ decoderCounts, ...
                'maxDecoderComputeSec', ...
                    state.scanner.maxDecoderComputeSec, ...
                'meanDecoderDispatchSec', ...
                    state.scanner.totalDecoderDispatchSec ./ decoderCounts, ...
                'maxDecoderDispatchSec', ...
                    state.scanner.maxDecoderDispatchSec, ...
                'finalized', state.scanner.finalized);
        end
        sourceNextSample = uint64(0);
        sourceTerminal = false;
        if ~isempty(state.source)
            sourceNextSample = state.source.globalNextSample;
            sourceTerminal = state.source.terminal;
        end
        decoderQueueSec = 0;
        queueSamples = uint64(0);
        if ~isempty(state.metadata)
            queueSamples = state.decoderQueueSamples;
            if state.asyncEnabled
                queueSamples = asyncDecoderQueueSamples();
            end
            decoderQueueSec = double(queueSamples) / ...
                state.metadata.sampleRateHz;
        end
        producerQueueSec = 0;
        spectrumDroppedChunks = uint64(0);
        ddcPendingSamples = uint64(0);
        ddcMeanComputeSec = 0;
        ddcMaxComputeSec = 0;
        ddcReady = false;
        ddcProcessedSamples = uint64(0);
        ddcRingAttached = false;
        ddcRingDrained = false;
        if state.asyncEnabled && ~isempty(state.producerActor)
            producerQueueSec = double(asyncProducerRelaySamples()) / ...
                state.metadata.sampleRateHz;
        end
        if state.asyncEnabled && ~isempty(state.producerActor) && ...
                state.producerActor.directFanout
            spectrumDroppedChunks = ...
                state.producerActor.spectrumDroppedChunks;
        elseif state.asyncEnabled && ~isempty(state.spectrumActor)
            spectrumDroppedChunks = state.spectrumActor.droppedChunkCount;
        end
        if state.asyncEnabled && ~isempty(state.ddcActor)
            ddcPendingSamples = asyncDecoderQueueSamples();
            ddcReady = state.ddcActor.ready;
            ddcProcessedSamples = state.ddcActor.processedInputSamples;
            if state.ddcActor.computeCount > 0
                ddcMeanComputeSec = state.ddcActor.totalComputeSec / ...
                    double(state.ddcActor.computeCount);
            end
            ddcMaxComputeSec = state.ddcActor.maxComputeSec;
            ddcRingAttached = state.ddcActor.ringAttached;
            ddcRingDrained = state.ddcActor.ringDrained;
        end
        public = struct('mode', state.mode, 'metadata', state.metadata, ...
            'selections', state.selections, 'scanner', scannerSummary, ...
            'pdus', state.pdus, 'spectrum', state.snapshot, ...
            'decoderPending', ~isempty(state.scannerBuildFuture), ...
            'decoderQueueSamples', queueSamples, ...
            'decoderQueueSec', decoderQueueSec, ...
            'asyncFrontend', state.asyncEnabled, ...
            'producerQueueSec', producerQueueSec, ...
            'spectrumDroppedChunks', spectrumDroppedChunks, ...
            'ddcPendingSamples', ddcPendingSamples, ...
            'ddcMeanComputeSec', ddcMeanComputeSec, ...
            'ddcMaxComputeSec', ddcMaxComputeSec, ...
            'ddcReady', ddcReady, ...
            'ddcProcessedSamples', ddcProcessedSamples, ...
            'sharedIqRing', ~isempty(state.sharedIqRing), ...
            'ddcRingAttached', ddcRingAttached, ...
            'ddcRingDrained', ddcRingDrained, ...
            'maxProducerLagSec', state.maxProducerLagSec, ...
            'maxProducerQueueSec', state.maxProducerQueueSec, ...
            'maxDdcInputQueueSec', state.maxDdcInputQueueSec, ...
            'maxDdcResultQueueSec', state.maxDdcResultQueueSec, ...
            'maxDecoderPipelineQueueSec', ...
                state.maxDecoderPipelineQueueSec, ...
            'meanAsyncCoordinatorSec', ...
                state.asyncCoordinatorTotalSec / max(1, ...
                    double(state.asyncCoordinatorCount)), ...
            'maxAsyncCoordinatorSec', state.asyncCoordinatorMaxSec, ...
            'decoderRequestedSample', state.scannerRequestedSample, ...
            'decoderReadySample', state.scannerReadySample, ...
            'sourceNextSample', sourceNextSample, ...
            'sourceTerminal', sourceTerminal, ...
            'inputLagSec', state.inputLagSec, ...
            'maxInputLagSec', state.maxInputLagSec, ...
            'timerRunning', isTimerRunning(), 'log', {state.log});
    end

    function closePublic(), onClose([], []); end

    function onClose(~, ~)
        try, upgradeState(); catch, end
        try, state.closing = true; catch, end
        try, stopTimer(); catch, end
        try, discardDecoder('frontend_closed'); catch, end
        try, closeSource(); catch, end
        try, if isvalid(state.timer), delete(state.timer); end; catch, end
        try, if isvalid(fig), delete(fig); end; catch, end
    end

    function onFigureDeleted(~, ~)
        % DeleteFcn is the last-resort cleanup path when a caller uses
        % delete(fig) to bypass a failed/stale CloseRequestFcn.
        try, upgradeState(); catch, end
        try, state.closing = true; catch, end
        try, stopTimer(); catch, end
        try, discardDecoder('figure_deleted'); catch, end
        try, closeSource(); catch, end
        try, if isvalid(state.timer), delete(state.timer); end; catch, end
    end

    function closeSource()
        if isfield(state, 'asyncEnabled') && state.asyncEnabled
            if isfield(state, 'producerActor') && ...
                    ~isempty(state.producerActor)
                state.producerActor = ...
                    radio.live.fileProducerStop(state.producerActor);
            end
            if isfield(state, 'spectrumActor') && ...
                    ~isempty(state.spectrumActor)
                state.spectrumActor = ...
                    radio.live.spectrumActorStop(state.spectrumActor);
            end
            if ~isempty(state.source) && isstruct(state.source)
                state.source.closed = true;
            end
            if isfield(state, 'sharedIqRing') && ...
                    ~isempty(state.sharedIqRing)
                radio.live.sharedIqRingDelete(state.sharedIqRing);
                state.sharedIqRing = [];
            end
            return;
        end
        if ~isempty(state.source) && isstruct(state.source) && ...
                isfield(state.source, 'closed') && ~state.source.closed
            state.source = radio.replay.fileLoopSourceClose(state.source);
        end
    end

    function discardDecoder(reason)
        upgradeState();
        preserveDdc = state.asyncEnabled && ...
            strcmp(char(reason), 'carrier_selection_cleared');
        if state.asyncEnabled && ~isempty(state.producerActor) && ...
                ~state.producerActor.sharedRingEnabled
            state.producerActor = radio.live.fileProducerDetachDecoder( ...
                state.producerActor);
        end
        if state.asyncEnabled && ~isempty(state.ddcActor)
            if preserveDdc
                state.ddcActor = radio.live.ddcActorReset(state.ddcActor);
                token = tic;
                while state.ddcActor.resetPending && ...
                        ~state.ddcActor.failed && toc(token) < 2
                    [state.ddcActor, ~] = radio.live.ddcActorPoll( ...
                        state.ddcActor, 'MaxEvents', inf);
                    if state.ddcActor.resetPending, pause(0.001); end
                end
                if state.ddcActor.resetPending || state.ddcActor.failed
                    state.ddcActor = ...
                        radio.live.ddcActorStop(state.ddcActor);
                    state.ddcActor = [];
                end
            else
                state.ddcActor = radio.live.ddcActorStop(state.ddcActor);
                state.ddcActor = [];
            end
        end
        state.ddcResultQueue = cell(0, 1);
        state.ddcResultQueueHead = 1;
        state.ddcResultQueueSamples = uint64(0);
        state.ddcFlushComplete = false;
        if ~isempty(state.scannerBuildFuture)
            try, cancel(state.scannerBuildFuture); catch, end
        end
        state.scannerBuildFuture = [];
        state.scannerBuildToken = [];
        scannerActive = ~isempty(state.scanner) && ...
            (~isfield(state.scanner, 'finalized') || ...
            ~state.scanner.finalized);
        if scannerActive
            try
                [state.scanner, ~] = ...
                    radio.tuned.multiStreamScannerCancel( ...
                        state.scanner, 'Reason', reason);
            catch ME
                try
                    appendLog(sprintf('Decoder cancellation warning: %s', ...
                        ME.message));
                catch
                end
            end
        end
        state.scanner = [];
        state.scannerRequestedSample = uint64(0);
        state.scannerReadySample = [];
        state.decoderQueue = cell(0, 1);
        state.decoderQueueHead = 1;
        state.decoderQueueSamples = uint64(0);
    end

    function tf = isDecoderActive()
        upgradeState();
        scannerActive = ~isempty(state.scanner) && ...
            (~isfield(state.scanner, 'finalized') || ...
            ~state.scanner.finalized);
        tf = ~isempty(state.scannerBuildFuture) || scannerActive;
    end

    function upgradeState()
        % Keep callbacks from a figure created before a hot code update
        % closable.  MATLAB can deliver queued timer/async events after the
        % file has changed on disk, so every newly introduced field needs a
        % safe legacy default.
        if ~isfield(state, 'scannerBuildFuture')
            state.scannerBuildFuture = [];
        end
        if ~isfield(state, 'scannerBuildToken')
            state.scannerBuildToken = [];
        end
        if ~isfield(state, 'scannerRequestedSample')
            state.scannerRequestedSample = uint64(0);
        end
        if ~isfield(state, 'scannerReadySample')
            state.scannerReadySample = [];
        end
        if ~isfield(state, 'decoderQueue')
            state.decoderQueue = cell(0, 1);
        end
        if ~isfield(state, 'decoderQueueHead')
            state.decoderQueueHead = 1;
        end
        if ~isfield(state, 'decoderQueueSamples')
            state.decoderQueueSamples = uint64(0);
        end
        if ~isfield(state, 'runtimePrepared')
            state.runtimePrepared = false;
        end
        if ~isfield(state, 'runtimeWorkersWarmed')
            state.runtimeWorkersWarmed = false;
        end
        if ~isfield(state, 'runtimePoolInfo')
            state.runtimePoolInfo = [];
        end
        if ~isfield(state, 'runtimeWarmReport')
            state.runtimeWarmReport = [];
        end
        if ~isfield(state, 'runtimeClientWarmReport')
            state.runtimeClientWarmReport = [];
        end
        if ~isfield(state, 'preparedDdcStates')
            state.preparedDdcStates = cell(0, 1);
        end
        if ~isfield(state, 'preparedFusedDdcState')
            state.preparedFusedDdcState = [];
        end
        if ~isfield(state, 'asyncEnabled')
            state.asyncEnabled = false;
        end
        if ~isfield(state, 'producerActor')
            state.producerActor = [];
        end
        if ~isfield(state, 'spectrumActor')
            state.spectrumActor = [];
        end
        if ~isfield(state, 'ddcActor')
            state.ddcActor = [];
        end
        if ~isfield(state, 'sharedIqRing')
            state.sharedIqRing = [];
        end
        if ~isfield(state, 'producerRunning')
            state.producerRunning = false;
        end
        if ~isfield(state, 'producerTerminal')
            state.producerTerminal = false;
        end
        if ~isfield(state, 'ddcResultQueue')
            state.ddcResultQueue = cell(0, 1);
        end
        if ~isfield(state, 'ddcResultQueueHead')
            state.ddcResultQueueHead = 1;
        end
        if ~isfield(state, 'ddcResultQueueSamples')
            state.ddcResultQueueSamples = uint64(0);
        end
        if ~isfield(state, 'ddcFlushComplete')
            state.ddcFlushComplete = false;
        end
        if ~isfield(state, 'maxProducerLagSec')
            state.maxProducerLagSec = 0;
        end
        if ~isfield(state, 'maxProducerQueueSec')
            state.maxProducerQueueSec = 0;
        end
        if ~isfield(state, 'maxDdcInputQueueSec')
            state.maxDdcInputQueueSec = 0;
        end
        if ~isfield(state, 'maxDdcResultQueueSec')
            state.maxDdcResultQueueSec = 0;
        end
        if ~isfield(state, 'maxDecoderPipelineQueueSec')
            state.maxDecoderPipelineQueueSec = 0;
        end
        if ~isfield(state, 'asyncCoordinatorCount')
            state.asyncCoordinatorCount = uint64(0);
        end
        if ~isfield(state, 'asyncCoordinatorTotalSec')
            state.asyncCoordinatorTotalSec = 0;
        end
        if ~isfield(state, 'asyncCoordinatorMaxSec')
            state.asyncCoordinatorMaxSec = 0;
        end
        if ~isfield(state, 'clockBaseSample')
            state.clockBaseSample = uint64(0);
        end
        if ~isfield(state, 'lastDecoderSummaryKey')
            state.lastDecoderSummaryKey = '';
        end
        if ~isfield(state, 'closing')
            state.closing = false;
        end
    end

    function tf = decoderQueueIsEmpty()
        tf = state.decoderQueueHead > numel(state.decoderQueue);
    end

    function count = decoderQueueCount()
        count = max(0, numel(state.decoderQueue) - ...
            state.decoderQueueHead + 1);
    end

    function compactDecoderQueue()
        if decoderQueueIsEmpty()
            state.decoderQueue = cell(0, 1);
            state.decoderQueueHead = 1;
            return;
        end
        if state.decoderQueueHead <= 64 && ...
                state.decoderQueueHead <= numel(state.decoderQueue) / 2
            return;
        end
        state.decoderQueue = state.decoderQueue( ...
            state.decoderQueueHead:end);
        state.decoderQueueHead = 1;
    end

    function tf = hasLiveSource()
        tf = ~isempty(state.source) && isstruct(state.source) && ...
            ~state.source.closed && ~state.source.terminal;
    end

    function seconds = sourceLogicalSec()
        seconds = 0;
        if ~isempty(state.source)
            seconds = double(state.source.globalNextSample) / ...
                state.metadata.sampleRateHz;
        end
    end

    function resumeReplayClock()
        state.clockBaseSample = state.source.globalNextSample;
        state.clockToken = tic;
        state.inputLagSec = 0;
        state.lastUiUpdateSec = 0;
        if state.asyncEnabled && ~isempty(state.producerActor)
            state.producerActor = radio.live.fileProducerCommand( ...
                state.producerActor, 'run');
            state.producerRunning = true;
        end
    end

    function stopTimer()
        if isTimerRunning(), stop(state.timer); end
        if isfield(state, 'asyncEnabled') && state.asyncEnabled && ...
                isfield(state, 'producerActor') && ...
                ~isempty(state.producerActor) && state.producerRunning && ...
                ~state.producerActor.terminal && ...
                ~state.producerActor.failed
            try
                state.producerActor = radio.live.fileProducerCommand( ...
                    state.producerActor, 'pause');
            catch
            end
            state.producerRunning = false;
        end
    end

    function tf = isTimerRunning()
        tf = false;
        try, tf = isvalid(state.timer) && strcmp(state.timer.Running, 'on'); catch, end
    end

    function setMode(mode)
        mode = char(mode);
        if strcmp(state.mode, mode), return; end
        state.mode = mode;
        stateLabel.Text = state.mode;
    end

    function appendLog(message, refresh)
        if nargin < 2, refresh = true; end
        message = char(message);
        state.log{end+1, 1} = message;
        if numel(state.log) > 200, state.log = state.log(end-199:end); end
        if refresh, refreshLog(); end
        if options.PrintToCommandWindow
            fprintf('[radio.live] %s\n', message);
        end
    end

    function refreshLog()
        console.Value = state.log;
    end

    function fail(ME)
        setMode('ERROR'); appendLog(sprintf('%s: %s', ME.identifier, ME.message));
    end
end

function selections = upsertSelection(selections, selection)
if isempty(selections), selections = selection; return; end
distance = abs([selections.offsetHz] - selection.offsetHz);
[nearest, index] = min(distance);
if nearest <= max(500, selection.bandwidthHz / 10)
    selections(index) = selection;
else
    selections(end+1) = selection;
    [~, order] = sort([selections.offsetHz]);
    selections = selections(order);
end
end

function selections = emptySelections()
template = struct('clickedFrequencyHz', 0, 'refinedFrequencyHz', 0, ...
    'offsetHz', 0, 'bandwidthHz', 0, 'searchRadiusHz', 0, ...
    'peakBinFrequencyHz', 0, 'peakPower', NaN, 'noisePower', NaN);
selections = template([]);
end

function validateOptions(options)
validateattributes(options.MaxLoops, {'numeric'}, {'scalar','real','positive'});
validateattributes(options.InputChunkDurationSec, {'numeric'}, ...
    {'scalar','real','finite','positive'});
validateattributes(options.PlayoutDelaySec, {'numeric'}, ...
    {'scalar','real','finite','nonnegative'});
validateattributes(options.MaxChunksPerTick, {'numeric'}, ...
    {'scalar','real','finite','integer','positive'});
validateattributes(options.MaxCarrierPaths, {'numeric'}, ...
    {'scalar','real','finite','integer','positive'});
validateattributes(options.DecoderQueueLimitSec, {'numeric'}, ...
    {'scalar','real','finite','positive'});
validateattributes(options.DecoderCatchupChunksPerTick, {'numeric'}, ...
    {'scalar','real','finite','integer','positive'});
validateattributes(options.DecoderCatchupBudgetSec, {'numeric'}, ...
    {'scalar','real','finite','positive'});
validateattributes(options.DecoderCatchupMaxBudgetSec, {'numeric'}, ...
    {'scalar','real','finite','positive'});
if options.DecoderCatchupMaxBudgetSec < options.DecoderCatchupBudgetSec
    error('radio_live_frontend:DecoderCatchupBudget', ...
        'DecoderCatchupMaxBudgetSec must not be below the base budget.');
end
validateattributes(options.FrontendWorkerReserve, {'numeric'}, ...
    {'scalar','real','finite','integer','positive'});
validateattributes(options.ProducerQueueLimitSec, {'numeric'}, ...
    {'scalar','real','finite','positive'});
validateattributes(options.SpectrumQueueLimitChunks, {'numeric'}, ...
    {'scalar','real','finite','integer','positive'});
end

function value = scalarOr(value, fallback)
if isempty(value), value = fallback; end
value = double(value);
end

function path = defaultCapture()
candidates = { ...
    '/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/synthesized_wideband_2.5MHz.rawiq', ...
    '/home/lzkj/lzkj_workspace/DMR_signal/1.bvsp'};
path = '';
for k = 1:numel(candidates)
    if exist(candidates{k}, 'file') == 2, path = candidates{k}; return; end
end
end

function value = valueOr(value, fallback)
if isempty(value), value = fallback; end
end

function value = valueOnOff(tf)
if tf, value = 'on'; else, value = 'off'; end
end

function label = placeLabel(parent, text, row, column)
label = uilabel(parent, 'Text', text);
label.Layout.Row = row; label.Layout.Column = column;
end
