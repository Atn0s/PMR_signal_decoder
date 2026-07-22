function actor = ddcActorStop(actor)
%DDCACTORSTOP Stop a live DDC actor and release its process worker.
if isempty(actor) || actor.stopped || actor.failed, return; end
message = struct('type', 'stop', 'actorId', actor.actorId);
if actor.ready
    send(actor.inputQueue, message);
else
    actor.pendingMessages{end+1, 1} = message;
end
token = tic;
while ~actor.stopped && ~actor.failed && toc(token) < 5
    [actor, ~] = radio.live.ddcActorPoll(actor, 'MaxEvents', inf);
    if ~actor.stopped && ~actor.failed, pause(0.001); end
end
if ~actor.stopped && ~actor.failed
    error('radio:live:ddcActorStop:Timeout', ...
        'The DDC actor did not stop within five seconds.');
end
end
