function handle = lockedDecoderStart(state, buffer, varargin)
%LOCKEDDECODERSTART Start one ordered locked-protocol decode pass.
p = inputParser;
p.addParameter('Mode', 'auto');
p.addParameter('NumWorkers', 5);
p.addParameter('PoolType', 'auto');
p.parse(varargin{:});

handle = struct( ...
    'epochId', uint64(state.epochId), ...
    'generation', uint64(state.generation), ...
    'protocol', state.protocol, ...
    'mode', '', ...
    'future', [], ...
    'actor', [], ...
    'completed', false, ...
    'canceled', false, ...
    'decoderState', [], ...
    'output', [], ...
    'errorReason', '', ...
    'fallbackReason', '', ...
    'submitElapsedSec', 0, ...
    'pollElapsedSec', 0, ...
    'fetchElapsedSec', 0, ...
    'timerToken', tic, ...
    'elapsedSec', 0);

mode = lower(char(p.Results.Mode));
input = radio.stream.lockedDecoderPrepareInput(state, buffer);
if strcmp(mode, 'serial')
    handle.mode = 'serial';
    [handle.decoderState, handle.output] = ...
        radio.stream.lockedDecoderProcessChunk(state, input);
    handle.completed = true;
    handle.elapsedSec = toc(handle.timerToken);
    return;
end
if ~any(strcmp(mode, {'auto', 'parallel'}))
    error('radio:stream:lockedDecoderStart:Mode', ...
        'Mode must be auto, parallel, or serial.');
end

% NXDN's native causal path is thread-compatible at the tuned 120 kS/s
% rate.  Prefer backgroundPool so state and IQ stay in one MATLAB process
% and the five process workers remain available for protocol races and the
% four legacy locked decoders.  The persistent process actor below remains
% a fallback for environments where the background task cannot be queued.
if persistentNxdnEligible(state) && ...
        state.sampleRateHz == 120000 && isempty(state.actor)
    try
        handle.mode = 'background_worker';
        submitToken = tic;
        handle.future = parfeval(backgroundPool, ...
            @radio.stream.lockedDecoderProcessChunk, 2, state, input);
        handle.submitElapsedSec = toc(submitToken);
        return;
    catch ME
        handle.fallbackReason = sprintf( ...
            'background_worker_start_failed:%s', ME.identifier);
    end
end

[pool, info] = radio.stream.acquireParallelPool( ...
    'NumWorkers', p.Results.NumWorkers, 'PoolType', p.Results.PoolType);
if isempty(pool)
    handle.mode = 'serial_fallback';
    handle.fallbackReason = info.reason;
    [handle.decoderState, handle.output] = ...
        radio.stream.lockedDecoderProcessChunk(state, input);
    handle.completed = true;
    handle.elapsedSec = toc(handle.timerToken);
    return;
end

handle.mode = 'parallel';
if persistentNxdnEligible(state)
    try
        if isempty(state.actor)
            submitToken = tic;
            handle.actor = radio.stream.lockedDecoderActorStart( ...
                pool, state, input);
            handle.submitElapsedSec = toc(submitToken);
        else
            submitToken = tic;
            handle.actor = state.actor;
            handle.actor = radio.stream.lockedDecoderActorSubmit( ...
                handle.actor, input);
            handle.submitElapsedSec = toc(submitToken);
        end
        handle.mode = 'persistent_worker';
        handle.future = handle.actor.future;
        return;
    catch ME
        if ~isempty(state.actor)
            handle.mode = 'persistent_worker';
            handle.completed = true;
            handle.errorReason = sprintf('%s: %s', ...
                ME.identifier, ME.message);
            handle.elapsedSec = toc(handle.timerToken);
            return;
        end
        handle.fallbackReason = sprintf( ...
            'persistent_worker_start_failed:%s', ME.identifier);
    end
end
submitToken = tic;
handle.future = parfeval(pool, @radio.stream.lockedDecoderProcessChunk, 2, ...
    state, input);
handle.submitElapsedSec = toc(submitToken);
end

function tf = persistentNxdnEligible(state)
tf = strcmp(state.protocol, 'NXDN') && isempty(state.decodeFcn) && ...
    isfield(state, 'incremental') && ...
    isfield(state.incremental, 'nativeStreaming') && ...
    state.incremental.nativeStreaming && isfield(state, 'actor');
end
