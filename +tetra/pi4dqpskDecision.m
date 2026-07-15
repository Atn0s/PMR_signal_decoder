function decision = pi4dqpskDecision(symbols, varargin)
%PI4DQPSKDECISION Differential pi/4-DQPSK dibit decision.
p = inputParser;
p.addParameter('Variant', 'standard');
p.addParameter('PhaseOffsetRad', []);
p.addParameter('PhaseOffsetStepRad', pi / 180);
p.addParameter('PhaseOffsetMaxTransitions', 8192);
p.addParameter('ValidTransitionMask', []);
p.parse(varargin{:});

symbols = symbols(:);
dphi = angle(symbols(2:end) .* conj(symbols(1:end-1)));
transitionAmplitude = min(abs(symbols(2:end)), abs(symbols(1:end-1)));
[signFactor, bitOrder] = variantParams(p.Results.Variant);
observed = signFactor .* dphi;
valid = p.Results.ValidTransitionMask;
if isempty(valid) || numel(valid) ~= numel(observed)
    valid = true(size(observed));
else
    valid = logical(valid(:));
end

centers = [-3 -1 1 3].' .* pi ./ 4;
centerBits = [1 1; 1 0; 0 0; 0 1];

phaseOffset = p.Results.PhaseOffsetRad;
if isempty(phaseOffset)
    phaseOffset = bestPhaseOffset(observed(valid), centers, ...
        p.Results.PhaseOffsetStepRad, ...
        p.Results.PhaseOffsetMaxTransitions);
end

corrected = wrapToPiLocal(observed - phaseOffset);
dist = abs(wrapToPiLocal(corrected(:) - centers(:).'));
[~, idx] = min(dist, [], 2);
phaseError = wrapToPiLocal(corrected - centers(idx));
pairs = centerBits(idx, :);
pairs = pairs(:, bitOrder);
bits = reshape(pairs.', [], 1);
dibitReliability = reliabilityFromPhaseAndAmplitude(phaseError, transitionAmplitude, valid);
bitReliability = reshape(repmat(dibitReliability(:).', 2, 1), [], 1);
bitValidMask = reshape(repmat(valid(:).', 2, 1), [], 1);

decision = struct();
decision.variant = char(p.Results.Variant);
decision.phaseOffsetRad = phaseOffset;
decision.diffPhaseRaw = dphi;
decision.diffPhaseCorrected = corrected;
decision.symbolIndex = idx;
decision.symbolPhase = centers(idx);
decision.errorRad = phaseError;
decision.bitPairs = pairs;
decision.bits = bits;
decision.dibits = pairs(:, 1) * 2 + pairs(:, 2);
decision.validTransitionMask = valid;
decision.transitionAmplitude = transitionAmplitude;
decision.dibitReliability = dibitReliability;
decision.bitReliability = bitReliability;
decision.bitValidMask = bitValidMask;
end

function [signFactor, bitOrder] = variantParams(name)
switch lower(char(name))
    case 'standard'
        signFactor = 1;
        bitOrder = [1 2];
    case 'conjugate'
        signFactor = -1;
        bitOrder = [1 2];
    case 'swap_bits'
        signFactor = 1;
        bitOrder = [2 1];
    case 'conjugate_swap'
        signFactor = -1;
        bitOrder = [2 1];
    otherwise
        error('tetra:pi4dqpskDecision:Variant', 'Unknown decision variant: %s', name);
end
end

function offset = bestPhaseOffset(values, centers, step, maxTransitions)
if isempty(values)
    offset = 0;
    return;
end
if isfinite(maxTransitions) && numel(values) > maxTransitions
    indices = unique(round(linspace(1, numel(values), maxTransitions)));
    values = values(indices);
end
offsetGrid = (-pi/4):step:(pi/4);
bestScore = inf;
offset = 0;
for off = offsetGrid
    dist = abs(wrapToPiLocal(wrapToPiLocal(values(:) - off) - centers(:).'));
    e = min(dist, [], 2);
    score = median(e);
    if score < bestScore
        bestScore = score;
        offset = off;
    end
end
end

function y = wrapToPiLocal(x)
y = mod(x + pi, 2 * pi) - pi;
end

function reliability = reliabilityFromPhaseAndAmplitude(phaseError, amplitude, valid)
phaseError = abs(phaseError(:));
amplitude = abs(amplitude(:));
if isempty(amplitude)
    reliability = zeros(size(phaseError));
    return;
end
ampScale = prctile(amplitude, 90);
if ampScale <= 0
    ampScore = zeros(size(amplitude));
else
    ampScore = min(1, amplitude ./ ampScale);
end
phaseScore = max(0, 1 - phaseError ./ (pi / 4));
reliability = ampScore(:) .* phaseScore(:);
reliability(~valid(:)) = 0;
end
