function pdus = decode(y, cfg)
%DECODE Native MATLAB DMR metadata decode.
if nargin < 2 || isempty(cfg)
    cfg = dmr.config();
end
positions = dmr.findSyncPositions(y, cfg);
pdus = struct([]);
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
                pdus = appendStruct(pdus, pdu);
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
            pdus = appendStruct(pdus, pdu);
        end
    end
end
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
if isempty(arr), out = item; else, out = arr; out(end + 1) = item; end
end
