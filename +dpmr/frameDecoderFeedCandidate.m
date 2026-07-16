function [state, pdus] = frameDecoderFeedCandidate( ...
        state, y, candidate, varargin)
%FRAMEDECODERFEEDCANDIDATE Decode one dPMR frame and retain sessions.
if state.finalized
    error('dpmr:frameDecoderFeedCandidate:Finalized', ...
        'Cannot feed a finalized dPMR frame decoder.');
end
p = inputParser;
p.addParameter('SampleOffset', 0);
p.parse(varargin{:});
absoluteStart = round(candidate.fs_start + p.Results.SampleOffset);
key = sprintf('%d:%s', round(absoluteStart / 240), ...
    char(candidate.sync_type));
pdus = struct([]);
if any(strcmp(state.seenKeys, key)), return; end
state.seenKeys{end+1, 1} = key;
if numel(state.seenKeys) > state.cfg.streamSeenKeyLimit
    state.seenKeys = state.seenKeys(end-state.cfg.streamSeenKeyLimit+1:end);
end
state.candidateCount = state.candidateCount + uint64(1);
[state.idSession, pdu] = dpmr.decodeSyncCandidate( ...
    state.idSession, y, candidate, state.cfg, ...
    'SampleOffset', p.Results.SampleOffset);
if isempty(pdu), return; end
pdus = pdu;
[state.callSession, callPdu] = dpmr.callSessionFeed( ...
    state.callSession, pdu, state.cfg.samplesPerSymbol);
if ~isempty(callPdu), pdus(end+1) = callPdu; end
state.decodedPduCount = state.decodedPduCount + uint64(numel(pdus));
records = radio.getNestedField(pdu, 'extra.cch', struct([]));
if any(arrayfun(@(item) logical(radio.getField( ...
        item, 'crc_ok', false)), records))
    state.crcValidPduCount = state.crcValidPduCount + uint64(1);
end
pdus = radio.normalizePdus(pdus);
end
