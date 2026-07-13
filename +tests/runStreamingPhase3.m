function runStreamingPhase3()
%RUNSTREAMINGPHASE3 Test deterministic probe-window characterization.
fs = 1000;
iq = complex(ones(1000, 1));
savedRng = rng;
report = radio.stream.characterizeProbeWindows(iq, fs, 'NXDN', ...
    'StartOffsetsSec', [0, 0.1, 0.2], ...
    'WindowDurationsSec', [0.1, 0.2, 0.3, 0.4], ...
    'SnrDb', [inf, 10], ...
    'FrequencyOffsetsHz', [-100, 100], ...
    'RandomSeed', 19, ...
    'StopAfterFirstConfirmation', false, ...
    'ProbeFcn', @fakeProbe);

assert(numel(report.conditions) == 12);
assert(numel(report.trials) == 48);
assert(numel(report.summary) == 4);
assert(all([report.summary.successRatio] == 1));
assert(all(abs([report.summary.p50Sec] - 0.3) < 1e-12));
assert(all(abs([report.summary.p95Sec] - 0.39) < 1e-12));
assert(all(abs([report.summary.p99Sec] - 0.398) < 1e-12));
assert(isequal(rng, savedRng));
fprintf('Streaming phase-3 characterization tests passed.\n');
end

function result = fakeProbe(snapshot, probe, epochId, generation)
state = radio.stream.probeStateInit( ...
    probe, epochId, generation, snapshot.sourceSampleStart);
durationSec = numel(snapshot.iq) / snapshot.sampleRateHz;
offsetSec = double(snapshot.sourceSampleStart) / snapshot.sampleRateHz;
thresholdSec = 0.2 + offsetSec;
if durationSec + 1 / snapshot.sampleRateHz >= thresholdSec
    status = 'confirmed';
    confidence = 0.99;
    evidenceClass = 'synthetic_threshold';
else
    status = 'no_evidence';
    confidence = 0;
    evidenceClass = '';
end
result = radio.stream.makeProbeResult(state, status, snapshot, ...
    'Confidence', confidence, ...
    'EvidenceClass', evidenceClass, ...
    'ElapsedSec', 0.001);
end
