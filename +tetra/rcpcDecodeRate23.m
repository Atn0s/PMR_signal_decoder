function [decodedBits, info] = rcpcDecodeRate23(encodedBits, type2Length)
%RCPCDECODERATE23 Hard-decision Viterbi decoder for TETRA RCPC rate 2/3.
encodedBits = encodedBits(:) ~= 0;
if nargin < 2 || isempty(type2Length)
    type2Length = round(numel(encodedBits) * 2 / 3);
end
if mod(type2Length, 2) ~= 0 || numel(encodedBits) ~= type2Length * 3 / 2
    error('tetra:rcpcDecodeRate23:BadLength', ...
        'Rate 2/3 RCPC expects encoded length 3/2 of an even type-2 length.');
end

obs = observationsByInput(numel(encodedBits), type2Length);
nStates = 16;
infMetric = 1e9;
metrics = infMetric .* ones(nStates, 1);
metrics(1) = 0;
prevState = zeros(type2Length, nStates);
prevInput = false(type2Length, nStates);

for k = 1:type2Length
    nextMetrics = infMetric .* ones(nStates, 1);
    nextPrevState = zeros(1, nStates);
    nextPrevInput = false(1, nStates);
    for state = 0:nStates-1
        baseMetric = metrics(state + 1);
        if baseMetric >= infMetric
            continue;
        end
        for inputBit = 0:1
            [out, nextState] = motherBranch(state, inputBit);
            branchMetric = 0;
            for m = 1:size(obs{k}, 1)
                outIdx = obs{k}(m, 1);
                rxIdx = obs{k}(m, 2);
                branchMetric = branchMetric + double(out(outIdx) ~= encodedBits(rxIdx));
            end
            metric = baseMetric + branchMetric;
            idx = nextState + 1;
            if metric < nextMetrics(idx)
                nextMetrics(idx) = metric;
                nextPrevState(idx) = state;
                nextPrevInput(idx) = inputBit ~= 0;
            end
        end
    end
    metrics = nextMetrics;
    prevState(k, :) = nextPrevState;
    prevInput(k, :) = nextPrevInput;
end

finalState = 0;
if metrics(finalState + 1) >= infMetric
    [~, finalIdx] = min(metrics);
    finalState = finalIdx - 1;
end

decodedBits = false(type2Length, 1);
state = finalState;
for k = type2Length:-1:1
    decodedBits(k) = prevInput(k, state + 1);
    state = prevState(k, state + 1);
end

info = struct();
info.metric = metrics(finalState + 1);
info.finalState = finalState;
info.startedInZeroState = true;
info.endedInZeroState = finalState == 0;
end

function obs = observationsByInput(encodedLength, type2Length)
p = [1 2 5];
obs = cell(type2Length, 1);
for j = 1:encodedLength
    coeff = p(1 + mod(j - 1, numel(p)));
    motherIdx = 8 * floor((j - 1) / numel(p)) + coeff;
    inputIdx = floor((motherIdx - 1) / 4) + 1;
    outIdx = mod(motherIdx - 1, 4) + 1;
    if inputIdx <= type2Length
        obs{inputIdx}(end+1, :) = [outIdx, j]; %#ok<AGROW>
    end
end
end

function [out, nextState] = motherBranch(state, inputBit)
prev = bitget(uint8(state), 4:-1:1) ~= 0;
u = inputBit ~= 0;
out = [ ...
    xor(xor(u, prev(1)), prev(4)), ...
    xor(xor(u, prev(2)), xor(prev(3), prev(4))), ...
    xor(xor(u, prev(1)), xor(prev(2), prev(4))), ...
    xor(xor(u, prev(1)), xor(prev(3), prev(4)))];
nextBits = [u, prev(1:3)];
nextState = double(nextBits) * [8; 4; 2; 1];
end
