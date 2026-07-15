function actor = lockedDecoderActorSubmit(actor, input)
%LOCKEDDECODERACTORSUBMIT Submit one ordered chunk to a persistent actor.
if actor.stopped || actor.failed
    error('radio:stream:lockedDecoderActorSubmit:Unavailable', ...
        'The persistent decoder actor is not available.');
end
if actor.requestInFlight
    error('radio:stream:lockedDecoderActorSubmit:Busy', ...
        'Only one decoder request may be in flight per actor.');
end
actor.requestId = actor.requestId + uint64(1);
actor.requestInFlight = true;
actor.requestSent = false;
[actor.pendingInput, payload] = ...
    radio.stream.lockedDecoderActorPackInput(input);
actor.pendingInput.actorIq = payload;
if actor.ready
    actor = sendPending(actor);
end
end

function actor = sendPending(actor)
message = struct('type', 'decode', ...
    'actorId', actor.actorId, ...
    'requestId', actor.requestId, ...
    'input', actor.pendingInput);
send(actor.inputQueue, message);
actor.requestSent = true;
actor.pendingInput = [];
end
