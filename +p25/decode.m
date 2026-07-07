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
c = p25.constants();

for k = 1:numel(candidates)
    symbols = p25.recoverSymbolsFromFs(y, candidates(k), c.fsNidSymbols, ...
        'Sps', cfg.samplesPerSymbol);
    if isempty(symbols)
        continue;
    end
    bits = p25.sliceSymbolsToBits(symbols);
    try
        nidBits = p25.extractNidBits(bits);
        nid = p25.decodeNid(nidBits);
    catch
        continue;
    end
    frame = p25.frameInfoFromNid(nid);

    lc = [];
    hcw = [];
    es = [];
    src = 0;
    dst = 0;
    if any(frame.duid == [0, 5, 10])
        fullSymbols = p25.recoverSymbolsFromFs(y, candidates(k), c.lduSymbols, ...
            'Sps', cfg.samplesPerSymbol);
        if ~isempty(fullSymbols)
            fullBits = p25.sliceSymbolsToBits(fullSymbols);
            if frame.duid == 5
                lc = p25.decodeLdu1Lc(fullBits);
                if ~isempty(lc)
                    src = lc.src;
                    dst = lc.dst;
                end
            elseif frame.duid == 0
                hcw = p25.decodeHduHcw(fullBits);
                if ~isempty(hcw)
                    dst = hcw.tgid;
                end
            elseif frame.duid == 10
                es = p25.decodeLdu2Es(fullBits);
            end
        end
    end

    rec = struct('nid', nid, 'frame', frame, 'candidate', candidates(k), ...
        'bits', bits, 'src', src, 'dst', dst, 'lc', lc, 'hcw', hcw, 'es', es);
    frames = appendStruct(frames, rec);
end

keep = stableFrameIndexes(frames, cfg.stableNacMinCount, cfg.stableNacMinRatio);
pdus = struct([]);
session = p25.sessionInit();
for idx = keep
    rec = frames(idx);
    pdu = nidPdu(rec.nid, rec.frame, rec.candidate, rec.bits, rec.src, rec.dst, ...
        rec.lc, rec.hcw, rec.es);
    if rec.frame.duid == 5 && ~isempty(rec.lc)
        pdu.type = 'P25_LDU1';
    elseif rec.frame.duid == 0 && ~isempty(rec.hcw)
        pdu.type = 'P25_HDU';
    elseif rec.frame.duid == 10 && ~isempty(rec.es)
        pdu.type = 'P25_LDU2';
    end
    pdus = appendStruct(pdus, pdu);
    [session, call] = p25.sessionFeed(session, rec.frame, rec.lc, ...
        rec.candidate.fs_start, cfg.samplesPerSymbol);
    if ~isempty(call)
        pdus = appendStruct(pdus, call);
    end
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

function pdu = nidPdu(nid, frame, candidate, bits, src, dst, lc, hcw, es)
extra = struct( ...
    'nac', nid.nac, ...
    'duid', nid.duid, ...
    'duid_name', nid.duid_name, ...
    'pdu_type', frame.pdu_type, ...
    'frame_category', frame.category, ...
    'is_voice', frame.is_voice, ...
    'is_control', frame.is_control, ...
    'is_terminator', frame.is_terminator, ...
    'has_link_control', frame.has_link_control, ...
    'valid_bch', nid.valid_bch, ...
    'corrected', nid.corrected, ...
    'fs_start', candidate.fs_start, ...
    'sync_ncc', candidate.ncc, ...
    'tgid', 0, ...
    'rs_ok', ~isempty(lc) || ~isempty(hcw) || ~isempty(es));
if ~isempty(lc)
    extra.tgid = lc.tgid;
    extra.lco = lc.lco;
    extra.mfid = lc.mfid;
    extra.svc = lc.svc;
    extra.lc_info = lc.lc_info;
    extra.lc_octet2 = lc.octet2;
    extra.lc_octet3 = lc.octet3;
    extra.lc_emergency = lc.emergency;
    extra.lc_reserved = lc.reserved;
    extra.lc_reserved_bits = lc.reserved_bits;
    extra.is_group = lc.is_group;
    extra.call_type = lc.call_type;
end
if ~isempty(hcw)
    extra.tgid = hcw.tgid;
    extra.mi = hcw.mi;
    extra.hdu_mfid = hcw.mfid;
    extra.algid = hcw.algid;
    extra.kid = hcw.kid;
    extra.hdu_tgid = hcw.tgid;
    extra.hdu_golay_corrected = hcw.golay_corrected;
end
if ~isempty(es)
    extra.es_mi = es.mi;
    extra.es_algid = es.algid;
    extra.es_kid = es.kid;
    extra.es_hamming_corrected = es.hamming_corrected;
end
pdu = struct( ...
    'protocol', 'P25', ...
    'type', 'P25_NID', ...
    'src', src, ...
    'dst', dst, ...
    'ts', 0, ...
    'flco', nid.duid_name, ...
    'fid', '', ...
    'extra', extra, ...
    'raw_bits', bits(:).');
end

function out = appendStruct(arr, item)
if isempty(arr)
    out = item;
else
    out = arr;
    out(end + 1) = item;
end
end
