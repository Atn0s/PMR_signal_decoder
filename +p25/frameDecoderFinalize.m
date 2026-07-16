function [state, pdus] = frameDecoderFinalize(state)
%FRAMEDECODERFINALIZE Emit stable-NAC fallback records at end of input.
pdus = struct([]);
if state.finalized, return; end
if ~state.hasValidBch && ~isempty(state.pendingInvalidRecords)
    records = state.pendingInvalidRecords;
    nids = [records.nid];
    nacs = [nids.nac];
    values = unique(nacs);
    counts = arrayfun(@(n) sum(nacs == n), values);
    [count, index] = max(counts);
    required = max(state.cfg.stableNacMinCount, ...
        floor(state.cfg.stableNacMinRatio * numel(records)));
    if count >= state.cfg.stableNacMinCount && count >= required
        keep = find(nacs == values(index));
        for k = keep
            [state.session, items] = p25.frameRecordPdus( ...
                state.session, records(k), state.cfg);
            pdus = appendPdus(pdus, items);
        end
    end
end
state.pduCount = state.pduCount + uint64(numel(pdus));
state.pendingInvalidRecords = struct([]);
state.finalized = true;
end

function value = appendPdus(value, items)
if isempty(items), return; end
if isempty(value)
    value = items;
else
    value(end+1:end+numel(items)) = items;
end
end
