function pdus = decode(y, cfg)
%DECODE Native MATLAB DMR metadata decode.
if nargin < 2 || isempty(cfg)
    cfg = dmr.config();
end
positions = dmr.findSyncPositions(y, cfg);
pdus = struct([]);
session = dmr.sessionInit();
seenKeys = strings(0, 1);
for idx = 1:height(positions)
    center = positions.center(idx);
    polarity = positions.polarity(idx);
    syncType = char(positions.syncType(idx));
    key = sprintf('%d:%s', round(center / cfg.burstDedupWindowSamples), syncType);
    if any(seenKeys == key)
        continue;
    end
    seenKeys(end + 1) = key; %#ok<AGROW>

    if contains(syncType, 'VOICE')
        phase = dmr.lockVoicePhase(y, center, polarity, syncType);
        collector = lateEntryInit();
        for j = 0:cfg.voiceBurstCount-1
            bits = dmr.recoverSteppedBurstBits(y, center, j, phase, polarity, cfg.voiceBurstStrideSamples);
            if isempty(bits)
                break;
            end
            [collector, pdu] = lateEntryFeed(collector, bits);
            if ~isempty(pdu)
                pdu = stampPdu(pdu, round(center + cfg.voiceBurstStrideSamples * j), syncType);
                pdus = appendStruct(pdus, pdu);
                [session, callPdu] = dmr.sessionFeed(session, pdu, cfg.samplesPerSymbol);
                pdus = appendStruct(pdus, callPdu);
                break;
            end
        end
    else
        symbols = dmr.recoverBurst(y, center, polarity, syncType);
        if isempty(symbols)
            continue;
        end
        pdu = dmr.decodeBurst(symbols, syncType);
        if ~isempty(pdu)
            pdu = stampPdu(pdu, round(center), syncType);
            pdus = appendStruct(pdus, pdu);
            [session, callPdu] = dmr.sessionFeed(session, pdu, cfg.samplesPerSymbol);
            pdus = appendStruct(pdus, callPdu);
        end
    end
end
[session, callPdu] = dmr.sessionFinalize(session, cfg.samplesPerSymbol); %#ok<ASGLU>
pdus = appendStruct(pdus, callPdu);
pdus = radio.normalizePdus(pdus);
end

function collector = lateEntryInit()
collector = struct('frags', {{}}, 'collecting', false);
end

function [collector, pdu] = lateEntryFeed(collector, bits)
pdu = [];
center = bits(109:156);
embBits = [center(1:8), center(41:48)];
signalling = center(9:40);
lcss = dmr.bitsToInt(embBits(6:7));
if ~collector.collecting
    if lcss == 1
        collector.collecting = true;
        collector.frags = {signalling};
    end
else
    expectedCont = numel(collector.frags) < 3;
    if expectedCont
        if lcss ~= 3
            collector = lateEntryInit();
            if lcss == 1
                collector.collecting = true;
                collector.frags = {signalling};
            end
            return;
        end
    else
        if lcss ~= 2
            collector = lateEntryInit();
            if lcss == 1
                collector.collecting = true;
                collector.frags = {signalling};
            end
            return;
        end
    end
    collector.frags{end + 1} = signalling;
    if numel(collector.frags) == 4
        bits128 = [collector.frags{:}];
        collector = lateEntryInit();
        lc77 = dmr.vbptc128DataBits(bits128);
        lc72 = lc77(1:72);
        rxCs5 = dmr.bitsToInt(lc77(73:77));
        cs5ok = dmr.fiveBitChecksumOk(lc72, rxCs5);
        if ~cs5ok
            return;
        end
        flc = dmr.parseFullLinkControl(lc77);
        if isempty(flc)
            return;
        end
        pdu = struct( ...
            'protocol', 'DMR', ...
            'type', 'LATE_ENTRY', ...
            'src', flc.src, ...
            'dst', flc.dst, ...
            'ts', 0, ...
            'flco', flc.flco_name, ...
            'fid', flc.fid_name, ...
            'extra', struct('cs5_ok', cs5ok), ...
            'raw_bits', bits);
    end
end
end

function out = appendStruct(arr, item)
if isempty(item)
    out = arr;
elseif isempty(arr)
    out = item;
else
    out = arr;
    out(end + 1) = item;
end
end

function pdu = stampPdu(pdu, sample, syncType)
if ~isfield(pdu, 'extra') || isempty(pdu.extra)
    pdu.extra = struct();
end
pdu.extra.fs_start = sample;
pdu.extra.sync_center_sample = sample;
pdu.extra.sync_type = syncType;
end
