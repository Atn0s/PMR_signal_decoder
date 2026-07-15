function [handle, status] = lockedDecoderPoll(handle)
%LOCKEDDECODERPOLL Collect a completed locked decoder without blocking.
if handle.completed
    status = makeStatus(handle);
    return;
end
if strcmp(handle.mode, 'persistent_worker')
    pollToken = tic;
    [handle.actor, actorEvent] = ...
        radio.stream.lockedDecoderActorPoll(handle.actor);
    if actorEvent.completed
        if strcmp(actorEvent.state, 'completed')
            handle.decoderState = actorEvent.decoderState;
            handle.decoderState.actor = handle.actor;
            handle.output = actorEvent.output;
        else
            handle.errorReason = actorEvent.errorReason;
            if isempty(handle.errorReason)
                handle.errorReason = 'persistent_decoder_worker_stopped';
            end
            handle.actor = ...
                radio.stream.lockedDecoderActorStop(handle.actor);
        end
        handle.completed = true;
        handle.elapsedSec = toc(handle.timerToken);
    end
    handle.pollElapsedSec = toc(pollToken);
    status = makeStatus(handle);
    return;
end
if ~strcmp(char(handle.future.State), 'finished')
    status = makeStatus(handle);
    return;
end

pollToken = tic;
try
    fetchToken = tic;
    [decoderState, output] = fetchOutputs(handle.future);
    handle.fetchElapsedSec = toc(fetchToken);
    if decoderState.epochId ~= handle.epochId || ...
            decoderState.generation ~= handle.generation || ...
            ~strcmp(decoderState.protocol, handle.protocol)
        handle.errorReason = ...
            'stale_or_mismatched_locked_decoder_result_ignored';
    else
        handle.decoderState = decoderState;
        handle.output = output;
    end
catch ME
    handle.errorReason = sprintf('%s: %s', ME.identifier, ME.message);
end
handle.pollElapsedSec = toc(pollToken);
handle.completed = true;
handle.elapsedSec = toc(handle.timerToken);
status = makeStatus(handle);
end

function status = makeStatus(handle)
if handle.canceled
    state = 'canceled';
elseif ~handle.completed
    state = 'running';
elseif ~isempty(handle.errorReason)
    state = 'error';
else
    state = 'completed';
end
status = struct( ...
    'state', state, ...
    'completed', handle.completed, ...
    'canceled', handle.canceled, ...
    'mode', handle.mode, ...
    'elapsedSec', toc(handle.timerToken), ...
    'submitElapsedSec', handle.submitElapsedSec, ...
    'pollElapsedSec', handle.pollElapsedSec, ...
    'fetchElapsedSec', handle.fetchElapsedSec, ...
    'errorReason', handle.errorReason, ...
    'decoderState', handle.decoderState, ...
    'output', handle.output);
end
