function [state, pdus] = frameDecoderFinalize(state)
%FRAMEDECODERFINALIZE Emit a pending DMR call summary.
pdus = struct([]);
if state.finalized, return; end
[state.session, callPdu] = ...
    dmr.sessionFinalize(state.session, state.cfg.samplesPerSymbol);
if ~isempty(callPdu)
    pdus = radio.normalizePdus(callPdu);
    state.decodedPduCount = state.decodedPduCount + uint64(numel(pdus));
end
state.finalized = true;
end
