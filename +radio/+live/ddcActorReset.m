function actor = ddcActorReset(actor)
%DDCACTORRESET Detach live input while preserving the prewarmed worker.
if isempty(actor) || actor.stopped || actor.failed, return; end
message = struct('type', 'reset', 'actorId', actor.actorId);
if actor.ready
    send(actor.inputQueue, message);
else
    actor.pendingMessages{end+1, 1} = message;
end
actor.resetPending = true;
actor.flushed = false;
actor.ringAttached = false;
actor.ringDrained = false;
actor.ringReadSequence = uint64(0);
actor.ringWriteSequence = uint64(0);
actor.ringSourceSampleEnd = uint64(0);
actor.ringConsumedSampleEnd = uint64(0);
actor.pendingInputSamples = uint64(0);
actor.processedInputSamples = uint64(0);
actor.computeCount = uint64(0);
actor.totalComputeSec = 0;
actor.maxComputeSec = 0;
end
