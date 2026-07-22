function runStreamingPhase8()
%RUNSTREAMINGPHASE8 Test the offline baseband protocol-race entry point.
testOfflineIdentificationContract();
testParallelModeGuards();
testRealNxdnScannerIntegration();
fprintf('Streaming phase-8 offline scanner integration tests passed.\n');
end

function testOfflineIdentificationContract()
cfg = radio.stream.defaultConfig();
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
report = radio.stream.identifyBasebandIq( ...
    complex(ones(1000, 1)), 1000, ...
    'Config', cfg, ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
assert(strcmp(report.outcome, 'confirmed'));
assert(strcmp(report.selectedProtocol, 'DMR'));
assert(strcmp(report.executionMode, 'parallel'));
assert(isequal(report.protocolNames, ...
    {'DMR', 'P25', 'dPMR', 'NXDN', 'TETRA'}));
assert(report.raceCount >= 1);
assert(report.classificationEndSample > report.classificationStartSample);
end

function testParallelModeGuards()
assertThrows(@() radio.scanFile('unused.rawiq', ...
    'ExecutionMode', 'parallel', ...
    'FreqList', [12500, 25000]), ...
    'radio:scanFile:KnownFrequencyMode');
assertThrows(@() radio.scanFile('unused.rawiq', ...
    'ExecutionMode', 'tuned-parallel', ...
    'FreqList', []), ...
    'radio:scanFile:TunedFrequencyList');
assertThrows(@() radio.scanFile('unused.rawiq', ...
    'ExecutionMode', 'not-a-mode'), ...
    'radio:scanFile:ExecutionMode');
end

function testRealNxdnScannerIntegration()
path = fullfile('signal_data', 'nxdn96_1_78125.rawiq');
if exist(path, 'file') ~= 2
    return;
end
[pdus, report] = radio.scanFile(path, ...
    'ExecutionMode', 'parallel', ...
    'FreqList', [], ...
    'NumWorkers', 5, ...
    'TimeoutSec', 180);
assert(strcmp(report.outcome, 'confirmed'));
assert(strcmp(report.selectedProtocol, 'NXDN'));
assert(strcmp(report.executionMode, 'parallel'));
assert(~isempty(pdus));
assert(all(strcmp({pdus.protocol}, 'NXDN')));
assert(report.pduCount == numel(pdus));
assert(report.epochCount >= 1);
assert(report.confirmedEpochCount == report.epochCount);
assert(isequal([report.epochs.epochId], ...
    uint64(1:report.epochCount)));
epochIds = arrayfun(@(item) item.extra.stream.epoch_id, pdus);
assert(all(ismember(epochIds, [report.epochs.epochId])));
assert(sum([report.epochs.pduCount]) == numel(pdus));
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
