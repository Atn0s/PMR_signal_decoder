function actor = fileProducerArmDecoder(actor, maxQueueSec)
%FILEPRODUCERARMDECODER Buffer click-forward IQ until DDC is attached.
validateattributes(maxQueueSec, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'positive'});
message = struct('type', 'arm_decoder', ...
    'maxQueueSec', double(maxQueueSec));
actor = radio.live.fileProducerSendCommand(actor, message);
actor.decoderArmed = true;
end
