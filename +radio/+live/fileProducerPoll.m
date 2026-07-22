function [actor, events] = fileProducerPoll(actor, varargin)
%FILEPRODUCERPOLL Collect producer state and lifecycle events.
p = inputParser;
p.addParameter('MaxEvents', inf);
p.parse(varargin{:});
events = cell(0, 1);
while actor.outputQueue.QueueLength > 0 && ...
        numel(events) < p.Results.MaxEvents
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
            for k = 1:numel(actor.pendingCommands)
                send(actor.inputQueue, actor.pendingCommands{k});
            end
            actor.pendingCommands = cell(0, 1);
        case 'progress'
            actor.productionLagSec = double(message.productionLagSec);
            actor.spectrumDroppedChunks = ...
                uint64(message.spectrumDroppedChunks);
            if ~isempty(events) && ...
                    strcmp(radio.getField(events{end}, 'type', ''), 'progress')
                events{end} = message;
            else
                events{end+1, 1} = message; %#ok<AGROW>
            end
        case 'terminal'
            actor.terminal = true;
            actor.productionLagSec = 0;
            actor.spectrumDroppedChunks = ...
                uint64(message.spectrumDroppedChunks);
            events{end+1, 1} = message; %#ok<AGROW>
        case 'stopped'
            actor.stopped = true;
            events{end+1, 1} = message; %#ok<AGROW>
        case 'error'
            actor.failed = true;
            actor.errorReason = char(message.errorReason);
            events{end+1, 1} = message; %#ok<AGROW>
    end
end
if ~actor.stopped && ~actor.terminal && ~actor.failed && ...
        strcmp(char(actor.future.State), 'finished')
    actor.failed = true;
    actor.errorReason = futureError(actor.future);
    events{end+1, 1} = struct('type', 'error', ...
        'actorId', actor.actorId, 'errorReason', actor.errorReason);
end
end

function reason = futureError(future)
reason = 'file_producer_stopped_unexpectedly';
try
    if ~isempty(future.Error)
        reason = sprintf('%s: %s', ...
            future.Error.identifier, future.Error.message);
    end
catch
end
end
