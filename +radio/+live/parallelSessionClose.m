function session = parallelSessionClose(session)
%PARALLELSESSIONCLOSE Idempotently release all live parallel resources.
if isempty(session) || session.closed, return; end
if ~isempty(session.decode.scanner) && ...
        ~session.decode.scanner.finalized
    try
        [session.decode.scanner, ~] = ...
            radio.tuned.multiStreamScannerCancel( ...
                session.decode.scanner, 'Reason', 'session_closed');
    catch
    end
end
if ~isempty(session.actors.ddc)
    try
        session.actors.ddc = ...
            radio.live.ddcActorStop(session.actors.ddc);
    catch
    end
end
if ~isempty(session.actors.producer)
    try
        session.actors.producer = ...
            radio.live.fileProducerStop(session.actors.producer);
    catch
    end
end
if ~isempty(session.actors.spectrum)
    try
        session.actors.spectrum = ...
            radio.live.spectrumActorStop(session.actors.spectrum);
    catch
    end
end
if ~isempty(session.ring)
    try
        radio.live.sharedIqRingDelete(session.ring);
    catch
    end
    session.ring = [];
end
session.producerRunning = false;
session.closed = true;
session.mode = 'CLOSED';
end
