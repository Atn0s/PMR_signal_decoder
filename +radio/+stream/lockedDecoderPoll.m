function [handle, status] = lockedDecoderPoll(handle)
%LOCKEDDECODERPOLL Collect a completed locked decoder without blocking.
if handle.completed
    status = makeStatus(handle);
    return;
end
if ~strcmp(char(handle.future.State), 'finished')
    status = makeStatus(handle);
    return;
end

try
    [decoderState, output] = fetchOutputs(handle.future);
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
    'errorReason', handle.errorReason, ...
    'decoderState', handle.decoderState, ...
    'output', handle.output);
end
