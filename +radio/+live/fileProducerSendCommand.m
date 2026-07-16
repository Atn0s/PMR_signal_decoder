function actor = fileProducerSendCommand(actor, message)
%FILEPRODUCERSENDCOMMAND Send or retain one producer control message.
if actor.stopped || actor.failed
    if isfield(message, 'type') && strcmp(char(message.type), 'stop')
        return;
    end
    error('radio:live:fileProducerSendCommand:Unavailable', ...
        'The file producer is no longer available.');
end
message.actorId = actor.actorId;
if actor.ready
    send(actor.inputQueue, message);
else
    actor.pendingCommands{end+1, 1} = message;
end
end
