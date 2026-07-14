function runStreamingPhase9()
%RUNSTREAMINGPHASE9 Test independent offline RF Epoch reporting.
testShortSilenceStaysInEpoch();
testLongSilenceCreatesEpochs();
testNoSignalCreatesNoEpoch();
testSameTransmitterIsNotMerged();
testProtocolSwitchRollsEpoch();
fprintf('Streaming phase-9 independent Epoch tests passed.\n');
end

function testShortSilenceStaysInEpoch()
fs = 1000;
cfg = epochConfig();
iq = [ones(500, 1); zeros(200, 1); ones(500, 1)];
[epochs, report] = radio.stream.detectActivityEpochs(iq, fs, ...
    'Config', cfg);
assert(report.activitySeen);
assert(report.epochCount == 1);
assert(numel(epochs) == 1);
assert(epochs(1).epochId == uint64(1));
assert(epochs(1).candidateStartSample == uint64(0));
assert(epochs(1).endSample == uint64(numel(iq)));
assert(strcmp(epochs(1).closeReason, 'end_of_input'));
end

function testLongSilenceCreatesEpochs()
fs = 1000;
cfg = epochConfig();
iq = twoBurstIq();
[epochs, report] = radio.stream.detectActivityEpochs(iq, fs, ...
    'Config', cfg);
assert(report.epochCount == 2);
assert(isequal([epochs.epochId], uint64([1, 2])));
assert(epochs(1).candidateStartSample == uint64(0));
assert(epochs(1).endSample == uint64(800));
assert(strcmp(epochs(1).closeReason, 'rf_activity_ended'));
assert(epochs(2).candidateStartSample == uint64(1500));
assert(epochs(2).decodeStartSample == uint64(1400));
assert(epochs(2).endSample == uint64(2000));
assert(strcmp(epochs(2).closeReason, 'end_of_input'));
end

function testNoSignalCreatesNoEpoch()
cfg = epochConfig();
[pdus, report] = radio.stream.scanBasebandIqEpochs( ...
    zeros(1000, 1), 1000, ...
    'Config', cfg, ...
    'Mode', 'serial', ...
    'ProbeTaskFcn', @tests.fakeParallelProbeTask, ...
    'DecodeFcn', @tests.fakeEpochDecoder);
assert(isempty(pdus));
assert(strcmp(report.outcome, 'no_signal'));
assert(report.epochCount == 0);
assert(report.confirmedEpochCount == 0);
assert(isempty(report.epochs));
end

function testSameTransmitterIsNotMerged()
fs = 1000;
cfg = epochConfig();
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
[pdus, report] = radio.stream.scanBasebandIqEpochs( ...
    twoBurstIq(), fs, ...
    'Config', cfg, ...
    'Mode', 'serial', ...
    'ProbeTaskFcn', @tests.fakeParallelProbeTask, ...
    'ProbeTaskContext', context, ...
    'DecodeFcn', @tests.fakeEpochDecoder);

assert(strcmp(report.outcome, 'confirmed'));
assert(strcmp(report.selectedProtocol, 'DMR'));
assert(report.epochCount == 2);
assert(report.confirmedEpochCount == 2);
assert(~isfield(report, 'sessions'));
assert(numel(pdus) == 2);
assert(all([pdus.src] == 12345));
assert(isequal(arrayfun(@(item) item.extra.stream.epoch_id, pdus), ...
    uint64([1, 2])));
assert(all([report.epochs.pduCount] == 1));
assert(isequal([report.epochs.pduStartIndex], uint64([1, 2])));
assert(isequal([report.epochs.pduEndIndex], uint64([1, 2])));
assert(report.epochs(1).classificationReport.epochId == uint64(1));
assert(report.epochs(2).classificationReport.epochId == uint64(2));
end

function testProtocolSwitchRollsEpoch()
cfg = epochConfig();
cfg.lockedSuspectWindows = 1;
cfg.lockedLostWindows = 2;
coordinator = radio.stream.raceCoordinatorInit(1000, ...
    'Config', cfg, ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeProtocolSwitchProbeTask, ...
    'LockedDecodeFcn', @tests.fakeHealthLossDecoder);

for startSample = 0:100:600
    chunk = radio.stream.makeIqChunk( ...
        complex(ones(100, 1)), 1000, startSample, ...
        'SequenceNumber', startSample / 100);
    [coordinator, output] = ...
        radio.stream.raceCoordinatorFeed(coordinator, chunk);
end

assert(strcmp(output.state, 'LOCKED'));
assert(strcmp(output.selectedProtocol, 'P25'));
assert(output.epochId == uint64(2));
assert(numel(output.closedEpochs) == 1);
closed = output.closedEpochs(1);
assert(closed.epochId == uint64(1));
assert(strcmp(closed.protocol, 'DMR'));
assert(strcmp(closed.closeReason, 'protocol_switch'));
assert(closed.endSample == uint64(400));
assert(isequal(closed.ambiguousInterval, uint64([400, 700])));
assert(output.currentEpoch.epochId == uint64(2));
assert(strcmp(output.currentEpoch.protocol, 'P25'));
assert(output.currentEpoch.candidateStartSample == uint64(400));
assert(any(strcmp({output.events.type}, 'PROTOCOL_SWITCH_CONFIRMED')));
end

function cfg = epochConfig()
cfg = radio.stream.defaultConfig();
cfg.chunkDurationSec = 0.1;
cfg.preTriggerSec = 0.1;
cfg.ringBufferSec = 3;
cfg.activity.initialNoiseFloorDb = -40;
cfg.activity.minOnSec = 0.05;
cfg.activity.offHangSec = 0.3;
end

function iq = twoBurstIq()
iq = [ones(500, 1); zeros(1000, 1); ones(500, 1)];
end
