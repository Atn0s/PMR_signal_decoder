function actor = ddcActorRetarget(actor, frequencyOffsetsHz, centerHz)
%DDCACTORRETARGET Retune an idle prewarmed DDC actor before IQ attachment.
if isempty(actor) || actor.stopped || actor.failed || ~actor.ready
    error('radio:live:ddcActorRetarget:Unavailable', ...
        'The prewarmed DDC actor is not ready for retargeting.');
end
if actor.processedInputSamples ~= 0 || actor.pendingInputSamples ~= 0
    error('radio:live:ddcActorRetarget:Started', ...
        'A DDC actor cannot be retargeted after accepting IQ.');
end
message = struct( ...
    'type', 'retarget', ...
    'actorId', actor.actorId, ...
    'frequencyOffsetsHz', double(frequencyOffsetsHz(:)), ...
    'inputCenterFrequencyHz', double(centerHz));
send(actor.inputQueue, message);
actor.retargetPending = true;
actor.configured = false;
actor.flushed = false;
actor.flushRequested = false;
end
