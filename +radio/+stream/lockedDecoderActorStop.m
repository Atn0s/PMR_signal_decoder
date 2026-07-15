function actor = lockedDecoderActorStop(actor)
%LOCKEDDECODERACTORSTOP Cooperatively stop a persistent decoder worker.
if actor.stopped, return; end
if actor.ready && ~isempty(actor.inputQueue)
    try
        send(actor.inputQueue, struct( ...
            'type', 'stop', 'actorId', actor.actorId));
    catch
        try, cancel(actor.future); catch, end
    end
else
    try, cancel(actor.future); catch, end
end
actor.stopped = true;
actor.requestInFlight = false;
actor.pendingInput = [];
end
