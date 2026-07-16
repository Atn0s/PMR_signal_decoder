function pdus = decode(y, cfg)
%DECODE Native MATLAB P25 Phase 1 metadata decode.
if nargin < 2 || isempty(cfg)
    cfg = p25.config();
end

frames = struct([]);
candidates = p25.findFrameSync(y, ...
    'Sps', cfg.samplesPerSymbol, ...
    'Threshold', cfg.syncThreshold, ...
    'MinDistanceSymbols', cfg.syncMinDistanceSymbols);
for k = 1:numel(candidates)
    rec = p25.decodeFrameCandidate(y, candidates(k), cfg);
    if isempty(rec), continue; end
    frames = appendStruct(frames, rec);
end

keep = stableFrameIndexes(frames, cfg.stableNacMinCount, cfg.stableNacMinRatio);
pdus = struct([]);
session = p25.sessionInit();
for idx = keep
    rec = frames(idx);
    [session, framePdus] = p25.frameRecordPdus(session, rec, cfg);
    pdus = appendStruct(pdus, framePdus);
end
pdus = radio.normalizePdus(pdus);
end

function keep = stableFrameIndexes(frames, minCount, minRatio)
if isempty(frames)
    keep = [];
    return;
end
valid = find(arrayfun(@(f) logical(f.nid.valid_bch), frames));
if ~isempty(valid)
    keep = valid;
    return;
end
nacs = [frames.nid];
nacVals = [nacs.nac];
uniqueNacs = unique(nacVals);
counts = arrayfun(@(n) sum(nacVals == n), uniqueNacs);
[count, idx] = max(counts);
if count < minCount || count < max(minCount, floor(minRatio * numel(frames)))
    keep = [];
    return;
end
keep = find(nacVals == uniqueNacs(idx));
end

function out = appendStruct(arr, items)
if isempty(items)
    out = arr;
elseif isempty(arr)
    out = items;
else
    out = arr;
    out(end+1:end+numel(items)) = items;
end
end
