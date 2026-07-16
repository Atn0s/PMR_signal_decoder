function [state, pdus] = frameDecoderFeedRecord(state, record)
%FRAMEDECODERFEEDRECORD Consume one decoded P25 frame record.
if state.finalized
    error('p25:frameDecoderFeedRecord:Finalized', ...
        'Cannot feed a finalized P25 frame decoder.');
end
pdus = struct([]);
if isempty(record), return; end
state.candidateCount = state.candidateCount + uint64(1);
state.frameCount = state.frameCount + uint64(1);
if ~logical(record.nid.valid_bch)
    if ~state.hasValidBch
        state.pendingInvalidRecords = appendRecords( ...
            state.pendingInvalidRecords, record);
        limit = state.cfg.streamMaxPendingInvalidFrames;
        if numel(state.pendingInvalidRecords) > limit
            state.pendingInvalidRecords = ...
                state.pendingInvalidRecords(end-limit+1:end);
        end
    end
    return;
end

state.hasValidBch = true;
state.pendingInvalidRecords = struct([]);
state.validFrameCount = state.validFrameCount + uint64(1);
[state.session, pdus] = ...
    p25.frameRecordPdus(state.session, record, state.cfg);
state.pduCount = state.pduCount + uint64(numel(pdus));
end

function records = appendRecords(records, item)
if isempty(records)
    records = item;
else
    records(end+1) = item;
end
end
