function actor = fileProducerDetachDecoder(actor)
%FILEPRODUCERDETACHDECODER Disable and clear the click-forward IQ tap.
if isempty(actor) || actor.stopped || actor.failed || actor.terminal
    return;
end
message = struct('type', 'detach_decoder');
actor = radio.live.fileProducerSendCommand(actor, message);
actor.decoderArmed = false;
end
