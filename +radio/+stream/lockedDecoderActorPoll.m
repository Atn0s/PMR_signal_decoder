function [actor, event] = lockedDecoderActorPoll(actor)
%LOCKEDDECODERACTORPOLL Poll handshake/results without blocking acquisition.
event = emptyEvent();
while actor.outputQueue.QueueLength > 0
    message = poll(actor.outputQueue, 0);
    if isempty(message), break; end
    if ~isstruct(message) || ~isfield(message, 'type'), continue; end
    switch char(message.type)
        case 'ready'
            if message.actorId ~= actor.actorId, continue; end
            actor.inputQueue = message.inputQueue;
            actor.workerTaskId = message.workerTaskId;
            actor.ready = true;
            if actor.requestInFlight && ~actor.requestSent
                actor = sendPending(actor);
            end
        case 'result'
            if message.actorId ~= actor.actorId || ...
                    message.requestId ~= actor.requestId
                continue;
            end
            actor.requestInFlight = false;
            actor.requestSent = false;
            event.state = 'completed';
            event.completed = true;
            event.decoderState = message.decoderState;
            event.output = message.output;
            event.requestId = message.requestId;
        case 'error'
            if message.actorId ~= actor.actorId, continue; end
            actor.failed = true;
            actor.requestInFlight = false;
            actor.errorReason = char(message.errorReason);
            event.state = 'error';
            event.completed = true;
            event.errorReason = actor.errorReason;
        case 'stopped'
            if message.actorId ~= actor.actorId, continue; end
            actor.stopped = true;
            actor.requestInFlight = false;
            event.state = 'stopped';
            event.completed = true;
    end
end

if ~event.completed && strcmp(char(actor.future.State), 'finished') && ...
        ~actor.stopped
    actor.failed = true;
    actor.requestInFlight = false;
    actor.errorReason = futureError(actor.future);
    event.state = 'error';
    event.completed = true;
    event.errorReason = actor.errorReason;
end
end

function actor = sendPending(actor)
message = struct('type', 'decode', ...
    'actorId', actor.actorId, ...
    'requestId', actor.requestId, ...
    'input', actor.pendingInput);
try
    send(actor.inputQueue, message);
    actor.requestSent = true;
    actor.pendingInput = [];
catch ME
    actor.failed = true;
    actor.requestInFlight = false;
    actor.errorReason = sprintf('%s: %s', ME.identifier, ME.message);
end
end

function reason = futureError(future)
reason = 'persistent_decoder_worker_stopped_unexpectedly';
try
    if ~isempty(future.Error)
        reason = sprintf('%s: %s', ...
            future.Error.identifier, future.Error.message);
    end
catch
end
end

function event = emptyEvent()
event = struct('state', 'running', 'completed', false, ...
    'decoderState', [], 'output', [], 'requestId', uint64(0), ...
    'errorReason', '');
end
