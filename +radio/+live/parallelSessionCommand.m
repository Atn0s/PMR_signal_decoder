function session = parallelSessionCommand(session, command, varargin)
%PARALLELSESSIONCOMMAND Run, pause, or deterministically step the producer.
if isempty(session) || session.closed
    error('radio:live:parallelSessionCommand:Closed', ...
        'The parallel live session is closed.');
end
command = lower(char(command));
switch command
    case 'run'
        session.actors.producer = radio.live.fileProducerCommand( ...
            session.actors.producer, 'run');
        session.producerRunning = true;
        session.startedToken = tic;
    case 'pause'
        if session.producerRunning && ...
                ~session.actors.producer.terminal && ...
                ~session.actors.producer.failed
            session.actors.producer = radio.live.fileProducerCommand( ...
                session.actors.producer, 'pause');
        end
        session.producerRunning = false;
    case 'step'
        if isempty(varargin), count = 1; else, count = varargin{1}; end
        validateattributes(count, {'numeric'}, ...
            {'scalar','real','finite','integer','positive'});
        session.actors.producer = radio.live.fileProducerCommand( ...
            session.actors.producer, 'step', count);
        session.producerRunning = false;
    otherwise
        error('radio:live:parallelSessionCommand:Command', ...
            'Unsupported producer command: %s', command);
end
end
