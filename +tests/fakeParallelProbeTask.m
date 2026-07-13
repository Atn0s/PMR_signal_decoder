function [state, result] = fakeParallelProbeTask( ...
        state, snapshot, probe, context)
%FAKEPARALLELPROBETASK Deterministic worker task for race lifecycle tests.
delaySec = protocolValue(context, 'DelaySecByProtocol', probe.name, ...
    fieldOr(context, 'DelaySec', 0));
if delaySec > 0, pause(delaySec); end
status = protocolValue(context, 'StatusByProtocol', probe.name, ...
    fieldOr(context, 'Status', 'rejected'));

state.attemptCount = state.attemptCount + uint32(1);
state.lastAttemptedEndSample = snapshot.sourceSampleEnd;
state.status = status;
confidence = 0;
evidenceClass = '';
if strcmp(status, 'confirmed')
    confidence = 0.99;
    evidenceClass = 'synthetic_parallel_confirmation';
end
result = radio.stream.makeProbeResult(state, status, snapshot, ...
    'Confidence', confidence, ...
    'EvidenceClass', evidenceClass, ...
    'ElapsedSec', delaySec);

generationDelta = fieldOr(context, 'GenerationDelta', 0);
if generationDelta ~= 0
    shifted = double(state.generation) + generationDelta;
    state.generation = uint64(max(0, shifted));
    result.generation = state.generation;
end
end

function value = protocolValue(context, fieldName, protocol, fallback)
value = fallback;
if ~isstruct(context) || ~isfield(context, fieldName)
    return;
end
items = context.(fieldName);
name = matlab.lang.makeValidName(protocol);
if isstruct(items) && isfield(items, name)
    value = items.(name);
end
end

function value = fieldOr(s, name, fallback)
if isstruct(s) && isfield(s, name)
    value = s.(name);
else
    value = fallback;
end
end
