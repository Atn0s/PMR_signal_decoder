function [state, pdus] = frameDecoderFinalize(state)
%FRAMEDECODERFINALIZE Flush an open NXDN session exactly once.
pdus = struct([]);
if state.finalized, return; end
[state.session, callPdu] = nxdn.sessionFinalize( ...
    state.session, state.cfg);
if ~isempty(callPdu)
    pdus = callPdu;
    state.pduCount = state.pduCount + uint64(1);
end
state.finalized = true;
end
