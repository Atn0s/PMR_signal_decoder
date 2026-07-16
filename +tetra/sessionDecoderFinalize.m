function [state, summaries] = sessionDecoderFinalize(state)
%SESSIONDECODERFINALIZE Emit the pending TETRA DMO session summary.
summaries = struct([]);
if state.finalized, return; end
if state.session.active
    stateName = 'open';
    if ~isempty(state.session.releaseMessage), stateName = 'closed'; end
    summaries = tetra.sessionDecoderPdu(state.session, stateName);
end
state.finalized = true;
end
