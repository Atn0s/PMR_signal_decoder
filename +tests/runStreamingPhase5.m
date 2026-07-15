function runStreamingPhase5()
%RUNSTREAMINGPHASE5 Test winner backlog decode and race coordination.
testAbsolutePduStamping();
[buffer, epoch] = testRealDmrCatchup();
testSerialCoordinator();
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
end

function [buffer, epoch] = testRealDmrCatchup()
path = fullfile(pybackend.defaultPythonRoot(), 'data', 'dmr_1_78125.rawiq');
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

function testSerialCoordinator()
cfg = radio.stream.defaultConfig();
cfg.ringBufferSec = 2.0;
cfg.preTriggerSec = 0.1;
cfg.activity.initialNoiseFloorDb = -40;
cfg.activity.minOnSec = 0.05;
cfg.activity.offHangSec = 0.06;
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
coordinator = radio.stream.raceCoordinatorInit(1000, ...
    'Config', cfg, ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);

signal = complex(ones(100, 1));
for k = 0:2
    [coordinator, output] = radio.stream.raceCoordinatorFeed( ...
        coordinator, radio.stream.makeIqChunk( ...
            signal, 1000, 100 * k, 'SequenceNumber', k));
end
assert(strcmp(output.state, 'LOCKED'));
assert(strcmp(output.selectedProtocol, 'DMR'));
assert(coordinator.catchupPassCount == 1);
assert(coordinator.lastCatchup.catchupStartSample == uint64(0));
assert(coordinator.lastCatchup.catchupEndSample == uint64(300));
assert(coordinator.lastCatchup.caughtUpToLiveEdge);

coordinator.deferLockedDecode = true;
for k = 3:5
    [coordinator, output] = radio.stream.raceCoordinatorFeed( ...
        coordinator, radio.stream.makeIqChunk( ...
            signal, 1000, 100 * k, 'SequenceNumber', k));
    assert(isempty(output.decoder));
end
assert(coordinator.decoderState.lastProcessedEndSample == uint64(300));
coordinator.deferLockedDecode = false;
[coordinator, output] = radio.stream.raceCoordinatorFeed( ...
    coordinator, radio.stream.makeIqChunk( ...
        signal, 1000, 600, 'SequenceNumber', 6));
assert(~isempty(output.decoder));
assert(coordinator.decoderState.lastProcessedEndSample == uint64(700));

noise = complex(1e-3 .* ones(100, 1));
[~, output] = radio.stream.raceCoordinatorFeed( ...
    coordinator, radio.stream.makeIqChunk( ...
        noise, 1000, 700, 'SequenceNumber', 7));
assert(strcmp(output.state, 'NO_SIGNAL'));
assert(isempty(output.selectedProtocol));
end

function testAsyncCatchupKeepsAcquisition(buffer, epoch)
pool = gcp('nocreate');
if isempty(pool) || buffer.count == 0
    return;
end
firstEnd = buffer.endSample;
handle = radio.stream.winnerCatchupStart( ...
    buffer, epoch, 'DMR', 'Mode', 'parallel', 'NumWorkers', pool.NumWorkers, ...
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
    buffer, epoch, 'DMR', 'Mode', 'parallel', 'NumWorkers', pool.NumWorkers, ...
    'PreTriggerSec', 0.2);
[handle, status] = radio.stream.winnerCatchupCollect( ...
    handle, 'TimeoutSec', 30);
assert(handle.completed && strcmp(status.state, 'completed'));
assert(status.result.catchupEndSample == buffer.endSample);
assert(status.result.caughtUpToLiveEdge);
end
