function [state, result] = runProtocolProbe(state, snapshot, probe)
%RUNPROTOCOLPROBE Execute one compatibility probe on a buffer snapshot.
% Existing whole-window decoders are reused until incremental decoders exist.
radio.stream.validateIqChunk(snapshot);
if ~strcmp(state.protocol, probe.name)
    error('radio:stream:runProtocolProbe:Protocol', ...
        'Probe state and probe specification differ.');
end
if any(strcmp(state.status, {'confirmed', 'rejected'})) && ...
        ~isempty(state.lastResult)
    result = state.lastResult;
    return;
end

availableSec = numel(snapshot.iq) / snapshot.sampleRateHz;
if availableSec + 1 / snapshot.sampleRateHz < state.nextWindowSec
    result = radio.stream.makeProbeResult(state, 'pending', snapshot, ...
        'Reason', 'awaiting_probe_window');
    state.status = result.status;
    state.lastResult = result;
    return;
end
if snapshot.sourceSampleEnd <= state.lastAttemptedEndSample
    result = radio.stream.makeProbeResult(state, 'pending', snapshot, ...
        'Reason', 'awaiting_new_samples');
    state.status = result.status;
    state.lastResult = result;
    return;
end

maxSamples = max(1, ceil(probe.maxWindowSec * snapshot.sampleRateHz));
if numel(snapshot.iq) > maxSamples
    snapshot = radio.stream.makeIqChunk(snapshot.iq(1:maxSamples), ...
        snapshot.sampleRateHz, snapshot.sourceSampleStart, ...
        'ChannelId', snapshot.channelId, ...
        'SequenceNumber', snapshot.sequenceNumber, ...
        'TimestampStartNs', snapshot.timestampStartNs, ...
        'CenterFrequencyHz', snapshot.centerFrequencyHz, ...
        'Discontinuity', snapshot.discontinuity, ...
        'DroppedSourceSamples', snapshot.droppedSourceSamples);
end

timer = tic;
try
    [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        decodeProbeWindow(state.protocol, snapshot, probe);
    verdict = radio.stream.evaluateProbeEvidence( ...
        state.protocol, pdus, diagnostics);
    status = verdict.status;
    reason = verdict.reason;
    reachedMax = numel(snapshot.iq) / snapshot.sampleRateHz + ...
        1 / snapshot.sampleRateHz >= ...
        probe.maxWindowSec;
    if reachedMax && ~strcmp(status, 'confirmed')
        status = 'rejected';
        reason = 'max_probe_window_without_strong_confirmation';
    end
    result = radio.stream.makeProbeResult(state, status, snapshot, ...
        'Confidence', verdict.confidence, ...
        'EvidenceClass', verdict.evidenceClass, ...
        'Evidence', verdict.evidence, ...
        'FrequencyOffsetHz', frequencyOffsetHz, ...
        'TimingState', timingState, ...
        'ElapsedSec', toc(timer), ...
        'Reason', reason, ...
        'PduCount', numel(pdus));
catch ME
    result = radio.stream.makeProbeResult(state, 'error', snapshot, ...
        'ElapsedSec', toc(timer), ...
        'Reason', sprintf('%s: %s', ME.identifier, ME.message));
end

state.attemptCount = state.attemptCount + uint32(1);
state.lastAttemptedEndSample = snapshot.sourceSampleEnd;
state.status = result.status;
state.lastResult = result;
if any(strcmp(result.status, {'no_evidence', 'candidate', 'error'}))
    attemptedSec = numel(snapshot.iq) / snapshot.sampleRateHz;
    state.nextWindowSec = min(probe.maxWindowSec, ...
        max(probe.initialWindowSec, attemptedSec * probe.windowGrowthFactor));
end
end

function [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        decodeProbeWindow(protocol, snapshot, probe)
diagnostics = struct();
frequencyOffsetHz = 0;
timingState = struct();

if strcmp(protocol, 'TETRA')
    context = struct('activeStartSec', 0, ...
        'activeEndSec', numel(snapshot.iq) / snapshot.sampleRateHz);
    [pdus, diagnostics] = tetra.decodeIqWindow( ...
        snapshot.iq, snapshot.sampleRateHz, tetra.config(), context);
    frequencyOffsetHz = radio.getNestedField( ...
        diagnostics, 'coarseFrequencyOffsetHz', 0) + ...
        radio.getNestedField(diagnostics, 'residualCorrectionHz', 0);
    timingState = struct( ...
        'phaseSamples', radio.getNestedField(diagnostics, 'timingPhaseSamples', NaN), ...
        'errorRad', radio.getNestedField(diagnostics, 'timingErrorRad', NaN), ...
        'decisionVariant', radio.getNestedField(diagnostics, 'decisionVariant', ''));
    return;
end

specs = radio.protocolRegistry();
idx = find(strcmp({specs.name}, protocol), 1);
if isempty(idx)
    error('radio:stream:runProtocolProbe:UnknownProtocol', ...
        'No decoder is registered for protocol %s.', protocol);
end
spec = specs(idx);
if abs(snapshot.sampleRateHz - probe.targetSampleRateHz) < 1e-6
    iq = snapshot.iq;
else
    iq = common.resampleTo(snapshot.iq, ...
        snapshot.sampleRateHz, probe.targetSampleRateHz);
end

if strcmp(protocol, 'NXDN')
    [y, frontendInfo] = spec.frontendFcn(iq, probe.targetSampleRateHz, spec.config);
    [pdus, diagnostics] = spec.decodeFcn(y, spec.config);
    frequencyOffsetHz = frontendInfo.coarseFrequencyOffsetHz + ...
        frontendInfo.residualFrequencyOffsetHz;
    timingState = frontendInfo;
else
    y = spec.frontendFcn(iq, probe.targetSampleRateHz, spec.config);
    pdus = spec.decodeFcn(y, spec.config);
end
pdus = radio.normalizePdus(pdus);
end
