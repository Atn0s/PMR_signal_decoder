function actor = spectrumActorSubmit(actor, transport)
%SPECTRUMACTORSUBMIT Submit one packed IQ chunk without blocking decoding.
if actor.stopped || actor.failed
    return;
end
message = struct('type', 'chunk', 'actorId', actor.actorId, ...
    'chunk', transport.chunk, 'payload', transport.payload);
if actor.needsDiscontinuity
    message.chunk.discontinuity = true;
    actor.needsDiscontinuity = false;
end
if actor.ready
    queueLength = actor.inputQueue.QueueLength;
    if queueLength >= actor.maxQueueChunks
        actor.droppedChunkCount = actor.droppedChunkCount + uint64(1);
        actor.needsDiscontinuity = true;
        return;
    end
    send(actor.inputQueue, message);
else
    actor.pendingMessages{end+1, 1} = message;
    if numel(actor.pendingMessages) > actor.maxQueueChunks
        actor.pendingMessages(1) = [];
        actor.droppedChunkCount = actor.droppedChunkCount + uint64(1);
        actor.pendingMessages{1}.chunk.discontinuity = true;
    end
end
actor.lastInputSampleEnd = uint64(transport.chunk.sourceSampleEnd);
end
