function [coordinator, output] = raceCoordinatorFeed(coordinator, chunk)
%RACECOORDINATORFEED Advance known-frequency identification without IQ loss.
coordinator.lastDecoderOutput = [];
coordinator.closedEpochs = coordinator.closedEpochs([]);
[coordinator.channelController, channelOutput] = ...
    radio.stream.channelControllerFeed(coordinator.channelController, chunk);
events = emptyEvents();

if channelOutput.bufferEvent.reset
    [coordinator, events] = cancelActive(coordinator, events, ...
        chunk.sourceSampleStart, 'input_discontinuity');
end

channelState = coordinator.channelController.state;
if strcmp(channelState, 'NO_SIGNAL')
    [coordinator, events] = cancelActive(coordinator, events, ...
        chunk.sourceSampleEnd, 'signal_ended');
    if ~strcmp(coordinator.state, 'NO_SIGNAL')
        events(end+1) = makeEvent('COORDINATOR_STATE', coordinator.state, ...
            'NO_SIGNAL', chunk.sourceSampleEnd, '', 'signal_ended'); %#ok<AGROW>
    end
    coordinator = appendClosedEpoch( ...
        coordinator, coordinator.channelController.lastClosedEpoch);
    coordinator = clearEpoch(coordinator);
    output = makeOutput(coordinator, channelOutput, events, [], []);
    return;
end

if strcmp(channelState, 'ACTIVITY_PENDING')
    if strcmp(coordinator.state, 'NO_SIGNAL')
        events(end+1) = makeEvent('COORDINATOR_STATE', 'NO_SIGNAL', ...
            'ACTIVITY_PENDING', chunk.sourceSampleEnd, '', ...
            'activity_pending'); %#ok<AGROW>
        coordinator.state = 'ACTIVITY_PENDING';
    end
    output = makeOutput(coordinator, channelOutput, events, [], []);
    return;
end

epoch = coordinator.channelController.currentEpoch;
if isempty(epoch)
    error('radio:stream:raceCoordinatorFeed:Epoch', ...
        'CLASSIFYING channel state does not have an active epoch.');
end
if coordinator.currentEpochId ~= epoch.epochId || ...
        coordinator.currentGeneration ~= epoch.generation
    [coordinator, events] = cancelActive(coordinator, events, ...
        chunk.sourceSampleStart, 'new_epoch');
    oldState = coordinator.state;
    coordinator.state = 'CLASSIFYING';
    coordinator.currentEpochId = epoch.epochId;
    coordinator.currentGeneration = epoch.generation;
    coordinator.probeStates = [];
    coordinator.selectedProtocol = '';
    coordinator.lastRace = [];
    coordinator.lastCatchup = [];
    coordinator.decoderState = [];
    coordinator.reclassificationStartSample = uint64(0);
    coordinator.catchupPassCount = 0;
    events(end+1) = makeEvent('COORDINATOR_STATE', oldState, ...
        'CLASSIFYING', chunk.sourceSampleEnd, '', 'epoch_started'); %#ok<AGROW>
end

raceStatus = [];
catchupStatus = [];
if ~isempty(coordinator.activeRace)
    [coordinator.activeRace, raceStatus] = ...
        radio.stream.parallelProbeRacePoll(coordinator.activeRace);
    if coordinator.activeRace.completed
        [coordinator, events] = finishRace( ...
            coordinator, events, raceStatus, chunk.sourceSampleEnd);
    end
end

if any(strcmp(coordinator.state, {'CLASSIFYING', 'RECLASSIFYING'})) && ...
        isempty(coordinator.activeRace)
    buffer = coordinator.channelController.ringBuffer;
    snapshotStart = max(buffer.startSample, epoch.candidateStartSample);
    if snapshotStart < buffer.endSample
        snapshot = radio.stream.ringBufferRange( ...
            buffer, snapshotStart, buffer.endSample);
        coordinator.activeRace = radio.stream.parallelProbeRaceStart( ...
            snapshot, coordinator.probeStates, ...
            'EpochId', epoch.epochId, ...
            'Generation', epoch.generation, ...
            'Registry', coordinator.registry, ...
            'Mode', coordinator.options.mode, ...
            'NumWorkers', coordinator.options.numWorkers, ...
            'PoolType', coordinator.options.poolType, ...
            'TaskFcn', coordinator.options.taskFcn, ...
            'TaskContext', coordinator.options.taskContext);
        if coordinator.activeRace.completed
            raceStatus = coordinator.activeRace.race;
            [coordinator, events] = finishRace( ...
                coordinator, events, raceStatus, chunk.sourceSampleEnd);
        end
    end
