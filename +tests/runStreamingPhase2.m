function runStreamingPhase2()
%RUNSTREAMINGPHASE2 Tests for probe confirmation and race semantics.
testStrongEvidenceRules();
testAmbiguousAndStaleResults();
testProgressivePendingRace();
testRealProtocolProbes();
fprintf('Streaming phase-2 probe tests passed.\n');
end

function testStrongEvidenceRules()
dmrPdu = struct('type', 'LC_HEADER', ...
    'extra', struct('fec', struct('rs_12_9_4_ok', true)));
assertConfirmed('DMR', dmrPdu, struct(), 'rs_valid_full_link_control');
dmrWeak = struct('type', 'CSBK', 'extra', struct());
assert(strcmp(radio.stream.evaluateProbeEvidence( ...
    'DMR', dmrWeak, struct()).status, 'candidate'));

p25Pdu = struct('type', 'P25_NID', ...
    'extra', struct('valid_bch', true));
assertConfirmed('P25', p25Pdu, struct(), 'bch_valid_nid');

cch = struct('crc_ok', true, 'hamming_ok', true);
dpmrPdu = struct('type', 'DPMR_HEADER', ...
    'extra', struct('cch', cch));
assertConfirmed('dPMR', dpmrPdu, struct(), 'crc_valid_cch');

nxdnDiag = struct('validChannelBlockCount', 1, ...
    'quality', struct('lich_ok_count', 2));
assertConfirmed('NXDN', struct([]), nxdnDiag, ...
    'crc_valid_channel_block');

tetraPdu = struct('type', 'TETRA_DMAC_SYNC', 'extra', struct());
assertConfirmed('TETRA', tetraPdu, struct(), ...
    'fec_valid_dmo_control_block');

assert(strcmp(radio.stream.evaluateProbeEvidence( ...
    'P25', struct([]), struct()).status, 'no_evidence'));
end

function testAmbiguousAndStaleResults()
snapshot = radio.stream.makeIqChunk(complex(zeros(10, 1)), 100, 0);
states = { ...
    struct('epochId', uint64(4), 'generation', uint64(2), 'protocol', 'DMR'), ...
    struct('epochId', uint64(4), 'generation', uint64(2), 'protocol', 'P25')};
r1 = radio.stream.makeProbeResult(states{1}, 'confirmed', snapshot);
r2 = radio.stream.makeProbeResult(states{2}, 'confirmed', snapshot);
summary = radio.stream.summarizeProbeResults([r1, r2], 4, 2);
assert(strcmp(summary.outcome, 'ambiguous'));
assert(isempty(summary.winner));
assert(isequal(summary.confirmedProtocols, {'DMR', 'P25'}));

r2.status = 'rejected';
summary = radio.stream.summarizeProbeResults([r1, r2], 4, 2);
assert(strcmp(summary.outcome, 'confirmed'));
assert(strcmp(summary.winner.protocol, 'DMR'));

r2.generation = uint64(1);
assertThrows(@() radio.stream.summarizeProbeResults([r1, r2], 4, 2), ...
    'radio:stream:summarizeProbeResults:StaleResult');
end

function testProgressivePendingRace()
snapshot = radio.stream.makeIqChunk(complex(zeros(50, 1)), 1000, 0);
handle = radio.stream.parallelProbeRaceStart(snapshot, [], ...
    'EpochId', 8, 'Generation', 3);
states = handle.states;
race = handle.race;
assert(numel(states) == 5);
assert(strcmp(race.outcome, 'classifying'));
assert(all(strcmp({race.results.status}, 'pending')));
assert(all([race.results.epochId] == uint64(8)));
assert(all([race.results.generation] == uint64(3)));

probe = radio.stream.probeRegistry({'DMR'});
maxSnapshot = radio.stream.makeIqChunk( ...
    complex(zeros(ceil(probe.maxWindowSec * 48000), 1)), 48000, 0);
state = radio.stream.probeStateInit(probe, 9, 4, 0);
[~, rejected] = radio.stream.runProtocolProbe(state, maxSnapshot, probe);
assert(strcmp(rejected.status, 'rejected'));
end

function testRealProtocolProbes()
root = common.sampleDataRoot();
cases = { ...
    'DMR', fullfile(root, 'dmr_1_78125.rawiq'), 78125, 0.5, 1.5; ...
    'P25', fullfile(root, 'p25_1_78125.rawiq'), 78125, 0.0, 1.0; ...
    'dPMR', fullfile(root, 'dpmr_1_48000.rawiq'), 48000, 0.0, 1.5; ...
    'NXDN', fullfile('signal_data', 'nxdn96_1_78125.rawiq'), 78125, 0.5, 1.0; ...
    'TETRA', fullfile(root, ...
        'tetra_dmo_20240413_430050000_baseband.wav'), 0, 5.0, 2.6};
expectedEvidence = { ...
    'rs_valid_full_link_control', ...
    'bch_valid_nid', ...
    'crc_valid_cch', ...
    'crc_valid_channel_block', ...
    'fec_valid_dmo_control_block'};

for k = 1:size(cases, 1)
    protocol = cases{k, 1};
    path = cases{k, 2};
    if exist(path, 'file') ~= 2
        continue;
    end
    fs = cases{k, 3};
    if fs == 0
        fs = common.detectSampleRate(path);
    end
    iq = common.readRawIq(path);
    startSample = floor(cases{k, 4} * fs);
    count = min(floor(cases{k, 5} * fs), numel(iq) - startSample);
    snapshot = radio.stream.makeIqChunk( ...
        iq(startSample+1:startSample+count), fs, uint64(startSample));
    probe = radio.stream.probeRegistry({protocol});
    state = radio.stream.probeStateInit( ...
        probe, uint64(11), uint64(5), uint64(startSample));
    [state, result] = radio.stream.runProtocolProbe(state, snapshot, probe);
    assert(strcmp(result.status, 'confirmed'));
    assert(strcmp(result.evidenceClass, expectedEvidence{k}));
    assert(result.pduCount > 0 || strcmp(protocol, 'NXDN'));
    assert(state.attemptCount == uint32(1));
end
end

function assertConfirmed(protocol, pdus, diagnostics, evidenceClass)
result = radio.stream.evaluateProbeEvidence(protocol, pdus, diagnostics);
assert(strcmp(result.status, 'confirmed'));
assert(strcmp(result.evidenceClass, evidenceClass));
end

function assertThrows(fn, identifier)
didThrow = false;
try
    fn();
catch ME
    didThrow = strcmp(ME.identifier, identifier);
end
assert(didThrow);
end
