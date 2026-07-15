function runStreamingPhase6()
%RUNSTREAMINGPHASE6 Test bounded-overlap locked decoding and PDU ledger.
testOverlapLedger();
testRingOverrunIsExplicitFailure();
testSemanticDedupCanBeDisabled();
testFiveRealProtocols();
fprintf('Streaming phase-6 continuous decoder tests passed.\n');
end

function testRingOverrunIsExplicitFailure()
fs = 1000;
epoch = radio.stream.newEpoch(1, 32, 4, 0);
state = radio.stream.lockedDecoderInit('DMR', epoch, fs, ...
    'LastProcessedEndSample', 0, ...
    'DecodeFcn', @tests.fakeLockedDecoder);
buffer = radio.stream.ringBufferInit(fs, 0.2);
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(300, 1)), fs, 0));
[state, output] = radio.stream.lockedDecoderProcess(state, buffer); %#ok<ASGLU>
assert(strcmp(output.status, 'error'));
assert(strcmp(output.errorReason, 'locked_decoder_input_overrun'));
assert(output.overrunSamples == uint64(100));
assert(output.newPduCount == 0);
end

function testSemanticDedupCanBeDisabled()
fs = 1000;
pdu1 = struct('protocol', 'DMR', 'type', 'DMR_CALL', ...
    'src', 10, 'dst', 20, 'ts', 1, 'flco', '', 'fid', '', ...
    'extra', struct('stream', struct('source_sample', uint64(100))));
pdu2 = pdu1;
pdu2.extra.stream.source_sample = uint64(200);
[semantic1, persistent1] = radio.stream.streamPduKey(pdu1, fs);
[semantic2, persistent2] = radio.stream.streamPduKey(pdu2, fs);
assert(persistent1 && persistent2 && strcmp(semantic1, semantic2));
[timed1, persistent1] = radio.stream.streamPduKey( ...
    pdu1, fs, 'SemanticDeduplicate', false);
[timed2, persistent2] = radio.stream.streamPduKey( ...
    pdu2, fs, 'SemanticDeduplicate', false);
assert(~persistent1 && ~persistent2 && ~strcmp(timed1, timed2));
end

function testOverlapLedger()
fs = 1000;
epoch = radio.stream.newEpoch(1, 31, 4, 0);
buffer = radio.stream.ringBufferInit(fs, 2.0);
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(300, 1)), fs, 0));
state = radio.stream.lockedDecoderInit('DMR', epoch, fs, ...
    'LastProcessedEndSample', 0, ...
    'DecodeFcn', @tests.fakeLockedDecoder);

[state, first] = radio.stream.lockedDecoderProcess(state, buffer);
assert(strcmp(first.status, 'healthy'));
assert(first.newPduCount == 3);
assert(isequal(sourceSamples(first.newPdus), uint64([0, 100, 200])));

[state, repeated] = radio.stream.lockedDecoderProcess(state, buffer);
assert(repeated.newPduCount == 0);
assert(strcmp(repeated.errorReason, 'no_new_samples'));

[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(100, 1)), fs, 300, ...
        'SequenceNumber', 1));
[state, second] = radio.stream.lockedDecoderProcess(state, buffer);
assert(second.newPduCount == 1);
assert(sourceSamples(second.newPdus) == uint64(300));
assert(state.decodeCount == uint64(2));
assert(numel(unique(state.seenKeys)) == numel(state.seenKeys));
end

function samples = sourceSamples(pdus)
samples = arrayfun(@(p) p.extra.stream.source_sample, pdus);
end

function testFiveRealProtocols()
root = fullfile(pybackend.defaultPythonRoot(), 'data');
cases = { ...
    'DMR', fullfile(root, 'dmr_1_78125.rawiq'), 78125, 0.5, 1.5; ...
    'P25', fullfile(root, 'p25_1_78125.rawiq'), 78125, 0.0, 1.0; ...
    'dPMR', fullfile(root, 'dpmr_1_48000.rawiq'), 48000, 0.0, 1.5; ...
    'NXDN', fullfile('signal_data', 'nxdn96_1_78125.rawiq'), 78125, 0.5, 1.0; ...
    'TETRA', fullfile(root, ...
        'tetra_dmo_20240413_430050000_baseband.wav'), 0, 5.0, 0.5};
for k = 1:size(cases, 1)
    protocol = cases{k, 1};
    path = cases{k, 2};
    if exist(path, 'file') ~= 2, continue; end
    fs = cases{k, 3};
    if fs == 0, fs = common.detectSampleRate(path); end
    iq = common.readRawIq(path);
    base = floor(cases{k, 4} * fs);
    initialCount = ceil(cases{k, 5} * fs);
    extraCount = min(ceil(0.1 * fs), numel(iq) - base - initialCount);
    assert(extraCount > 0);

    buffer = radio.stream.ringBufferInit(fs, 8);
    firstChunk = radio.stream.makeIqChunk( ...
        iq(base+1:base+initialCount), fs, uint64(base));
    [buffer, ~] = radio.stream.ringBufferPush(buffer, firstChunk);
    epoch = radio.stream.newEpoch(1, 40 + k, 1, uint64(base));
    state = radio.stream.lockedDecoderInit(protocol, epoch, fs, ...
        'LastProcessedEndSample', uint64(base));
    [state, first] = radio.stream.lockedDecoderProcess(state, buffer);
    assert(strcmp(first.health.status, 'confirmed'));
    assert(first.newPduCount > 0);

    secondChunk = radio.stream.makeIqChunk( ...
        iq(base+initialCount+1:base+initialCount+extraCount), fs, ...
        uint64(base+initialCount), 'SequenceNumber', 1);
    [buffer, ~] = radio.stream.ringBufferPush(buffer, secondChunk);
    [~, second] = radio.stream.lockedDecoderProcess(state, buffer);
    assert(~strcmp(second.status, 'error'));
    allKeys = [keysFor(first.newPdus, fs), keysFor(second.newPdus, fs)];
    assert(numel(unique(allKeys)) == numel(allKeys));
end
end

function keys = keysFor(pdus, fs)
keys = cell(1, numel(pdus));
for k = 1:numel(pdus)
    keys{k} = radio.stream.streamPduKey(pdus(k), fs);
end
end
