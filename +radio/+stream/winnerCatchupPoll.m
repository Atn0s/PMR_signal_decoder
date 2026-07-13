function [handle, status] = winnerCatchupPoll(handle)
%WINNERCATCHUPPOLL Collect an asynchronous catch-up result if ready.
if handle.completed
    status = makeStatus(handle);
    return;
end
if ~strcmp(char(handle.future.State), 'finished')
    status = makeStatus(handle);
    return;
end

try
    result = fetchOutputs(handle.future);
    if result.epochId ~= handle.epochId || ...
            result.generation ~= handle.generation || ...
            ~strcmp(result.protocol, handle.protocol)
        handle.errorReason = 'stale_or_mismatched_catchup_result_ignored';
    else
        handle.result = result;
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
    'result', handle.result);
end
