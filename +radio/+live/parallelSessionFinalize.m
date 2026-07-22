function [session, update] = parallelSessionFinalize(session)
%PARALLELSESSIONFINALIZE Flush scanners and release a terminal live source.
update = struct('messages', {cell(0, 1)}, ...
    'spectrum', [], 'newPdus', struct([]), 'completed', true);
if isempty(session) || strcmp(session.mode, 'COMPLETED')
    return;
end
session.mode = 'FINALIZING';
if ~isempty(session.decode.scanner) && ...
        ~session.decode.scanner.finalized
    previousCount = numel(session.pdus);
    [session.decode.scanner, ~] = ...
        radio.tuned.multiStreamScannerFinalize( ...
            session.decode.scanner, 'FlushDdc', false);
    session.pdus = session.decode.scanner.pdus;
    if numel(session.pdus) > previousCount
        update.newPdus = session.pdus(previousCount+1:end);
    end
end
if ~isempty(session.actors.ddc)
    session.actors.ddc = ...
        radio.live.ddcActorStop(session.actors.ddc);
end
if ~isempty(session.actors.producer)
    session.actors.producer = ...
        radio.live.fileProducerStop(session.actors.producer);
end
if ~isempty(session.actors.spectrum)
    session.actors.spectrum = ...
        radio.live.spectrumActorStop(session.actors.spectrum);
end
if ~isempty(session.ring)
    radio.live.sharedIqRingDelete(session.ring);
    session.ring = [];
end
session.producerRunning = false;
session.closed = true;
session.mode = 'COMPLETED';
update.messages{end+1, 1} = 'Configured replay completed.';
end
