function handle = parallelProbeRaceSubmitPending(handle)
%PARALLELPROBERACESUBMITPENDING Fill the bounded per-carrier worker share.
if handle.completed || ~strcmp(handle.executionMode, 'parallel')
    return;
end
active = handle.submitted & ~handle.collected;
available = max(0, floor(handle.maxInFlight) - nnz(active));
if available == 0
    return;
end
pending = find(handle.eligible & ~handle.submitted & ~handle.collected);
count = min(available, numel(pending));
for n = 1:count
    k = pending(n);
    handle.futures{k} = parfeval( ...
        handle.pool, @radio.stream.executeProbeTask, 2, ...
        handle.states(k), handle.snapshot, handle.registry(k), ...
        handle.taskFcn, handle.taskContext);
    handle.submitted(k) = true;
end
handle.peakInFlight = max(handle.peakInFlight, ...
    nnz(handle.submitted & ~handle.collected));
end
