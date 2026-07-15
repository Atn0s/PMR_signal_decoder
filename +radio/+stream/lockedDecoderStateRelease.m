function state = lockedDecoderStateRelease(state)
%LOCKEDDECODERSTATERELEASE Stop resources owned by a client decoder shadow.
if isempty(state) || ~isstruct(state) || ~isfield(state, 'actor') || ...
        isempty(state.actor)
    return;
end
state.actor = radio.stream.lockedDecoderActorStop(state.actor);
state.actor = [];
end
