function runStreamingPhase7()
%RUNSTREAMINGPHASE7 Test health hysteresis and reclassification generation.
testHealthRecovery();
testHealthLossReclassifies();
fprintf('Streaming phase-7 health transition tests passed.\n');
end

function testHealthRecovery()
coordinator = makeCoordinator(@tests.fakeHealthRecoveryDecoder, 2, 4);
[coordinator, nextStart] = lockCoordinator(coordinator);
[coordinator, ~] = feedSignal(coordinator, nextStart);      % healthy at 400
[coordinator, ~] = feedSignal(coordinator, nextStart+100);  % miss 1 at 500
[coordinator, output] = feedSignal(coordinator, nextStart+200); % suspect at 600
assert(strcmp(output.state, 'LOSS_PENDING'));
assert(any(strcmp({output.events.type}, 'DECODER_SUSPECT')));
[coordinator, output] = feedSignal(coordinator, nextStart+300); %#ok<ASGLU>
assert(strcmp(output.state, 'LOCKED'));
assert(any(strcmp({output.events.type}, 'DECODER_RECOVERED')));
end

function testHealthLossReclassifies()
coordinator = makeCoordinator(@tests.fakeHealthLossDecoder, 2, 3);
[coordinator, nextStart] = lockCoordinator(coordinator);
initialGeneration = coordinator.currentGeneration;
[coordinator, ~] = feedSignal(coordinator, nextStart);       % healthy at 400
[coordinator, ~] = feedSignal(coordinator, nextStart+100);   % miss 1
[coordinator, output] = feedSignal(coordinator, nextStart+200); % suspect
assert(strcmp(output.state, 'LOSS_PENDING'));
[coordinator, output] = feedSignal(coordinator, nextStart+300); %#ok<ASGLU>
assert(strcmp(output.state, 'RECLASSIFYING'));
assert(coordinator.currentGeneration == initialGeneration + uint64(1));
assert(strcmp(coordinator.previousProtocol, 'DMR'));
assert(isempty(coordinator.selectedProtocol));
assert(isempty(coordinator.decoderState));
assert(any(strcmp({output.events.type}, 'DECODER_LOST')));
end

function coordinator = makeCoordinator(decodeFcn, suspectWindows, lostWindows)
cfg = radio.stream.defaultConfig();
cfg.ringBufferSec = 2;
cfg.preTriggerSec = 0.1;
cfg.lockedSuspectWindows = suspectWindows;
cfg.lockedLostWindows = lostWindows;
cfg.activity.initialNoiseFloorDb = -40;
cfg.activity.minOnSec = 0.05;
cfg.activity.offHangSec = 0.2;
context = struct('StatusByProtocol', struct('DMR', 'confirmed'));
coordinator = radio.stream.raceCoordinatorInit(1000, ...
    'Config', cfg, ...
    'Mode', 'serial', ...
    'TaskFcn', @tests.fakeParallelProbeTask, ...
    'TaskContext', context, ...
    'LockedDecodeFcn', decodeFcn);
end

function [coordinator, nextStart] = lockCoordinator(coordinator)
for startSample = 0:100:200
    [coordinator, output] = feedSignal(coordinator, startSample);
end
assert(strcmp(output.state, 'LOCKED'));
nextStart = 300;
end

function [coordinator, output] = feedSignal(coordinator, startSample)
chunk = radio.stream.makeIqChunk( ...
    complex(ones(100, 1)), 1000, startSample, ...
    'SequenceNumber', startSample / 100);
[coordinator, output] = radio.stream.raceCoordinatorFeed(coordinator, chunk);
end
