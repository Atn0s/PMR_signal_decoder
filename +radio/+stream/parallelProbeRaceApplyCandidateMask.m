function handle = parallelProbeRaceApplyCandidateMask(handle, candidateMask)
%PARALLELPROBERACEAPPLYCANDIDATEMASK Narrow a running race in place.
% A modulation-family decision can become reliable after a race has
% already started.  Cancel excluded work immediately while preserving
% completed state for the candidates that remain eligible.
if handle.completed
    return;
end
validateattributes(candidateMask, {'logical', 'numeric'}, ...
    {'vector', 'numel', numel(handle.registry)}, mfilename, ...
    'CandidateMask');
candidateMask = logical(candidateMask(:));
candidateMask = handle.candidateMask & candidateMask;
if ~any(candidateMask)
    error('radio:stream:parallelProbeRaceApplyCandidateMask:EmptyMask', ...
        'A running protocol race must retain at least one candidate.');
end

excluded = find(handle.candidateMask & ~candidateMask);
handle.candidateMask = candidateMask;
for n = 1:numel(excluded)
    k = excluded(n);
    handle.eligible(k) = false;
    if handle.submitted(k) && ~handle.collected(k)
        try
            cancel(handle.futures{k});
        catch
        end
        handle.canceledTaskCount = handle.canceledTaskCount + 1;
    end
    handle.results(k) = radio.stream.makeProbeResult( ...
        handle.states(k), 'rejected', handle.snapshot, ...
        'Reason', 'modulation_family_gate_excluded_during_race');
    handle.collected(k) = true;
end
handle = radio.stream.parallelProbeRaceSubmitPending(handle);
end
