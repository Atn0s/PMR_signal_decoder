function pdus = decode(y, cfg)
%DECODE Native MATLAB dPMR metadata decode.
if nargin < 2 || isempty(cfg)
    cfg = dpmr.config();
end
c = dpmr.constants();
pdus = struct([]);
session = dpmr.sessionInit();
seen = [];

syncCandidates = dpmr.findSync(y, ...
    'Threshold', cfg.syncThreshold, ...
    'MaxSymbolErrors', cfg.syncMaxSymbolErrors, ...
    'MinDistanceSamples', cfg.syncMinDistanceSamples, ...
    'DedupWindowSymbols', cfg.syncDedupWindowSymbols, ...
    'SyncErrorPhaseSearch', linspace(-12, 12, 13), ...
    'SyncTypes', {'FS2'});
if numel(syncCandidates) > 100
    [~, order] = sort([syncCandidates.ncc], 'descend');
    syncCandidates = syncCandidates(order(1:100));
    [~, order] = sort([syncCandidates.fs_start]);
    syncCandidates = syncCandidates(order);
end

for k = 1:numel(syncCandidates)
    candidate = syncCandidates(k);
    bucket = round(candidate.fs_start / 240);
    if any(seen == bucket)
        continue;
    end
    seen(end + 1) = bucket; %#ok<AGROW>
    symbolCandidates = dpmr.recoverFrameSymbolCandidates(y, candidate, ...
        'TotalSymbols', c.voiceFs2TotalSymbols, ...
        'PhaseSearch', linspace(-12, 12, 25), ...
        'SpsSearch', 20, ...
        'SampleWindows', 0, ...
        'Limit', 8, ...
        'DecisionAmbiguousThreshold', 0.35);
    if isempty(symbolCandidates)
        continue;
    end

    best = [];
    bestScore = -inf;
    bestTiming = [];
    for j = 1:numel(symbolCandidates)
        decoded = dpmr.decodeVoiceSymbols(symbolCandidates(j).symbols);
        if isempty(decoded)
            continue;
        end
        score = candidateScore(decoded, symbolCandidates(j).resid);
        if score > bestScore
            bestScore = score;
            best = decoded;
            bestTiming = timingStruct(symbolCandidates(j));
        end
    end
    if isempty(best)
        continue;
    end

    quality = best.quality;
    quality.timing_coherent = true;
    quality.front_end_confidence = quality.confidence;
    [session, src, dst, superframePart] = dpmr.sessionFeed(session, best.cch0, best.cch1);
    exposeIds = strcmp(quality.confidence, 'high') && any(strcmp(superframePart, {'src', 'dst'}));
    if ~exposeIds
        src = '';
        dst = '';
    end

    extra = struct( ...
        'color_code', best.color_code, ...
        'sync_type', 'FS2', ...
        'polarity_inverted', candidate.polarity_inverted, ...
        'sync_ncc', candidate.ncc, ...
        'symbol_sps', bestTiming.sps, ...
        'symbol_phase', bestTiming.phase, ...
        'symbol_resid', bestTiming.resid, ...
        'symbol_sample_window', bestTiming.sample_window, ...
        'segment_timing', struct('cch0', bestTiming, 'cc', bestTiming, 'cch1', bestTiming), ...
        'fs_start', candidate.fs_start, ...
        'superframe_part', superframePart, ...
        'quality', quality, ...
        'cch', cchList(best.cch0, best.cch1));
    pdu = struct( ...
        'protocol', 'dPMR', ...
        'type', 'DPMR_VOICE', ...
        'src', src, ...
        'dst', dst, ...
        'ts', 0, ...
        'flco', 'VOICE', ...
        'fid', '', ...
        'extra', extra, ...
        'raw_bits', best.raw_bits);
    pdus = appendStruct(pdus, pdu);
end
pdus = radio.normalizePdus(pdus);
end

function score = candidateScore(decoded, resid)
records = {};
if ~isempty(decoded.cch0), records{end + 1} = decoded.cch0; end %#ok<AGROW>
if ~isempty(decoded.cch1), records{end + 1} = decoded.cch1; end %#ok<AGROW>
score = 0;
if decoded.color_code >= 0, score = score + 2; end
crcOk = 0;
hammingOk = 0;
frames = [];
for k = 1:numel(records)
    rec = records{k};
    crcOk = crcOk + double(rec.crc_ok);
    hammingOk = hammingOk + double(rec.hamming_ok);
    frames(end + 1) = rec.frame_number; %#ok<AGROW>
end
score = score + 5 * crcOk + 2 * hammingOk;
if all(ismember([0 1], frames)) || all(ismember([2 3], frames))
    score = score + 3;
end
score = score - 0.2 * resid;
end

function timing = timingStruct(candidate)
timing = struct('sps', candidate.sps, 'phase', candidate.phase, ...
    'resid', candidate.resid, 'sample_window', candidate.sample_window, ...
    'decision_error_p90', candidate.decision_error_p90, ...
    'ambiguous_symbols', candidate.ambiguous_symbols);
end

function list = cchList(cch0, cch1)
items = {};
if ~isempty(cch0), items{end + 1} = dpmr.cchExtra(cch0); end %#ok<AGROW>
if ~isempty(cch1), items{end + 1} = dpmr.cchExtra(cch1); end %#ok<AGROW>
if isempty(items)
    list = struct([]);
else
    list = [items{:}];
end
end

function out = appendStruct(arr, item)
if isempty(arr), out = item; else, out = arr; out(end + 1) = item; end
end
