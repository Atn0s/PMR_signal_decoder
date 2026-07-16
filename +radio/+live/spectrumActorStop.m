function actor = spectrumActorStop(actor)
%SPECTRUMACTORSTOP Request cooperative shutdown of the PSD consumer.
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
