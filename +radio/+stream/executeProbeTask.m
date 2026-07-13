function [state, result] = executeProbeTask( ...
        state, snapshot, probe, taskFcn, taskContext)
%EXECUTEPROBETASK Worker entry point shared by real and deterministic probes.
if nargin < 4 || isempty(taskFcn)
    [state, result] = radio.stream.runProtocolProbe(state, snapshot, probe);
else
    if nargin < 5, taskContext = struct(); end
    [state, result] = taskFcn(state, snapshot, probe, taskContext);
end
end
