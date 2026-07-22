function runStreamingPhase9()
%RUNSTREAMINGPHASE9 Test independent offline RF Epoch reporting.
testShortSilenceStaysInEpoch();
testLongSilenceCreatesEpochs();
testNoSignalCreatesNoEpoch();
testSameTransmitterIsNotMerged();
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
