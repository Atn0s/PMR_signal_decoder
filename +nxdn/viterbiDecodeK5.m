function [bits, info] = viterbiDecodeK5(coded)
%VITERBIDECODEK5 Hard-decision NXDN K=5, rate-1/2 Viterbi decoder.
coded = double(coded(:));
if mod(numel(coded), 2) ~= 0
    error('nxdn:viterbiDecodeK5:BadLength', 'Coded length must be even.');
end
steps = numel(coded) / 2;
states = 16;
metric = inf(states, 1);
metric(1) = 0;
prevState = zeros(steps, states, 'uint8');
prevInput = false(steps, states);
for t = 1:steps
    observed = coded(2*t-1:2*t);
    nextMetric = inf(states, 1);
    for state = 0:states-1
        if ~isfinite(metric(state + 1)), continue; end
        previous = bitget(uint8(state), 4:-1:1) ~= 0;
        for input = 0:1
            u = input ~= 0;
            expected = [xor(xor(u, previous(3)), previous(4)); ...
                xor(xor(xor(u, previous(1)), previous(2)), previous(4))];
            valid = ~isnan(observed);
            branch = sum(double(expected(valid)) ~= observed(valid));
            nextBits = [u previous(1:3)];
            next = double(nextBits) * [8; 4; 2; 1];
            cost = metric(state + 1) + branch;
            if cost < nextMetric(next + 1)
                nextMetric(next + 1) = cost;
                prevState(t, next + 1) = uint8(state);
                prevInput(t, next + 1) = u;
            end
        end
    end
    metric = nextMetric;
end
if isfinite(metric(1))
    finalState = 0;
else
    [~, idx] = min(metric);
    finalState = idx - 1;
end
bits = false(steps, 1);
state = finalState;
for t = steps:-1:1
    bits(t) = prevInput(t, state + 1);
    state = double(prevState(t, state + 1));
end
info = struct('metric', metric(finalState + 1), ...
    'normalized_metric', metric(finalState + 1) / max(1, nnz(~isnan(coded))), ...
    'final_state', finalState, 'ended_in_zero_state', finalState == 0);
end
