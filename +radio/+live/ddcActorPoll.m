function [actor, events] = ddcActorPoll(actor, varargin)
%DDCACTORPOLL Collect ordered baseband and flush results without waiting.
p = inputParser;
p.addParameter('MaxEvents', inf);
p.parse(varargin{:});
events = cell(0, 1);
while actor.outputQueue.QueueLength > 0 && ...
        numel(events) < p.Results.MaxEvents
    message = poll(actor.outputQueue, 0);
    if isempty(message), break; end
    if ~isstruct(message) || ~isfield(message, 'type'), continue; end
    if isfield(message, 'actorId') && message.actorId ~= actor.actorId
        continue;
    end
    switch char(message.type)
        case 'ready'
            actor.inputQueue = message.inputQueue;
            actor.ready = true;
            for k = 1:numel(actor.pendingMessages)
                send(actor.inputQueue, actor.pendingMessages{k});
            end
            actor.pendingMessages = cell(0, 1);
        case 'reset'
            actor.resetPending = false;
            actor.ringAttached = false;
            actor.ringDrained = false;
            actor.pendingInputSamples = uint64(0);
            actor.processedInputSamples = uint64(0);
            events{end+1, 1} = message; %#ok<AGROW>
        case 'ring_attached'
            actor.ringAttached = true;
            actor.ringDrained = false;
            actor.ringReadSequence = uint64(message.readSequence);
            actor.ringWriteSequence = uint64(message.writeSequence);
            actor.ringSourceSampleEnd = uint64(message.sourceSampleEnd);
            actor.ringConsumedSampleEnd = ...
                uint64(message.consumedSampleEnd);
            actor = updateRingPending(actor);
            events{end+1, 1} = message; %#ok<AGROW>
        case 'ring_progress'
            actor.ringReadSequence = uint64(message.readSequence);
            actor.ringWriteSequence = uint64(message.writeSequence);
            actor.ringSourceSampleEnd = uint64(message.sourceSampleEnd);
            actor.ringConsumedSampleEnd = ...
                uint64(message.consumedSampleEnd);
            actor = updateRingPending(actor);
        case 'baseband'
            inputCount = uint64(message.inputSampleCount);
            actor.processedInputSamples = ...
                actor.processedInputSamples + inputCount;
            actor.pendingInputSamples = actor.pendingInputSamples - ...
                min(actor.pendingInputSamples, inputCount);
            actor.computeCount = actor.computeCount + uint64(1);
            actor.totalComputeSec = actor.totalComputeSec + ...
                double(message.computeSec);
            actor.maxComputeSec = max( ...
                actor.maxComputeSec, double(message.computeSec));
            if isfield(message, 'ringSequence')
                actor.ringReadSequence = uint64(message.ringSequence);
                actor.ringWriteSequence = ...
                    uint64(message.ringWriteSequence);
                actor.ringSourceSampleEnd = ...
                    uint64(message.ringSourceSampleEnd);
                actor.ringConsumedSampleEnd = ...
                    uint64(message.ringConsumedSampleEnd);
                actor = updateRingPending(actor);
            end
            events{end+1, 1} = message; %#ok<AGROW>
        case 'flushed'
            actor.flushed = true;
            actor.ringDrained = true;
            actor.ringAttached = false;
            actor.pendingInputSamples = uint64(0);
            events{end+1, 1} = message; %#ok<AGROW>
        case 'stopped'
            actor.stopped = true;
            events{end+1, 1} = message; %#ok<AGROW>
        case 'error'
            actor.failed = true;
            actor.errorReason = char(message.errorReason);
            events{end+1, 1} = message; %#ok<AGROW>
    end
end
if ~actor.stopped && ~actor.failed && ...
        strcmp(char(actor.future.State), 'finished')
    actor.failed = true;
    actor.errorReason = futureError(actor.future);
    events{end+1, 1} = struct('type', 'error', ...
        'actorId', actor.actorId, ...
        'errorReason', actor.errorReason);
end
end

function actor = updateRingPending(actor)
if actor.ringSourceSampleEnd >= actor.ringConsumedSampleEnd
    actor.pendingInputSamples = ...
        actor.ringSourceSampleEnd - actor.ringConsumedSampleEnd;
else
    actor.pendingInputSamples = uint64(0);
end
end

function reason = futureError(future)
reason = 'ddc_actor_stopped_unexpectedly';
try
    if ~isempty(future.Error)
        reason = sprintf('%s: %s', ...
            future.Error.identifier, future.Error.message);
    end
catch
end
end