end

if strcmp(coordinator.state, 'CATCHING_UP') && ...
        ~isempty(coordinator.activeCatchup)
    [coordinator.activeCatchup, catchupStatus] = ...
        radio.stream.winnerCatchupPoll(coordinator.activeCatchup);
    if coordinator.activeCatchup.completed
        [coordinator, events] = finishCatchup( ...
            coordinator, events, catchupStatus, chunk.sourceSampleEnd);
    end
end

if any(strcmp(coordinator.state, {'LOCKED', 'LOSS_PENDING'})) && ...
        ~isempty(coordinator.decoderState) && ...
        chunk.sourceSampleEnd > coordinator.decoderState.lastProcessedEndSample
    [coordinator.decoderState, coordinator.lastDecoderOutput] = ...
        radio.stream.lockedDecoderProcess( ...
            coordinator.decoderState, coordinator.channelController.ringBuffer);
    [coordinator, events] = applyDecoderHealth( ...
        coordinator, events, chunk.sourceSampleEnd);
end

output = makeOutput( ...
    coordinator, channelOutput, events, raceStatus, catchupStatus);
end

function [coordinator, events] = finishRace( ...
        coordinator, events, race, eventSample)
coordinator.probeStates = coordinator.activeRace.states;
coordinator.lastRace = race;
coordinator.activeRace = [];
oldState = coordinator.state;
switch race.outcome
    case 'confirmed'
        winner = race.winner;
        coordinator.selectedProtocol = winner.protocol;
        isProtocolSwitch = strcmp(oldState, 'RECLASSIFYING') && ...
            ~isempty(coordinator.previousProtocol) && ...
            ~strcmp(coordinator.previousProtocol, coordinator.selectedProtocol);
        if isProtocolSwitch
            coordinator = rolloverProtocolEpoch( ...
                coordinator, eventSample, winner);
        else
            coordinator = updateEpochFromWinner( ...
                coordinator, eventSample, winner, 'CATCHING_UP');
        end
        coordinator.state = 'CATCHING_UP';
        eventType = 'PROTOCOL_CONFIRMED';
        if isProtocolSwitch
            eventType = 'PROTOCOL_SWITCH_CONFIRMED';
        end
        events(end+1) = makeEvent(eventType, oldState, ...
            'CATCHING_UP', eventSample, coordinator.selectedProtocol, ...
            race.winner.evidenceClass); %#ok<AGROW>
        coordinator = startCatchup(coordinator);
        if coordinator.activeCatchup.completed
            [coordinator.activeCatchup, status] = ...
                radio.stream.winnerCatchupPoll(coordinator.activeCatchup);
            [coordinator, events] = finishCatchup( ...
                coordinator, events, status, eventSample);
        end
    case 'ambiguous'
        coordinator.state = 'AMBIGUOUS';
        coordinator = setEpochOutcome( ...
            coordinator, 'AMBIGUOUS', 'ambiguous');
        events(end+1) = makeEvent('PROTOCOL_AMBIGUOUS', oldState, ...
            'AMBIGUOUS', eventSample, '', ...
            strjoin(race.confirmedProtocols, ',')); %#ok<AGROW>
    case 'rejected_all'
        coordinator.state = 'UNKNOWN';
        coordinator = setEpochOutcome( ...
            coordinator, 'UNKNOWN', 'unclassified');
        events(end+1) = makeEvent('PROTOCOL_UNKNOWN', oldState, ...
            'UNKNOWN', eventSample, '', 'all_probes_rejected'); %#ok<AGROW>
    case 'error'
        coordinator.state = 'ERROR';
        coordinator = setEpochOutcome(coordinator, 'ERROR', 'error');
        events(end+1) = makeEvent('PROBE_ERROR', oldState, ...
            'ERROR', eventSample, '', 'all_remaining_probes_failed'); %#ok<AGROW>
