function [state, pdus] = frameDecoderFinalize(state)
%FRAMEDECODERFINALIZE Emit a pending TETRA DMO session summary.
pdus = struct([]);
if state.finalized, return; end
[state.sessionState, pdus] = ...
    tetra.sessionDecoderFinalize(state.sessionState);
state.decodedPduCount = state.decodedPduCount + uint64(numel(pdus));
state.finalized = true;
pdus = radio.normalizePdus(pdus);
end
