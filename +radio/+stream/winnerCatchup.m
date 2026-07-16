function result = winnerCatchup(buffer, epoch, protocol, varargin)
%WINNERCATCHUP Decode the winner from pre-trigger through the latest IQ.
p = inputParser;
p.addParameter('PreTriggerSec', radio.stream.defaultConfig().preTriggerSec);
p.addParameter('EndSample', []);
p.addParameter('Deduplicate', true);
p.addParameter('InitialPdus', struct([]));
p.parse(varargin{:});
protocol = radio.normalizeProtocolNames({protocol});
protocol = protocol{1};

endSample = p.Results.EndSample;
if isempty(endSample), endSample = buffer.endSample; end
endSample = uint64(endSample);
if endSample > buffer.endSample || endSample < buffer.startSample
    error('radio:stream:winnerCatchup:EndSample', ...
        'Catch-up end is outside the retained ring-buffer range.');
end

preTriggerSamples = uint64(round( ...
    p.Results.PreTriggerSec * buffer.sampleRateHz));
candidateStart = uint64(epoch.candidateStartSample);
if candidateStart >= preTriggerSamples
    desiredStart = candidateStart - preTriggerSamples;
else
    desiredStart = uint64(0);
end
startSample = max(buffer.startSample, desiredStart);
if startSample >= endSample
    error('radio:stream:winnerCatchup:EmptyRange', ...
        'No retained IQ is available for winner catch-up.');
end
snapshot = radio.stream.ringBufferRange(buffer, startSample, endSample);

timer = tic;
try
    [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        radio.stream.decodeProtocolWindow(protocol, snapshot);
    pdus = radio.stream.stampStreamPdus( ...
        pdus, protocol, snapshot, epoch.epochId);
    pdus = appendPdus(p.Results.InitialPdus, pdus);
    if p.Results.Deduplicate
        pdus = radio.deduplicatePdus(pdus);
    end
    verdict = radio.stream.evaluateProbeEvidence(protocol, pdus, diagnostics);
    status = 'caught_up';
    errorReason = '';
catch ME
    pdus = p.Results.InitialPdus;
    diagnostics = struct();
    frequencyOffsetHz = NaN;
    timingState = struct();
    errorReason = sprintf('%s: %s', ME.identifier, ME.message);
    if isempty(pdus)
        verdict = struct('status', 'error', 'confidence', 0, ...
            'evidenceClass', '', 'evidence', struct(), ...
            'reason', errorReason);
        status = 'decode_error';
    else
        verdict = radio.stream.evaluateProbeEvidence( ...
            protocol, pdus, diagnostics);
        status = 'caught_up_from_confirmed_probe';
    end
end

result = struct( ...
    'epochId', uint64(epoch.epochId), ...
    'generation', uint64(epoch.generation), ...
    'protocol', protocol, ...
    'status', status, ...
    'candidateStartSample', candidateStart, ...
    'desiredStartSample', desiredStart, ...
    'catchupStartSample', startSample, ...
    'catchupEndSample', endSample, ...
    'preTriggerTruncated', startSample > desiredStart, ...
    'sourceSamplesDecoded', endSample - startSample, ...
    'caughtUpToLiveEdge', endSample == buffer.endSample, ...
    'pdus', pdus, ...
    'pduCount', numel(pdus), ...
    'health', verdict, ...
    'frequencyOffsetHz', frequencyOffsetHz, ...
    'timingState', timingState, ...
    'diagnostics', diagnostics, ...
    'elapsedSec', toc(timer), ...
    'errorReason', errorReason);
end

function pdus = appendPdus(initial, decoded)
if isempty(initial)
    pdus = decoded;
elseif isempty(decoded)
    pdus = initial(:);
else
    pdus = [initial(:); decoded(:)];
end
end
