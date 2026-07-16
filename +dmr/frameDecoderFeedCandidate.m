function [state, pdus] = frameDecoderFeedCandidate( ...
        state, y, center, polarity, syncType, varargin)
%FRAMEDECODERFEEDCANDIDATE Decode one DMR candidate and retain call state.
if state.finalized
    error('dmr:frameDecoderFeedCandidate:Finalized', ...
        'Cannot feed a finalized DMR frame decoder.');
end
p = inputParser;
p.addParameter('CenterOffset', 0);
p.parse(varargin{:});
absoluteCenter = round(center + p.Results.CenterOffset);
key = sprintf('%d:%s', round(absoluteCenter / ...
    state.cfg.burstDedupWindowSamples), char(syncType));
pdus = struct([]);
if any(strcmp(state.seenKeys, key)), return; end
state.seenKeys{end+1, 1} = key;
if numel(state.seenKeys) > state.cfg.streamSeenKeyLimit
    state.seenKeys = state.seenKeys(end-state.cfg.streamSeenKeyLimit+1:end);
end
state.candidateCount = state.candidateCount + uint64(1);
pdu = dmr.decodeSyncCandidate(y, center, polarity, syncType, ...
    state.cfg, 'CenterOffset', p.Results.CenterOffset);
if isempty(pdu), return; end
pdus = pdu;
[state.session, callPdu] = dmr.sessionFeed( ...
    state.session, pdu, state.cfg.samplesPerSymbol);
if ~isempty(callPdu), pdus(end+1) = callPdu; end
state.decodedPduCount = state.decodedPduCount + uint64(numel(pdus));
if any(strcmp({pdus.type}, {'LC_HEADER', 'TERMINATOR', 'LATE_ENTRY'}))
    state.strongPduCount = state.strongPduCount + uint64(1);
end
pdus = radio.normalizePdus(pdus);
end
