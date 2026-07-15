function [handle, status] = lockedDecoderCancel(handle)
%LOCKEDDECODERCANCEL Best-effort cancel of an obsolete decoder pass.
if strcmp(handle.mode, 'persistent_worker') && ~isempty(handle.actor)
    handle.actor = radio.stream.lockedDecoderActorStop(handle.actor);
elseif ~handle.completed && ~isempty(handle.future)
    try
        cancel(handle.future);
    catch
    end
end
handle.canceled = true;
handle.completed = true;
handle.elapsedSec = toc(handle.timerToken);
handle.decoderState = [];
handle.output = [];
handle.errorReason = 'locked_decoder_canceled';
[handle, status] = radio.stream.lockedDecoderPoll(handle);
end
