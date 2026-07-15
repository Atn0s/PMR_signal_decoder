function runProtocolCandidateGate()
%RUNPROTOCOLCANDIDATEGATE Validate conservative modulation-family pruning.
testFskFamily();
testPi4DqpskFamily();
testNoiseRemainsUncertain();
testCandidateMaskSkipsExcludedProbe();
fprintf('Protocol candidate-gate tests passed.\n');
end

function testFskFamily()
fs = 48000;
sps = 10;
saved = rng;
rng(3301);
levelsHz = [-2400; -800; 800; 2400];
symbols = levelsHz(randi(4, round(0.25 * fs / sps), 1));
instantaneousHz = repelem(symbols, sps);
iq = exp(1i .* cumsum(2 .* pi .* instantaneousHz ./ fs));
rng(saved);
snapshot = radio.stream.makeIqChunk(iq, fs, 0);
gate = radio.stream.protocolCandidateGate( ...
    snapshot, radio.stream.probeRegistry());
assert(strcmp(gate.family, 'fsk4'));
assert(~any(strcmp(gate.candidateProtocols, 'TETRA')));
assert(all(ismember({'DMR','P25','dPMR','NXDN'}, ...
    gate.candidateProtocols)));
end

function testPi4DqpskFamily()
fs = 72000;
sps = 4;
increments = repmat([pi/4; 3*pi/4; -pi/4; -3*pi/4], 1200, 1);
phaseSteps = repelem(increments ./ sps, sps);
iq = exp(1i .* cumsum(phaseSteps));
snapshot = radio.stream.makeIqChunk(iq, fs, 0);
gate = radio.stream.protocolCandidateGate( ...
    snapshot, radio.stream.probeRegistry());
assert(strcmp(gate.family, 'pi4dqpsk'));
assert(isequal(gate.candidateProtocols, {'TETRA'}));
end

function testNoiseRemainsUncertain()
fs = 125000;
saved = rng;
rng(3302);
iq = randn(round(0.25 * fs), 1) + 1i .* ...
    randn(round(0.25 * fs), 1);
rng(saved);
snapshot = radio.stream.makeIqChunk(iq, fs, 0);
gate = radio.stream.protocolCandidateGate( ...
    snapshot, radio.stream.probeRegistry());
assert(strcmp(gate.family, 'uncertain'));
assert(all(gate.candidateMask));
end

function testCandidateMaskSkipsExcludedProbe()
snapshot = radio.stream.makeIqChunk( ...
    complex(zeros(48000, 1, 'single')), 48000, 0);
registry = radio.stream.probeRegistry();
mask = ~strcmp({registry.name}, 'TETRA');
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'Registry', registry, 'Mode', 'serial', ...
    'CandidateMask', mask, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
tetraIndex = find(strcmp({registry.name}, 'TETRA'), 1);
assert(handle.states(tetraIndex).attemptCount == 0);
assert(strcmp(handle.race.results(tetraIndex).status, 'rejected'));
assert(strcmp(handle.race.outcome, 'confirmed'));
assert(strcmp(handle.race.winner.protocol, 'DMR'));
end
