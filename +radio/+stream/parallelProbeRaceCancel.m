function [handle, status] = parallelProbeRaceCancel(handle, varargin)
%PARALLELPROBERACECANCEL Best-effort cancel and close one race generation.
p = inputParser;
p.addParameter('Reason', 'race_canceled');
p.parse(varargin{:});
if handle.completed
    status = handle.race;
    return;
end

for k = 1:numel(handle.futures)
    if ~handle.collected(k)
        if handle.submitted(k)
            future = handle.futures{k};
            try
                cancel(future);
            catch
            end
            handle.canceledTaskCount = handle.canceledTaskCount + 1;
        end
        handle.results(k) = radio.stream.makeProbeResult( ...
            handle.states(k), 'error', handle.snapshot, ...
            'Reason', char(p.Results.Reason));
        handle.collected(k) = true;
    end
end
handle.canceled = true;
handle.completed = true;
handle.elapsedSec = toc(handle.timerToken);
handle.race = radio.stream.summarizeProbeResults( ...
    handle.results, handle.epochId, handle.generation);
handle.race.executionMode = handle.executionMode;
handle.race.elapsedSec = handle.elapsedSec;
handle.race.staleResultCount = handle.staleResultCount;
handle.race.taskErrorCount = handle.taskErrorCount;
handle.race.canceled = true;
handle.race.maxInFlight = handle.maxInFlight;
handle.race.peakInFlight = handle.peakInFlight;
handle.race.earlyTerminated = handle.earlyTerminated;
handle.race.canceledTaskCount = handle.canceledTaskCount;
status = handle.race;
end
