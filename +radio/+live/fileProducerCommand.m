function actor = fileProducerCommand(actor, command, varargin)
%FILEPRODUCERCOMMAND Queue run, pause, step, or stop for a producer actor.
kind = lower(char(command));
if ~any(strcmp(kind, {'run', 'pause', 'step', 'stop'}))
    error('radio:live:fileProducerCommand:Command', ...
        'Unsupported producer command: %s', kind);
end
message = struct('type', kind, 'actorId', actor.actorId, ...
    'count', uint64(0));
if strcmp(kind, 'step')
    if isempty(varargin), count = 1; else, count = varargin{1}; end
    validateattributes(count, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'integer', 'positive'});
    message.count = uint64(count);
end
actor = radio.live.fileProducerSendCommand(actor, message);
end
