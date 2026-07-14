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
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context);
assert(strcmp(report.outcome, 'confirmed'));
assert(strcmp(report.selectedProtocol, 'DMR'));
assert(strcmp(report.executionMode, 'serial'));
assert(isequal(report.protocolNames, ...
    {'DMR', 'P25', 'dPMR', 'NXDN', 'TETRA'}));
assert(report.raceCount >= 1);
assert(report.classificationEndSample > report.classificationStartSample);
end

function testParallelModeGuards()
assertThrows(@() radio.scanFile('unused.rawiq', ...
    'ExecutionMode', 'parallel', 'BlindSearch', true), ...
    'radio:scanFile:ParallelBlindSearch');
assertThrows(@() radio.scanFile('unused.rawiq', ...
    'ExecutionMode', 'parallel', 'BlindSearch', false, 'FreqList', 12500), ...
    'radio:scanFile:ParallelFrequencyList');
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
    'BlindSearch', false, ...
    'FreqList', [], ...
    'ParallelMode', 'parallel', ...
    'ParallelNumWorkers', 5, ...
    'ParallelPoolType', 'processes', ...
    'ParallelTimeoutSec', 180);
assert(strcmp(report.outcome, 'confirmed'));
assert(strcmp(report.selectedProtocol, 'NXDN'));
assert(any(strcmp(report.executionMode, {'parallel', 'serial_fallback'})));
assert(~isempty(pdus));
assert(all(strcmp({pdus.protocol}, 'NXDN')));
assert(report.pduCount == numel(pdus));
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
