function runStreamingPhase5()
%RUNSTREAMINGPHASE5 Test winner backlog decode and race coordination.
testAbsolutePduStamping();
[buffer, epoch] = testRealDmrCatchup();
testAsyncCatchupKeepsAcquisition(buffer, epoch);
fprintf('Streaming phase-5 catch-up tests passed.\n');
end

function testAbsolutePduStamping()
snapshot = radio.stream.makeIqChunk(complex(zeros(2000, 1)), 78125, 1000);
pdu = struct('protocol', 'DMR', 'type', 'LC_HEADER', ...
    'src', 1, 'dst', 2, 'ts', 0, 'flco', '', 'fid', '', ...
    'extra', struct('fs_start', 480), 'raw_bits', []);
stamped = radio.stream.stampStreamPdus(pdu, 'DMR', snapshot, 7);
assert(stamped.extra.stream.epoch_id == uint64(7));
assert(stamped.extra.stream.source_sample == uint64(1781));
assert(strcmp(stamped.extra.stream.position_basis, 'extra.fs_start'));

tetraPdu = pdu;
tetraPdu.protocol = 'TETRA';
tetraPdu.type = 'TETRA_DMAC_SYNC';
tetraPdu.extra = struct('start_time_s', 0.02);
stamped = radio.stream.stampStreamPdus(tetraPdu, 'TETRA', snapshot, 8);
assert(stamped.extra.stream.source_sample == uint64(2563));
assert(strcmp(stamped.extra.stream.position_basis, 'extra.start_time_s'));

buffer = radio.stream.ringBufferInit(78125, 0.1);
[buffer, ~] = radio.stream.ringBufferPush(buffer, ...
    radio.stream.makeIqChunk(complex(zeros(1000, 1)), 78125, 0));
epoch = radio.stream.newEpoch(1, 9, 1, 0);
seed = pdu;
seed.extra.fec = struct('rs_12_9_4_ok', true);
seed = radio.stream.stampStreamPdus(seed, 'DMR', ...
    radio.stream.ringBufferRange(buffer, 0, 1000), epoch.epochId);
seeded = radio.stream.winnerCatchup(buffer, epoch, 'DMR', ...
    'InitialPdus', seed, 'Deduplicate', false);
assert(any(strcmp({seeded.pdus.type}, 'LC_HEADER')));
assert(strcmp(seeded.health.status, 'confirmed'));
end

function [buffer, epoch] = testRealDmrCatchup()
path = fullfile(common.sampleDataRoot(), 'dmr_1_78125.rawiq');
fs = 78125;
epoch = radio.stream.newEpoch(1, 21, 3, uint64(floor(0.5 * fs)));
if exist(path, 'file') ~= 2
    buffer = radio.stream.ringBufferInit(fs, 3);
    return;
end
iq = common.readRawIq(path);
count = min(numel(iq), ceil(2.0 * fs));
chunk = radio.stream.makeIqChunk(iq(1:count), fs, 0);
buffer = radio.stream.ringBufferInit(fs, 3);
[buffer, ~] = radio.stream.ringBufferPush(buffer, chunk);
result = radio.stream.winnerCatchup( ...
    buffer, epoch, 'DMR', 'PreTriggerSec', 0.2);
assert(strcmp(result.status, 'caught_up'));
assert(result.catchupStartSample == uint64(floor(0.3 * fs)));
assert(result.catchupEndSample == uint64(count));
assert(result.caughtUpToLiveEdge);
assert(result.pduCount > 0);
assert(strcmp(result.health.status, 'confirmed'));
samples = arrayfun(@(p) p.extra.stream.source_sample, result.pdus);
assert(all(samples >= result.catchupStartSample));
assert(all(samples < result.catchupEndSample));
end

function testAsyncCatchupKeepsAcquisition(buffer, epoch)
pool = gcp('nocreate');
if isempty(pool) || buffer.count == 0
    return;
end
firstEnd = buffer.endSample;
handle = radio.stream.winnerCatchupStart( ...
    buffer, epoch, 'DMR', 'NumWorkers', pool.NumWorkers, ...
    'PreTriggerSec', 0.2);
extraCount = round(0.2 * buffer.sampleRateHz);
extra = radio.stream.makeIqChunk( ...
    complex(zeros(extraCount, 1, 'single')), buffer.sampleRateHz, firstEnd, ...
    'SequenceNumber', 2);
[buffer, ~] = radio.stream.ringBufferPush(buffer, extra);
[handle, status] = radio.stream.winnerCatchupCollect( ...
    handle, 'TimeoutSec', 30);
assert(handle.completed && strcmp(status.state, 'completed'));
assert(status.result.catchupEndSample == firstEnd);
assert(status.result.catchupEndSample < buffer.endSample);

handle = radio.stream.winnerCatchupStart( ...
    buffer, epoch, 'DMR', 'NumWorkers', pool.NumWorkers, ...
    'PreTriggerSec', 0.2);
[handle, status] = radio.stream.winnerCatchupCollect( ...
    handle, 'TimeoutSec', 30);
assert(handle.completed && strcmp(status.state, 'completed'));
assert(status.result.catchupEndSample == buffer.endSample);
assert(status.result.caughtUpToLiveEdge);
end
