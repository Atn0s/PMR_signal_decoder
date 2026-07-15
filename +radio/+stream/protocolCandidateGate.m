function gate = protocolCandidateGate(snapshot, registry, varargin)
%PROTOCOLCANDIDATEGATE Conservatively separate TETRA from 4FSK protocols.
% The gate only removes a modulation family when differential-phase
% evidence is strong.  Ambiguous, short, or noise-like inputs retain every
% registered protocol so the gate cannot turn uncertainty into a miss.
p = inputParser;
p.addParameter('MinAnalysisSec', 0.08);
p.addParameter('MinDecisionSec', 0.18);
p.addParameter('MaxAnalysisSec', 0.25);
p.addParameter('ActiveAmplitudeQuantile', 0.60);
p.parse(varargin{:});
radio.stream.validateIqChunk(snapshot);

if nargin < 2 || isempty(registry)
    registry = radio.stream.probeRegistry();
end
names = {registry.name};
candidateMask = true(numel(registry), 1);
gate = struct( ...
    'family', 'uncertain', ...
    'confidence', 0, ...
    'candidateMask', candidateMask, ...
    'candidateProtocols', {names}, ...
    'excludedProtocols', {{}}, ...
    'analysisSampleCount', 0, ...
    'features', emptyFeatures(), ...
    'reason', 'insufficient_or_ambiguous_modulation_evidence');
if numel(registry) <= 1 || ...
        ~any(strcmp(names, 'TETRA')) || ...
        ~any(ismember(names, fskProtocols()))
    gate.reason = 'modulation_family_competition_not_present';
    return;
end

minSamples = max(128, round( ...
    p.Results.MinAnalysisSec * snapshot.sampleRateHz));
if numel(snapshot.iq) < minSamples
    gate.reason = 'awaiting_modulation_analysis_window';
    return;
end
maxSamples = max(minSamples, round( ...
    p.Results.MaxAnalysisSec * snapshot.sampleRateHz));
x = double(snapshot.iq(max(1, end-maxSamples+1):end));
amplitude = abs(x);
threshold = localQuantile(amplitude, p.Results.ActiveAmplitudeQuantile);
valid = amplitude(1:end-1) >= threshold & ...
    amplitude(2:end) >= threshold;
differentialPhase = angle(x(2:end) .* conj(x(1:end-1)));
differentialPhase = differentialPhase(valid);
if numel(differentialPhase) < max(128, round(0.01 * numel(x)))
    gate.reason = 'too_few_active_differential_phase_samples';
    return;
end
center = angle(mean(exp(1i .* differentialPhase)));
residual = abs(angle(exp(1i .* (differentialPhase - center))));
% Express phase increments at a common 125 kS/s reference so the decision
% thresholds remain valid if a tuned front end uses 120, 125, or 48 kS/s.
residual = residual .* snapshot.sampleRateHz ./ 125000;
q75 = localQuantile(residual, 0.75);
q90 = localQuantile(residual, 0.90);
tailFraction = mean(residual > 0.20);
fourthMoment = abs(mean(exp(1i .* 4 .* residual)));
gate.analysisSampleCount = numel(x);
gate.features = struct( ...
    'phaseCenterRad', center, ...
    'phaseAbsQ75Rad', q75, ...
    'phaseAbsQ90Rad', q90, ...
    'phaseTailFractionAbove020', tailFraction, ...
    'differentialFourthMoment', fourthMoment, ...
    'activeAmplitudeThreshold', threshold, ...
    'activePairCount', numel(residual));

availableSec = numel(snapshot.iq) / snapshot.sampleRateHz;
if availableSec + 1 / snapshot.sampleRateHz < p.Results.MinDecisionSec
    gate.reason = 'awaiting_stable_modulation_decision_window';
    return;
end

isTetra = q75 >= 0.16 && tailFraction >= 0.18 && ...
    fourthMoment >= 0.35;
isFsk = q75 <= 0.13 && tailFraction <= 0.08 && ...
    fourthMoment >= 0.70;
if isTetra
    gate.family = 'pi4dqpsk';
    gate.confidence = min(0.995, 0.90 + ...
        0.30 .* min(0.25, q75 - 0.16) + ...
        0.15 .* min(0.30, tailFraction - 0.18));
    candidateMask = strcmp(names, 'TETRA').';
    gate.reason = 'strong_pi4dqpsk_differential_phase_evidence';
elseif isFsk
    gate.family = 'fsk4';
    gate.confidence = min(0.995, 0.90 + ...
        0.30 .* min(0.13, 0.13 - q75) + ...
        0.20 .* min(0.08, 0.08 - tailFraction));
    candidateMask = ismember(names, fskProtocols()).';
    gate.reason = 'strong_4fsk_differential_phase_evidence';
end
gate.candidateMask = candidateMask;
gate.candidateProtocols = names(candidateMask);
gate.excludedProtocols = names(~candidateMask);
end

function names = fskProtocols()
names = {'DMR', 'P25', 'dPMR', 'NXDN'};
end

function value = localQuantile(values, fraction)
values = sort(values(isfinite(values)));
if isempty(values)
    value = NaN;
    return;
end
index = max(1, min(numel(values), ceil(fraction * numel(values))));
value = values(index);
end

function features = emptyFeatures()
features = struct( ...
    'phaseCenterRad', NaN, ...
    'phaseAbsQ75Rad', NaN, ...
    'phaseAbsQ90Rad', NaN, ...
    'phaseTailFractionAbove020', NaN, ...
    'differentialFourthMoment', NaN, ...
    'activeAmplitudeThreshold', NaN, ...
    'activePairCount', 0);
end
