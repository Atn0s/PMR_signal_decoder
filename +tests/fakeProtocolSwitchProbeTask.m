function [state, result] = fakeProtocolSwitchProbeTask( ...
        state, snapshot, probe, ~)
%FAKEPROTOCOLSWITCHPROBETASK Confirm DMR first, then P25 after generation loss.
status = 'rejected';
if state.generation == uint64(1) && strcmp(probe.name, 'DMR')
    status = 'confirmed';
elseif state.generation >= uint64(2) && strcmp(probe.name, 'P25')
    status = 'confirmed';
end
state.attemptCount = state.attemptCount + uint32(1);
state.lastAttemptedEndSample = snapshot.sourceSampleEnd;
state.status = status;
confidence = 0;
evidenceClass = '';
if strcmp(status, 'confirmed')
    confidence = 0.99;
    evidenceClass = 'synthetic_protocol_switch';
end
result = radio.stream.makeProbeResult(state, status, snapshot, ...
    'Confidence', confidence, ...
    'EvidenceClass', evidenceClass);
end
