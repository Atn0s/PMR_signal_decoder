function [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        decodeProtocolWindow(protocol, snapshot)
%DECODEPROTOCOLWINDOW Decode one centered IQ snapshot with a registered protocol.
radio.stream.validateIqChunk(snapshot);
protocol = radio.normalizeProtocolNames({protocol});
protocol = protocol{1};
diagnostics = struct();
frequencyOffsetHz = 0;
timingState = struct();
iqInput = double(snapshot.iq(:));

if strcmp(protocol, 'TETRA')
    context = struct('activeStartSec', 0, ...
        'activeEndSec', numel(snapshot.iq) / snapshot.sampleRateHz);
    [pdus, diagnostics] = tetra.decodeIqWindow( ...
        iqInput, snapshot.sampleRateHz, tetra.config(), context);
    frequencyOffsetHz = radio.getNestedField( ...
        diagnostics, 'coarseFrequencyOffsetHz', 0) + ...
        radio.getNestedField(diagnostics, 'residualCorrectionHz', 0);
    timingState = struct( ...
        'phaseSamples', radio.getNestedField(diagnostics, 'timingPhaseSamples', NaN), ...
        'errorRad', radio.getNestedField(diagnostics, 'timingErrorRad', NaN), ...
        'decisionVariant', radio.getNestedField(diagnostics, 'decisionVariant', ''));
    pdus = radio.normalizePdus(pdus);
    return;
end

specs = radio.protocolRegistry();
idx = find(strcmp({specs.name}, protocol), 1);
if isempty(idx)
    error('radio:stream:decodeProtocolWindow:UnknownProtocol', ...
        'No decoder is registered for protocol %s.', protocol);
end
spec = specs(idx);
targetSampleRateHz = spec.targetSampleRateHz;
if abs(snapshot.sampleRateHz - targetSampleRateHz) < 1e-6
    iq = iqInput;
else
    iq = common.resampleTo(iqInput, ...
        snapshot.sampleRateHz, targetSampleRateHz);
end

if strcmp(protocol, 'NXDN')
    [y, frontendInfo] = spec.frontendFcn(iq, targetSampleRateHz, spec.config);
    [pdus, diagnostics] = spec.decodeFcn(y, spec.config);
    frequencyOffsetHz = frontendInfo.coarseFrequencyOffsetHz + ...
        frontendInfo.residualFrequencyOffsetHz;
    timingState = frontendInfo;
else
    y = spec.frontendFcn(iq, targetSampleRateHz, spec.config);
    pdus = spec.decodeFcn(y, spec.config);
end
pdus = radio.normalizePdus(pdus);
end
