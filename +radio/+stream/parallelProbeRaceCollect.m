function [handle, status] = parallelProbeRaceCollect(handle, varargin)
%PARALLELPROBERACECOLLECT Wait with polling while acquisition may continue.
p = inputParser;
p.addParameter('TimeoutSec', inf);
p.addParameter('PollIntervalSec', 0.01);
p.parse(varargin{:});
timer = tic;
while ~handle.completed
    [handle, status] = radio.stream.parallelProbeRacePoll(handle);
    if handle.completed
        return;
    end
    if toc(timer) >= p.Results.TimeoutSec
        status.timedOut = true;
        return;
    end
    pause(p.Results.PollIntervalSec);
end
status = handle.race;
end
