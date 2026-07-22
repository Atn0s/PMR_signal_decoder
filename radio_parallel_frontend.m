function app = radio_parallel_frontend(varargin)
%RADIO_PARALLEL_FRONTEND Lean shared-ring parallel replay frontend.
options = radio.live.parallelFrontendConfig(varargin{:});
runtime = options.RuntimeConfig;

callbacks = struct( ...
    'browse', @onBrowse, ...
    'preview', @(~,~) runUiAction(@startPreview), ...
    'clear', @(~,~) runUiAction(@clearCarriers), ...
    'run', @(~,~) runUiAction(@startDecode), ...
    'stop', @(~,~) runUiAction(@stopReplay), ...
    'spectrum', @onSpectrumClick);
view = radio.live.parallelFrontendCreateView( ...
    options.Visible, scalarOr(options.SampleRate, 0), ...
    scalarOr(options.CenterFrequencyHz, 0), callbacks);
fig = view.figure;
pathField = view.path;
fsField = view.sampleRate;
centerField = view.centerHz;
bwDrop = view.bandwidth;
metadataLabel = view.metadata;
runButton = view.runButton;
stateLabel = view.state;
carrierLabel = view.carrierCount;
winnerLabel = view.winners;
pduLabel = view.pduCount;
ddcLabel = view.ddcRate;
selectionArea = view.selections;
hintLabel = view.hint;
console = view.console;
markerLine = view.markerLine;
hintLabel.Text = decoderHint();

state = struct( ...
    'mode', 'IDLE', ...
    'metadata', [], ...
    'session', [], ...
    'selections', emptySelections(), ...
    'log', {cell(0, 1)}, ...
    'timer', [], ...
    'busy', false, ...
    'closed', false, ...
    'lastUiToken', tic);
timerObject = timer('ExecutionMode', 'fixedRate', 'BusyMode', 'drop', ...
    'Period', runtime.inputChunkDurationSec, ...
    'TimerFcn', @onTimer, 'ErrorFcn', @onTimerError, ...
    'Name', 'PMRParallelLiveReplay');
state.timer = timerObject;
fig.CloseRequestFcn = @closeApp;
fig.DeleteFcn = @closeApp;

app = struct( ...
    'Figure', fig, ...
    'LoadFile', @loadCapture, ...
    'StartPreview', @startPreview, ...
    'SelectOffsetHz', @selectOffset, ...
    'ClearCarriers', @clearCarriers, ...
    'StartDecode', @startDecode, ...
    'Step', @step, ...
    'Stop', @stopReplay, ...
    'GetState', @getState, ...
    'Close', @closeApp);

if ~isempty(options.DefaultFile) && exist(options.DefaultFile, 'file') == 2
    try
        loadCapture(options.DefaultFile);
    catch ME
        appendLog(sprintf('Load failed: %s', ME.message));
    end
end
if options.AutoStartPreview && ~isempty(state.metadata)
    startPreview();
