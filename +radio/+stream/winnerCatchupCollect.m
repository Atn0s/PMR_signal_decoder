function [handle, status] = winnerCatchupCollect(handle, varargin)
%WINNERCATCHUPCOLLECT Wait for winner catch-up with a bounded timeout.
p = inputParser;
p.addParameter('TimeoutSec', inf);
p.addParameter('PollIntervalSec', 0.01);
p.parse(varargin{:});
timer = tic;
while ~handle.completed
    [handle, status] = radio.stream.winnerCatchupPoll(handle);
    if handle.completed, return; end
    if toc(timer) >= p.Results.TimeoutSec
        status.state = 'running';
        status.timedOut = true;
        return;
    end
    pause(p.Results.PollIntervalSec);
end
[handle, status] = radio.stream.winnerCatchupPoll(handle);
end