end
end

function coordinator = startCatchup(coordinator)
epoch = coordinator.channelController.currentEpoch;
coordinator.catchupPassCount = coordinator.catchupPassCount + 1;
coordinator.activeCatchup = radio.stream.winnerCatchupStart( ...
    coordinator.channelController.ringBuffer, epoch, ...
    coordinator.selectedProtocol, ...
    'Mode', coordinator.options.mode, ...
    'NumWorkers', coordinator.options.numWorkers, ...
    'PoolType', coordinator.options.poolType, ...
    'PreTriggerSec', coordinator.options.preTriggerSec);
end

function [coordinator, events] = finishCatchup( ...
        coordinator, events, status, eventSample)
coordinator.activeCatchup = [];
if ~strcmp(status.state, 'completed') || isempty(status.result)
    coordinator.state = 'CATCHUP_ERROR';
    events(end+1) = makeEvent('CATCHUP_ERROR', 'CATCHING_UP', ...
        'CATCHUP_ERROR', eventSample, coordinator.selectedProtocol, ...
        status.errorReason); %#ok<AGROW>
    return;
end
coordinator.lastCatchup = status.result;
buffer = coordinator.channelController.ringBuffer;
if status.result.catchupEndSample < buffer.endSample
    coordinator = startCatchup(coordinator);
    events(end+1) = makeEvent('CATCHUP_RETRY', 'CATCHING_UP', ...
        'CATCHING_UP', eventSample, coordinator.selectedProtocol, ...
        'live_edge_advanced_during_decode'); %#ok<AGROW>
else
    coordinator.state = 'LOCKED';
    epoch = coordinator.channelController.currentEpoch;
    coordinator.decoderState = radio.stream.lockedDecoderInit( ...
        coordinator.selectedProtocol, epoch, buffer.sampleRateHz, ...
        'InitialPdus', status.result.pdus, ...
        'LastProcessedEndSample', status.result.catchupEndSample, ...
        'DecodeFcn', coordinator.options.lockedDecodeFcn, ...
        'SuspectWindows', coordinator.options.lockedSuspectWindows, ...
        'LostWindows', coordinator.options.lockedLostWindows);
    coordinator.channelController.currentEpoch.decodeStartSample = ...
        status.result.catchupStartSample;
    coordinator.channelController.currentEpoch.lastGoodSample = ...
        status.result.catchupEndSample;
    coordinator.channelController.currentEpoch.state = 'LOCKED';
    coordinator.channelController.currentEpoch.status = 'locked';
    coordinator.channelController.currentEpoch.pduCount = ...
        status.result.pduCount;
    events(end+1) = makeEvent('CATCHUP_COMPLETE', 'CATCHING_UP', ...
        'LOCKED', eventSample, coordinator.selectedProtocol, ...
        'caught_up_to_live_edge'); %#ok<AGROW>
    coordinator.previousProtocol = '';
end
end

function [coordinator, events] = cancelActive( ...
        coordinator, events, eventSample, reason)
if ~isempty(coordinator.activeRace)
    [coordinator.activeRace, ~] = ...
        radio.stream.parallelProbeRaceCancel( ...
            coordinator.activeRace, 'Reason', reason);
    coordinator.activeRace = [];
    events(end+1) = makeEvent('RACE_CANCELED', coordinator.state, ...
        coordinator.state, eventSample, '', reason); %#ok<AGROW>
end
if ~isempty(coordinator.activeCatchup)
    [coordinator.activeCatchup, ~] = ...
        radio.stream.winnerCatchupCancel(coordinator.activeCatchup);
    coordinator.activeCatchup = [];
    events(end+1) = makeEvent('CATCHUP_CANCELED', coordinator.state, ...
        coordinator.state, eventSample, coordinator.selectedProtocol, reason); %#ok<AGROW>
end
end

