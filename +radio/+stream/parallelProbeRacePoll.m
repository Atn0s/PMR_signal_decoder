function [handle, status] = parallelProbeRacePoll(handle)
%PARALLELPROBERACEPOLL Collect completed futures without blocking acquisition.
if handle.completed
    status = handle.race;
    return;
end
for k = 1:numel(handle.futures)
    if ~handle.submitted(k) || handle.collected(k)
        continue;
    end
    future = handle.futures{k};
    if ~strcmp(char(future.State), 'finished')
        continue;
    end
    try
        [newState, result] = fetchOutputs(future);
        accepted = result.epochId == handle.epochId && ...
            result.generation == handle.generation && ...
            newState.epochId == handle.epochId && ...
            newState.generation == handle.generation && ...
            strcmp(result.protocol, handle.registry(k).name) && ...
            strcmp(newState.protocol, handle.registry(k).name);
        if accepted
            handle.states(k) = newState;
            handle.results(k) = result;
        else
            handle.staleResultCount = handle.staleResultCount + 1;
            handle.results(k) = radio.stream.makeProbeResult( ...
                handle.states(k), 'error', handle.snapshot, ...
                'Reason', 'stale_or_mismatched_worker_result_ignored');
        end
    catch ME
        handle.taskErrorCount = handle.taskErrorCount + 1;
        handle.results(k) = radio.stream.makeProbeResult( ...
            handle.states(k), 'error', handle.snapshot, ...
            'Reason', sprintf('%s: %s', ME.identifier, ME.message));
    end
    handle.collected(k) = true;
end

if shouldFinishEarly(handle)
    handle = finishEarly(handle);
    status = handle.race;
    return;
end

handle = radio.stream.parallelProbeRaceSubmitPending(handle);
if all(handle.collected)
    handle = finalizeHandle(handle);
    status = handle.race;
else
    status = progressStatus(handle, false);
end
end

function status = progressStatus(handle, timedOut)
status = struct( ...
    'epochId', handle.epochId, ...
    'generation', handle.generation, ...
    'outcome', 'running', ...
    'winner', [], ...
    'confirmedProtocols', {{}}, ...
    'results', handle.results, ...
    'executionMode', handle.executionMode, ...
    'elapsedSec', toc(handle.timerToken), ...
    'staleResultCount', handle.staleResultCount, ...
    'taskErrorCount', handle.taskErrorCount, ...
    'canceled', handle.canceled, ...
    'earlyTerminated', handle.earlyTerminated, ...
    'maxInFlight', handle.maxInFlight, ...
    'peakInFlight', handle.peakInFlight, ...
    'timedOut', timedOut, ...
    'submittedCount', nnz(handle.submitted), ...
    'collectedCount', nnz(handle.collected));
end

function tf = shouldFinishEarly(handle)
tf = false;
if ~handle.earlyConfirm
    return;
end
confirmed = find(handle.collected & ...
    strcmp({handle.results.status}.', 'confirmed'));
if numel(confirmed) ~= 1
    return;
end
tf = handle.results(confirmed).confidence + eps >= ...
    handle.earlyConfirmMinConfidence;
end

function handle = finishEarly(handle)
winnerIndex = find(handle.collected & ...
    strcmp({handle.results.status}.', 'confirmed'), 1);
for k = 1:numel(handle.results)
    if k == winnerIndex || handle.collected(k)
        continue;
    end
    if handle.submitted(k)
        try
            cancel(handle.futures{k});
        catch
        end
        handle.canceledTaskCount = handle.canceledTaskCount + 1;
    end
    handle.results(k) = radio.stream.makeProbeResult( ...
        handle.states(k), 'pending', handle.snapshot, ...
        'Reason', 'not_evaluated_after_strong_winner');
    handle.collected(k) = true;
end
handle.earlyTerminated = true;
handle = finalizeHandle(handle);
end

function handle = finalizeHandle(handle)
handle.completed = true;
handle.elapsedSec = toc(handle.timerToken);
handle.race = radio.stream.summarizeProbeResults( ...
    handle.results, handle.epochId, handle.generation);
handle.race.executionMode = handle.executionMode;
handle.race.elapsedSec = handle.elapsedSec;
handle.race.staleResultCount = handle.staleResultCount;
handle.race.taskErrorCount = handle.taskErrorCount;
handle.race.canceled = handle.canceled;
handle.race.fallbackReason = handle.fallbackReason;
handle.race.maxInFlight = handle.maxInFlight;
handle.race.peakInFlight = handle.peakInFlight;
handle.race.earlyTerminated = handle.earlyTerminated;
handle.race.canceledTaskCount = handle.canceledTaskCount;
end
