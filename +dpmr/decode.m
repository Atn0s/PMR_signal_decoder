function pdus = decode(y, cfg)
%DECODE Native MATLAB dPMR metadata decode.
if nargin < 2 || isempty(cfg)
    cfg = dpmr.config();
end
c = dpmr.constants();
pdus = struct([]);
pdus = appendStruct(pdus, decodeHeaderFrames(y, cfg));
session = dpmr.sessionInit();
seen = [];

syncCandidates = dpmr.findSync(y, ...
    'Threshold', cfg.syncThreshold, ...
    'MaxSymbolErrors', cfg.syncMaxSymbolErrors, ...
    'MinDistanceSamples', cfg.syncMinDistanceSamples, ...
    'DedupWindowSymbols', cfg.syncDedupWindowSymbols, ...
    'SyncErrorPhaseSearch', syncErrorPhaseSearch(cfg), ...
    'SyncTypes', {'FS2'});
if numel(syncCandidates) > cfg.voiceSyncCandidateLimit
    [~, order] = sort([syncCandidates.ncc], 'descend');
    syncCandidates = syncCandidates(order(1:cfg.voiceSyncCandidateLimit));
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
        'PhaseSearch', symbolPhaseSearch(cfg), ...
        'SpsSearch', spsSearch(cfg), ...
        'SampleWindows', cfg.sampleWindows, ...
        'Limit', cfg.voiceSymbolCandidateLimit, ...
        'DecisionAmbiguousThreshold', cfg.decisionAmbiguousThreshold);
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
        'cch', cchList(best.cch0, best.cch1), ...
        'frame_numbers', frameNumbers(cchRecords(best.cch0, best.cch1)));
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
pdus = appendCallSummaries(pdus, cfg.samplesPerSymbol);
pdus = radio.normalizePdus(pdus);
end

function pdus = decodeHeaderFrames(y, cfg)
c = dpmr.constants();
pdus = struct([]);
seen = [];
syncCandidates = dpmr.findSync(y, ...
    'Threshold', cfg.syncThreshold, ...
    'MaxSymbolErrors', cfg.syncMaxSymbolErrors, ...
    'MinDistanceSamples', cfg.syncMinDistanceSamples, ...
    'DedupWindowSymbols', cfg.syncDedupWindowSymbols, ...
    'SyncErrorPhaseSearch', syncErrorPhaseSearch(cfg), ...
    'SyncTypes', {'FS1'});
if numel(syncCandidates) > cfg.headerSyncCandidateLimit
    [~, order] = sort([syncCandidates.ncc], 'descend');
    syncCandidates = syncCandidates(order(1:cfg.headerSyncCandidateLimit));
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
        'TotalSymbols', c.frameSymbols, ...
        'PhaseSearch', symbolPhaseSearch(cfg), ...
        'SpsSearch', spsSearch(cfg), ...
        'SampleWindows', cfg.sampleWindows, ...
        'Limit', cfg.headerSymbolCandidateLimit, ...
        'DecisionAmbiguousThreshold', cfg.decisionAmbiguousThreshold);
    if isempty(symbolCandidates)
        continue;
    end

    best = [];
    bestScore = -inf;
    bestTie = -inf;
    bestTiming = [];
    for j = 1:numel(symbolCandidates)
        payload = symbolCandidates(j).symbols(numel(c.fs1Symbols)+1:end);
        decoded = dpmr.decodeHeaderPayload(payload);
        if isempty(decoded)
            continue;
        end
        score = headerScore(decoded, symbolCandidates(j).resid);
        tie = -symbolCandidates(j).resid;
        if score > bestScore || (score == bestScore && tie > bestTie)
            bestScore = score;
            bestTie = tie;
            best = decoded;
            bestTiming = timingStruct(symbolCandidates(j));
        end
    end
    if isempty(best)
        continue;
    end

    extra = struct( ...
        'color_code', best.color_code, ...
        'sync_type', 'FS1', ...
        'polarity_inverted', candidate.polarity_inverted, ...
        'sync_ncc', candidate.ncc, ...
        'symbol_sps', bestTiming.sps, ...
        'symbol_phase', bestTiming.phase, ...
        'symbol_resid', bestTiming.resid, ...
        'symbol_sample_window', bestTiming.sample_window, ...
        'segment_timing', struct('header', bestTiming), ...
        'fs_start', candidate.fs_start, ...
        'superframe_part', best.superframe_part, ...
        'quality', best.quality, ...
        'cch', cchList(best.cch_records), ...
        'cch_offsets', best.cch_offsets, ...
        'color_code_candidates', best.color_codes, ...
        'color_code_offsets', best.color_offsets, ...
        'frame_numbers', frameNumbers(best.cch_records));
    pdu = struct( ...
        'protocol', 'dPMR', ...
        'type', 'DPMR_HEADER', ...
        'src', best.src, ...
        'dst', best.dst, ...
        'ts', 0, ...
        'flco', 'HEADER', ...
        'fid', '', ...
        'extra', extra, ...
        'raw_bits', best.raw_bits);
    pdus = appendStruct(pdus, pdu);