function coordinator = clearEpoch(coordinator)
coordinator.state = 'NO_SIGNAL';
coordinator.probeStates = [];
coordinator.activeRace = [];
coordinator.activeCatchup = [];
coordinator.selectedProtocol = '';
coordinator.previousProtocol = '';
coordinator.decoderState = [];
coordinator.lastDecoderOutput = [];
coordinator.currentEpochId = uint64(0);
coordinator.currentGeneration = uint64(0);
coordinator.reclassificationStartSample = uint64(0);
coordinator.catchupPassCount = 0;
end

function [coordinator, events] = applyDecoderHealth( ...
        coordinator, events, eventSample)
health = coordinator.lastDecoderOutput.status;
coordinator = updateEpochHealth(coordinator, health, eventSample);
if strcmp(health, 'healthy')
    if strcmp(coordinator.state, 'LOSS_PENDING')
        events(end+1) = makeEvent('DECODER_RECOVERED', 'LOSS_PENDING', ...
            'LOCKED', eventSample, coordinator.selectedProtocol, ...
            'strong_evidence_recovered'); %#ok<AGROW>
        coordinator.state = 'LOCKED';
        coordinator.channelController.currentEpoch.state = 'LOCKED';
        coordinator.channelController.currentEpoch.status = 'locked';
    end
    return;
end
if strcmp(health, 'suspect') && strcmp(coordinator.state, 'LOCKED')
    events(end+1) = makeEvent('DECODER_SUSPECT', 'LOCKED', ...
        'LOSS_PENDING', eventSample, coordinator.selectedProtocol, ...
        'consecutive_windows_without_strong_evidence'); %#ok<AGROW>
    coordinator.state = 'LOSS_PENDING';
    coordinator.channelController.currentEpoch.state = 'LOSS_PENDING';
    coordinator.channelController.currentEpoch.status = 'loss_pending';
    return;
end
if any(strcmp(health, {'lost', 'error'}))
    oldState = coordinator.state;
    lastStrong = coordinator.decoderState.lastStrongEvidenceSample;
    if lastStrong == 0
        lastStrong = uint64(eventSample);
    end
    coordinator.reclassificationStartSample = lastStrong;
    coordinator.previousProtocol = coordinator.selectedProtocol;
    coordinator.selectedProtocol = '';
    coordinator.state = 'RECLASSIFYING';
    coordinator.decoderState = [];
    coordinator.probeStates = [];
    coordinator.lastRace = [];
    coordinator.currentGeneration = coordinator.currentGeneration + uint64(1);
    coordinator.channelController.generation = ...
        coordinator.currentGeneration;
    coordinator.channelController.currentEpoch.generation = ...
        coordinator.currentGeneration;
    coordinator.channelController.currentEpoch.state = 'RECLASSIFYING';
    coordinator.channelController.currentEpoch.status = 'reclassifying';
    coordinator.channelController.currentEpoch.ambiguousInterval = ...
        uint64([lastStrong, 0]);
    events(end+1) = makeEvent('DECODER_LOST', oldState, ...
        'RECLASSIFYING', eventSample, coordinator.previousProtocol, health); %#ok<AGROW>
end
end

function output = makeOutput(coordinator, channel, events, race, catchup)
output = struct( ...
    'state', coordinator.state, ...
    'selectedProtocol', coordinator.selectedProtocol, ...
    'epochId', coordinator.currentEpochId, ...
    'generation', coordinator.currentGeneration, ...
    'channel', channel, ...
    'race', race, ...
    'catchup', catchup, ...
    'events', events, ...
    'lastRace', coordinator.lastRace, ...
    'lastCatchup', coordinator.lastCatchup, ...
    'decoder', coordinator.lastDecoderOutput, ...
    'currentEpoch', coordinator.channelController.currentEpoch, ...
    'closedEpochs', coordinator.closedEpochs);
end

function coordinator = updateEpochFromWinner( ...
        coordinator, eventSample, winner, state)
if isempty(coordinator.channelController.currentEpoch)
    return;
