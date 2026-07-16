function [actor, snapshot] = spectrumActorPoll(actor)
%SPECTRUMACTORPOLL Return only the newest completed PSD snapshot.
snapshot = [];
while actor.outputQueue.QueueLength > 0
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
        case 'snapshot'
            snapshot = message.snapshot;
            actor.lastSnapshotSampleEnd = ...
                uint64(message.sourceSampleEnd);
        case 'stopped'
            actor.stopped = true;
        case 'error'
            actor.failed = true;
            actor.errorReason = char(message.errorReason);
    end
end
if ~actor.stopped && ~actor.failed && ...
        strcmp(char(actor.future.State), 'finished')
    actor.failed = true;
    actor.errorReason = 'spectrum_actor_stopped_unexpectedly';
    try
        if ~isempty(actor.future.Error)
            actor.errorReason = sprintf('%s: %s', ...
                actor.future.Error.identifier, actor.future.Error.message);
        end
    catch
    end
end
end
