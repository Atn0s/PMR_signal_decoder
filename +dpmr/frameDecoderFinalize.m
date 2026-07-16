function [state, pdus] = frameDecoderFinalize(state)
%FRAMEDECODERFINALIZE Emit a pending dPMR call summary.
pdus = struct([]);
if state.finalized, return; end
[state.callSession, callPdu] = dpmr.callSessionFinalize( ...
    state.callSession, state.cfg.samplesPerSymbol);
if ~isempty(callPdu)
    pdus = radio.normalizePdus(callPdu);
    state.decodedPduCount = state.decodedPduCount + uint64(numel(pdus));
end
state.finalized = true;
end
