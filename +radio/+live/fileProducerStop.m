function actor = fileProducerStop(actor)
%FILEPRODUCERSTOP Request cooperative shutdown of a producer actor.
if isempty(actor), return; end
if ~actor.stopped && ~actor.failed && ~actor.terminal
    try
        actor = radio.live.fileProducerCommand(actor, 'stop');
    catch
    end
end
end
