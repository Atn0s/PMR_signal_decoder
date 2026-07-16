function actor = ddcActorFlush(actor)
%DDCACTORFLUSH Queue one ordered filter-tail flush after all input.
if actor.stopped || actor.failed || actor.flushRequested, return; end
actor.flushRequested = true;
message = struct('type', 'flush', 'actorId', actor.actorId, ...
    'requestId', actor.nextRequestId);
actor.nextRequestId = actor.nextRequestId + uint64(1);
if actor.ready
    send(actor.inputQueue, message);
else
    actor.pendingMessages{end+1, 1} = message;
end
end
