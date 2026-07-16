function [deferMask, report] = multiStreamLockedDecodeDeferrals(scanner)
%MULTISTREAMLOCKEDDECODEDEFERRALS Admit bounded new actor launches per feed.
channelCount = scanner.channelCount;
deferMask = false(channelCount, 1);
priorityStates = {'ACTIVITY_PENDING', 'CLASSIFYING', 'RECLASSIFYING', ...
    'CATCHING_UP'};
states = cell(channelCount, 1);
for k = 1:channelCount
    states{k} = scanner.channels{k}.coordinator.state;
end
if any(ismember(states, priorityStates))
    deferMask(:) = true;
    report = struct('reason', 'classification_priority', ...
        'candidateIndices', zeros(0, 1), ...
        'admittedIndices', zeros(0, 1), ...
        'deferMask', deferMask);
    return;
end

limit = radio.getField(scanner, 'maxPersistentActorStartsPerFeed', 1);
candidates = zeros(0, 1);
for k = 1:channelCount
    coordinator = scanner.channels{k}.coordinator;
    if ~any(strcmp(coordinator.state, {'LOCKED', 'LOSS_PENDING'})) || ...
            ~isempty(coordinator.activeDecode) || ...
            isempty(coordinator.decoderState)
        continue;
    end
    mode = lower(char(coordinator.options.mode));
    poolType = lower(char(coordinator.options.poolType));
    if strcmp(mode, 'serial') || strcmp(poolType, 'threads') || ...
            ~radio.stream.lockedDecoderActorEligible( ...
                coordinator.decoderState) || ...
            ~isempty(coordinator.decoderState.actor)
        continue;
    end
    if radio.stream.lockedDecoderReady(coordinator.decoderState, ...
            coordinator.channelController.ringBuffer)
        candidates(end+1, 1) = k; %#ok<AGROW>
    end
end

admittedCount = min(numel(candidates), max(0, floor(limit)));
nextAllowedFeed = radio.getField( ...
    scanner, 'nextPersistentActorStartFeed', uint64(0));
if scanner.feedCount < nextAllowedFeed
    admittedCount = 0;
end
admitted = candidates(1:admittedCount);
deferred = setdiff(candidates, admitted, 'stable');
deferMask(deferred) = true;
reason = 'bounded_actor_launch';
if ~isempty(candidates) && admittedCount == 0 && ...
        scanner.feedCount < nextAllowedFeed
    reason = 'actor_launch_cooldown';
end
report = struct('reason', reason, ...
    'candidateIndices', candidates, ...
    'admittedIndices', admitted, ...
    'deferMask', deferMask);
end