end

    function onBrowse(~, ~)
        [name, folder] = uigetfile( ...
            {'*.bvsp;*.rawiq;*.bin;*.wav','IQ captures';'*.*','All files'});
        if isequal(name, 0), return; end
        try
            loadCapture(fullfile(folder, name));
        catch ME
            fail(ME);
        end
    end

    function onSpectrumClick(source, ~)
        if isempty(state.session) || isempty(state.session.spectrum) || ...
                ~state.session.spectrum.hasEstimate
            return;
        end
        try
            selectFrequency(source.CurrentPoint(1, 1) * 1e6, ...
                true, bwDrop.Value);
        catch ME
            fail(ME);
        end
    end

    function onTimer(~, ~)
        if state.busy || state.closed, return; end
        state.busy = true;
        cleanup = onCleanup(@() releaseBusy());
        try
            processSession();
        catch ME
            fail(ME);
        end
        clear cleanup;
    end

    function releaseBusy()
        state.busy = false;
    end

    function onTimerError(~, event)
        message = 'Timer callback failed.';
        try
            message = event.Data.Message;
        catch
        end
        fail(MException('radio_parallel_frontend:Timer', '%s', message));
    end

    function runUiAction(action)
        try
            action();
        catch ME
            fail(ME);
        end
    end

    function loadCapture(path)
        stopTimer();
        closeSession();
        path = char(path);
        pathField.Value = path;
        sampleRate = fsField.Value;
        if sampleRate <= 0, sampleRate = []; end
        centerHz = centerField.Value;
        if centerHz == 0, centerHz = []; end
        metadata = radio.tuned.captureInfo(path, ...
            'SampleRate', sampleRate, ...
            'CenterFrequencyHz', centerHz, ...
            'IqDType', options.IqDType);
        state.metadata = metadata;
        state.selections = emptySelections();
        fsField.Value = metadata.sampleRateHz;
        centerField.Value = metadata.centerFrequencyHz;
        metadataLabel.Text = sprintf('%.3f MHz | %.1f s', ...
            metadata.sampleRateHz / 1e6, metadata.durationSec);
        [resolved, report] = radio.tuned.resolveInputConfig( ...
            metadata.sampleRateHz, options.TunedConfig);
        ddcLabel.Text = sprintf('%.0f kS/s (/%d)', ...
            resolved.outputSampleRateHz / 1e3, report.decimationFactor);
        clearSelectionView();
        setMode('IDLE');
        appendLog(sprintf('Loaded %s, Fs %.3f MHz, duration %.3f s.', ...
            metadata.format, metadata.sampleRateHz / 1e6, ...
            metadata.durationSec));
    end

    function startPreview(varargin)
        q = inputParser;
        q.addParameter('StartTimer', true);
        q.parse(varargin{:});
        ensureCapture();
        stopTimer();
        closeSession();
        state.selections = emptySelections();
        clearSelectionView();
        setMode('PREPARING');
        drawnow;
        [state.session, messages] = radio.live.parallelSessionStart( ...
            state.metadata, options.SessionConfig);
        setMode(state.session.mode);
        appendMessages(messages);
        appendLog('1x preview started; click PSD peaks to add carriers.');
        state.lastUiToken = tic;
        if q.Results.StartTimer
            state.session = radio.live.parallelSessionCommand( ...
                state.session, 'run');
            start(state.timer);
        end
    end

    function selection = selectOffset(offsetHz, varargin)
        q = inputParser;
        q.addParameter('Refine', true);
        q.addParameter('BandwidthHz', bwDrop.Value);
        q.parse(varargin{:});
        ensureCapture();
        selection = selectFrequency( ...
            state.metadata.centerFrequencyHz + double(offsetHz), ...
            q.Results.Refine, q.Results.BandwidthHz);
    end

    function selection = selectFrequency(frequencyHz, refine, bandwidthHz)
        ensurePreview();
        if decoderActive()
            error('radio_parallel_frontend:DecoderActive', ...
                'Clear the active decoder before changing carriers.');
        end
        if refine
            if isempty(state.session.spectrum) || ...
                    ~state.session.spectrum.hasEstimate
                error('radio_parallel_frontend:SpectrumUnavailable', ...
                    'Wait for a spectrum estimate before refining a carrier.');
            end
            selection = radio.scope.refineCarrier( ...
                state.session.spectrum, frequencyHz, ...
                'BandwidthHz', bandwidthHz);
        else
            selection = makeSelection(frequencyHz, bandwidthHz);
        end
        selections = upsertSelection(state.selections, selection);
        if numel(selections) > options.MaxCarrierPaths
            error('radio_parallel_frontend:CarrierCount', ...
                'At most %d carrier paths are supported.', ...
                options.MaxCarrierPaths);
        end
        state.selections = selections;
        renderSelections();
        appendLog(sprintf('Carrier %+.3f kHz selected.', ...
            selection.offsetHz / 1e3));
    end

    function clearCarriers()
        if state.busy
            error('radio_parallel_frontend:Busy', ...
                'The frontend is already processing another update.');
        end
        state.busy = true;
        cleanup = onCleanup(@() releaseBusy());
        ensurePreview();
        if decoderActive()
            [state.session, message] = ...
                radio.live.parallelSessionClear(state.session);
            appendLog(message);
        end
        state.selections = emptySelections();
        clearSelectionView();
        setMode(state.session.mode);
        clear cleanup;
    end

    function startDecode(varargin)
        q = inputParser;
        q.addParameter('StartTimer', true);
        q.parse(varargin{:});
        ensurePreview();
        if isempty(state.selections)
            error('radio_parallel_frontend:NoCarrier', ...
                'Select at least one carrier first.');
        end
        [state.session, message] = radio.live.parallelSessionAttach( ...
            state.session, [state.selections.offsetHz].');
        setMode(state.session.mode);
        runButton.Enable = 'off';
        winnerLabel.Text = '-';
        pduLabel.Text = '0';
        appendLog(message);
        if q.Results.StartTimer && ~isTimerRunning()
            state.session = radio.live.parallelSessionCommand( ...
                state.session, 'run');
            start(state.timer);
        end
    end

    function out = step(count)
        if nargin < 1, count = 1; end
        ensurePreview();
        validateattributes(count, {'numeric'}, ...
            {'scalar','real','finite','integer','positive'});
        stopTimer();
        before = radio.live.parallelSessionSnapshot(state.session);
        target = before.sourceNextSample + uint64(round( ...
            count * runtime.inputChunkDurationSec * ...
            state.metadata.sampleRateHz));
        state.session = radio.live.parallelSessionCommand( ...
            state.session, 'step', count);
        token = tic;
        while ~state.session.closed && ...
                state.session.source.globalNextSample < target && ...
                ~state.session.source.terminal && toc(token) < 30
            processSession();
            pause(0.001);
        end
        while ~state.session.closed && toc(token) < 30
            current = radio.live.parallelSessionSnapshot(state.session);
            if ~state.session.source.terminal && ...
                    current.decoderPipelineQueueSamples == 0
                break;
            end
            processSession();
            pause(0.001);
        end
        if ~state.session.closed, processSession(); end
        if toc(token) >= 30 && ~state.session.closed
            error('radio_parallel_frontend:StepTimeout', ...
                'Parallel stepping or finalization did not complete.');
        end
        out = getState();
    end

    function processSession()
        if isempty(state.session) || state.session.closed, return; end
        [state.session, update] = ...
            radio.live.parallelSessionPoll(state.session);
        if ~isempty(update.spectrum)
            radio.live.parallelFrontendRenderSpectrum( ...
                view, update.spectrum, state.selections);
        end
        appendMessages(update.messages);
        if ~isempty(update.newPdus), printPdus(update.newPdus); end
        setMode(state.session.mode);
        if update.completed, stopTimer(); end
        if toc(state.lastUiToken) >= 0.1 || update.completed
            snapshot = radio.live.parallelSessionSnapshot(state.session);
            wallSec = 0;
            if ~isempty(state.session.startedToken)
                wallSec = toc(state.session.startedToken);
            end
            radio.live.parallelFrontendRenderRuntime( ...
                view, snapshot, state.metadata.sampleRateHz, ...
                wallSec, decoderHint());
            state.lastUiToken = tic;
        end
    end

    function stopReplay()
        stopTimer();
        closeSession();
        setMode('STOPPED');
        appendLog('Replay stopped.');
    end

    function out = getState()
        sessionState = radio.live.parallelSessionSnapshot(state.session);
        out = sessionState;
        out.mode = state.mode;
        out.metadata = state.metadata;
        out.selections = state.selections;
        out.timerRunning = isTimerRunning();
        out.log = state.log;
    end

    function closeApp(varargin)
        if state.closed, return; end
        state.closed = true;
        try
            if isTimerRunning(), stop(state.timer); end
        catch
        end
        closeSession();
        try
            if isvalid(state.timer), delete(state.timer); end
        catch
        end
        try
            if isvalid(fig), delete(fig); end
        catch
        end
    end

    function closeSession()
        if isempty(state.session), return; end
        state.session = radio.live.parallelSessionClose(state.session);
        state.session = [];
    end

    function stopTimer()
        if isTimerRunning(), stop(state.timer); end
        if ~isempty(state.session) && ~state.session.closed && ...
                state.session.producerRunning
            state.session = radio.live.parallelSessionCommand( ...
                state.session, 'pause');
        end
    end

    function tf = isTimerRunning()
        tf = false;
        try
            tf = isvalid(state.timer) && strcmp(state.timer.Running, 'on');
        catch
        end
    end

    function tf = decoderActive()
        tf = ~isempty(state.session) && ...
            ~isempty(state.session.decode.scanner) && ...
            ~state.session.decode.scanner.finalized;
    end

    function ensureCapture()
        if isempty(state.metadata)
            error('radio_parallel_frontend:NoCapture', ...
                'Load a capture first.');
        end
    end

    function ensurePreview()
        ensureCapture();
        if isempty(state.session) || state.session.closed || ...
                state.session.source.terminal
            error('radio_parallel_frontend:NoPreview', ...
                'Start a live preview first.');
        end
    end

    function renderSelections()
        carrierLabel.Text = sprintf('%d', numel(state.selections));
        selectionArea.Value = arrayfun( ...
            @(s) sprintf('%+.3f kHz', s.offsetHz / 1e3), ...
            state.selections, 'UniformOutput', false);
        runButton.Enable = onOff(~decoderActive());
        if ~isempty(state.session)
            radio.live.parallelFrontendRenderSpectrum( ...
                view, state.session.spectrum, state.selections);
        end
    end

    function clearSelectionView()
        carrierLabel.Text = '0';
        selectionArea.Value = {'Click one or more PSD peaks.'};
        markerLine.XData = NaN;
        markerLine.YData = NaN;
        runButton.Enable = 'off';
        winnerLabel.Text = '-';
        pduLabel.Text = '0';
        hintLabel.Text = decoderHint();
    end

    function printPdus(pdus)
        lines = radio.formatLines(pdus);
        for pduIndex = 1:numel(pdus)
            channel = double(radio.getNestedField( ...
                pdus(pduIndex), 'extra.tuned.channel_id', uint64(0)));
            if pduIndex <= numel(lines)
                body = lines{pduIndex};
            else
                body = pdus(pduIndex).type;
            end
            appendLog(sprintf('PDU ch%d %s', channel, body), false);
        end
        refreshLog();
    end

    function appendMessages(messages)
        for messageIndex = 1:numel(messages)
            appendLog(messages{messageIndex});
        end
    end

    function setMode(mode)
        state.mode = char(mode);
        stateLabel.Text = state.mode;
    end

    function appendLog(message, refresh)
        if nargin < 2, refresh = true; end
        message = char(message);
        state.log{end+1, 1} = message;
        if numel(state.log) > 200
            state.log = state.log(end-199:end);
        end
        if refresh, refreshLog(); end
        if options.PrintToCommandWindow
            fprintf('[radio.parallel] %s\n', message);
        end
    end

    function refreshLog()
        console.Value = state.log;
    end

    function fail(ME)
        try
            stopTimer();
        catch
        end
        try
            closeSession();
        catch
        end
        setMode('ERROR');
        appendLog(sprintf('%s: %s', ME.identifier, ME.message));
    end

    function text = decoderHint()
        if options.Deduplicate
            text = 'Parallel protocol workers; semantic dedup is on.';
        else
            text = 'Parallel protocol workers; semantic dedup is off.';
        end
    end

    function selection = makeSelection(frequencyHz, bandwidthHz)
        selection = struct( ...
            'clickedFrequencyHz', double(frequencyHz), ...
            'refinedFrequencyHz', double(frequencyHz), ...
            'offsetHz', double(frequencyHz - ...
                state.metadata.centerFrequencyHz), ...
            'bandwidthHz', double(bandwidthHz), ...
            'searchRadiusHz', 0, ...
            'peakBinFrequencyHz', double(frequencyHz), ...
            'peakPower', NaN, 'noisePower', NaN);
    end
end

function selections = upsertSelection(selections, selection)
if isempty(selections)
    selections = selection;
    return;
end
[nearest, index] = min(abs( ...
    [selections.offsetHz] - selection.offsetHz));
if nearest <= max(500, selection.bandwidthHz / 10)
    selections(index) = selection;
else
    selections(end+1) = selection;
    [~, order] = sort([selections.offsetHz]);
    selections = selections(order);
end
end

function selections = emptySelections()
template = struct('clickedFrequencyHz', 0, ...
    'refinedFrequencyHz', 0, 'offsetHz', 0, 'bandwidthHz', 0, ...
    'searchRadiusHz', 0, 'peakBinFrequencyHz', 0, ...
    'peakPower', NaN, 'noisePower', NaN);
selections = template([]);
end

function value = scalarOr(value, fallback)
if isempty(value), value = fallback; end
value = double(value);
end

function value = onOff(tf)
if tf, value = 'on'; else, value = 'off'; end
end
