function actor = ddcActorStop(actor)
%DDCACTORSTOP Request cooperative shutdown of a live DDC actor.
if isempty(actor) || actor.stopped || actor.failed, return; end
message = struct('type', 'stop', 'actorId', actor.actorId);
try
    if actor.ready
        send(actor.inputQueue, message);
    else
        actor.pendingMessages{end+1, 1} = message;
    end
catch
end
end
