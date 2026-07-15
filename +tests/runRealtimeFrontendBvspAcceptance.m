function result = runRealtimeFrontendBvspAcceptance(varargin)
%RUNREALTIMEFRONTENDBVSPACCEPTANCE Decode the observed 61.44 MS/s DMR file.
p = inputParser;
p.addParameter('Path', ...
    '/home/lzkj/lzkj_workspace/DMR_signal/1.bvsp');
p.addParameter('Mode', 'serial');
p.addParameter('TimeoutSec', 90);
p.parse(varargin{:});
path = char(p.Results.Path);
mode = lower(char(p.Results.Mode));
if exist(path, 'file') ~= 2
    error('tests:runRealtimeFrontendBvspAcceptance:NotFound', ...
        'BVSP acceptance capture is unavailable: %s', path);
end
if ~any(strcmp(mode, {'serial','parallel'}))
    error('tests:runRealtimeFrontendBvspAcceptance:Mode', ...
        'Mode must be serial or parallel.');
end
if strcmp(mode, 'serial')
    protocols = {'dmr'};
    workers = 1;
    warmPool = false;
else
    protocols = {};
    workers = 5;
    warmPool = true;
end

app = radio_frontend( ...
    'Visible', 'off', ...
    'DefaultFile', path, ...
    'ReplayMode', 'once', ...
    'MaxLoops', 1, ...
    'ReplaySpeed', 0.25, ...
    'ProtocolNames', protocols, ...
    'ParallelMode', mode, ...
    'NumWorkers', workers, ...
    'PoolType', 'processes', ...
    'WarmParallelPool', warmPool, ...
    'ContinueAfterLockSec', 0, ...
    'MaxLogicalDurationSec', 2);
cleanup = onCleanup(@() app.Close());

app.StartPreview('StartTimer', false);
app.Step(20);
selection = app.SelectOffsetHz(1235200, 'Refine', true);
if abs(selection.offsetHz - 1235200) > 3000
    error('tests:runRealtimeFrontendBvspAcceptance:Refinement', ...
        'Carrier refinement moved outside the expected DMR channel.');
end

if strcmp(mode, 'serial')
    app.RunIdentification('StartTimer', false);
    state = app.Step(110);
else
    app.RunIdentification();
    token = tic;
    while toc(token) < p.Results.TimeoutSec
        pause(0.5);
        state = app.GetState();
        if ~state.timerRunning, break; end
    end
    if state.timerRunning
        error('tests:runRealtimeFrontendBvspAcceptance:Timeout', ...
            'Parallel frontend did not finish within %.1f seconds.', ...
            p.Results.TimeoutSec);
    end
end

assert(strcmp(state.mode, 'COMPLETED'));
assert(strcmp(state.scanner.selectedProtocol, 'DMR'));
assert(numel(state.closedEpochs) == 1);
assert(numel(state.pdus) == 3);
assert(any(strcmp({state.pdus.type}, 'LATE_ENTRY')));
assert(any(strcmp({state.pdus.type}, 'DMR_CALL')));
result = struct( ...
    'mode', mode, ...
    'selection', selection, ...
    'winner', state.scanner.selectedProtocol, ...
    'pduCount', numel(state.pdus), ...
    'epochCount', numel(state.closedEpochs), ...
    'pduTypes', {unique({state.pdus.type}, 'stable')});
clear cleanup;
fprintf(['Realtime frontend BVSP acceptance passed: mode=%s, ', ...
    'offset=%.3f Hz, winner=%s, PDUs=%d.\n'], ...
    mode, selection.offsetHz, result.winner, result.pduCount);
end