end
epoch = coordinator.channelController.currentEpoch;
epoch.protocol = winner.protocol;
epoch.outcome = 'confirmed';
epoch.confidence = radio.getField(winner, 'confidence', 0);
epoch.frequencyOffsetHz = radio.getField(winner, 'frequencyOffsetHz', 0);
if epoch.lockSample == 0
    epoch.lockSample = uint64(eventSample);
end
epoch.lastGoodSample = uint64(eventSample);
epoch.state = state;
epoch.status = lower(state);
epoch.classificationEndSample = uint64(eventSample);
coordinator.channelController.currentEpoch = epoch;
end

function coordinator = rolloverProtocolEpoch(coordinator, eventSample, winner)
boundary = coordinator.reclassificationStartSample;
if boundary == 0
    boundary = uint64(eventSample);
end
oldEpoch = coordinator.channelController.currentEpoch;
boundary = max(boundary, oldEpoch.candidateStartSample);
oldEpoch.ambiguousInterval = uint64([boundary, uint64(eventSample)]);
coordinator.channelController.currentEpoch = oldEpoch;
[coordinator.channelController, closed] = ...
    radio.stream.channelControllerCloseEpoch( ...
        coordinator.channelController, boundary, 'protocol_switch');
closed.ambiguousInterval = uint64([boundary, uint64(eventSample)]);
coordinator.channelController.lastClosedEpoch = closed;
coordinator = appendClosedEpoch(coordinator, closed);

epochId = coordinator.channelController.nextEpochId;
coordinator.channelController.nextEpochId = epochId + uint64(1);
newGeneration = coordinator.channelController.generation;
nextEpoch = radio.stream.newEpoch( ...
    coordinator.channelController.channelId, epochId, ...
    newGeneration, boundary);
nextEpoch.ambiguousInterval = uint64([boundary, uint64(eventSample)]);
coordinator.channelController.currentEpoch = nextEpoch;
coordinator.channelController.state = 'CLASSIFYING';
coordinator.currentEpochId = epochId;
coordinator.currentGeneration = newGeneration;
coordinator.probeStates = [];
coordinator.reclassificationStartSample = uint64(0);
coordinator = updateEpochFromWinner( ...
    coordinator, eventSample, winner, 'CATCHING_UP');
end

function coordinator = appendClosedEpoch(coordinator, epoch)
if isempty(epoch)
    return;
end
if coordinator.lastReportedClosedEpochId == epoch.epochId || ...
        (~isempty(coordinator.closedEpochs) && ...
        any([coordinator.closedEpochs.epochId] == epoch.epochId))
    return;
end
coordinator.closedEpochs(end+1, 1) = epoch;
coordinator.lastReportedClosedEpochId = epoch.epochId;
end

function coordinator = updateEpochHealth(coordinator, health, eventSample)
if isempty(coordinator.channelController.currentEpoch)
    return;
end
epoch = coordinator.channelController.currentEpoch;
epoch.consecutiveInvalidFrames = ...
    coordinator.lastDecoderOutput.consecutiveNoEvidence;
frequencyOffsetHz = coordinator.lastDecoderOutput.frequencyOffsetHz;
if isnumeric(frequencyOffsetHz) && isscalar(frequencyOffsetHz) && ...
        isfinite(frequencyOffsetHz)
    epoch.frequencyOffsetHz = frequencyOffsetHz;
end
if strcmp(health, 'healthy')
    epoch.lastGoodSample = uint64(eventSample);
end
coordinator.channelController.currentEpoch = epoch;
end

function coordinator = setEpochOutcome(coordinator, state, outcome)
if isempty(coordinator.channelController.currentEpoch)
    return;
end
coordinator.channelController.currentEpoch.state = state;
coordinator.channelController.currentEpoch.status = lower(state);
coordinator.channelController.currentEpoch.outcome = outcome;
end

function event = makeEvent(type, fromState, toState, sample, protocol, reason)
event = struct( ...
    'type', type, ...
    'fromState', fromState, ...
    'toState', toState, ...
    'sample', uint64(sample), ...
    'protocol', protocol, ...
    'reason', reason);
end

function events = emptyEvents()
events = struct('type', {}, 'fromState', {}, 'toState', {}, ...
    'sample', {}, 'protocol', {}, 'reason', {});
end
