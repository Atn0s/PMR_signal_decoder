function [ready, reason] = probeReady(state, snapshot, probe)
%PROBEREADY Return whether a probe should run on the current snapshot.
if any(strcmp(state.status, {'confirmed', 'rejected'}))
    ready = false;
    reason = 'terminal_probe_state';
    return;
end
availableSec = numel(snapshot.iq) / snapshot.sampleRateHz;
if availableSec + 1 / snapshot.sampleRateHz < state.nextWindowSec
    ready = false;
    reason = 'awaiting_probe_window';
    return;
end
if snapshot.sourceSampleEnd <= state.lastAttemptedEndSample
    ready = false;
    reason = 'awaiting_new_samples';
    return;
end
if ~strcmp(state.protocol, probe.name)
    error('radio:stream:probeReady:Protocol', ...
        'Probe state and registry entry differ.');
end
ready = true;
reason = '';
end