end
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

function score = headerScore(decoded, resid)
score = 0;
crcOk = 0;
hammingOk = 0;
frames = [];
records = decoded.cch_records;
for k = 1:numel(records)
    rec = records(k);
    crcOk = crcOk + double(rec.crc_ok);
    hammingOk = hammingOk + double(rec.hamming_ok);
    if dpmr.cchUsable(rec)
        frames(end + 1) = rec.frame_number; %#ok<AGROW>
    end
end
score = score + 8 * crcOk + 2 * hammingOk;
if ~isempty(decoded.color_codes)
    score = score + 2;
end
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
if nargin < 2
    records = cch0;
else
    records = struct([]);
    if ~isempty(cch0), records = appendStruct(records, cch0); end
    if ~isempty(cch1), records = appendStruct(records, cch1); end
end
list = struct([]);
for k = 1:numel(records)
    list = appendStruct(list, dpmr.cchExtra(records(k)));
end
end

function nums = frameNumbers(records)
nums = [];
for k = 1:numel(records)
    nums(end + 1) = records(k).frame_number; %#ok<AGROW>
end
end

function pdus = appendCallSummaries(pdus, sps)
if isempty(pdus)
    return;
end
orderValues = zeros(1, numel(pdus));
for k = 1:numel(pdus)
    orderValues(k) = double(radio.getNestedField(pdus(k), 'extra.fs_start', 0));
end
[~, order] = sort(orderValues);
callSession = dpmr.callSessionInit();
summaries = struct([]);
for idx = order
    [callSession, callPdu] = dpmr.callSessionFeed(callSession, pdus(idx), sps);
    summaries = appendStruct(summaries, callPdu);
end
[callSession, callPdu] = dpmr.callSessionFinalize(callSession, sps); %#ok<ASGLU>
summaries = appendStruct(summaries, callPdu);
pdus = appendStruct(pdus, summaries);
end

function values = syncErrorPhaseSearch(cfg)
values = linspace(cfg.syncErrorPhaseMin, cfg.syncErrorPhaseMax, cfg.syncErrorPhaseSteps);
end

function values = symbolPhaseSearch(cfg)
values = linspace(cfg.phaseSearchMin, cfg.phaseSearchMax, cfg.phaseSearchSteps);
end

function values = spsSearch(cfg)
values = linspace(cfg.spsSearchMin, cfg.spsSearchMax, cfg.spsSearchSteps);
end

function out = appendStruct(arr, item)
if isempty(item)
    out = arr;
elseif isempty(arr)
    out = item;
else
    out = arr;
    n = numel(out);
    out(n + 1:n + numel(item)) = item;
end
end

function records = cchRecords(cch0, cch1)
records = struct([]);
if ~isempty(cch0)
    records = appendStruct(records, cch0);
end
if ~isempty(cch1)
    records = appendStruct(records, cch1);
end
end
