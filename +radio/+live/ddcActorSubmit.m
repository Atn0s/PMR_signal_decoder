function actor = ddcActorSubmit(actor, transport)
%DDCACTORSUBMIT Queue one packed wideband chunk in source order.
if actor.stopped || actor.failed || actor.flushRequested
    error('radio:live:ddcActorSubmit:Unavailable', ...
        'The DDC actor is stopped, failed, or already flushing.');
end
sampleCount = uint64(transport.payload.sampleCount);
newPending = actor.pendingInputSamples + sampleCount;
if double(newPending) / actor.inputSampleRateHz > actor.maxQueueSec
    error('radio:live:ddcActorSubmit:QueueOverrun', ...
        ['DDC input exceeded %.3f s; decode must stop instead of ', ...
         'silently dropping IQ.'], actor.maxQueueSec);
end
message = struct( ...
    'type', 'chunk', ...
    'actorId', actor.actorId, ...
    'requestId', actor.nextRequestId, ...
    'chunk', transport.chunk, ...
    'payload', transport.payload);
actor.nextRequestId = actor.nextRequestId + uint64(1);
actor.pendingInputSamples = newPending;
actor.maxPendingInputSamples = max( ...
    actor.maxPendingInputSamples, newPending);
actor = sendOrQueue(actor, message);
end

function actor = sendOrQueue(actor, message)
if actor.ready
    send(actor.inputQueue, message);
else
    actor.pendingMessages{end+1, 1} = message;
end
end
