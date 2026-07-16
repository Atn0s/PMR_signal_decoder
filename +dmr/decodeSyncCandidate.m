function pdu = decodeSyncCandidate( ...
        y, center, polarity, syncType, cfg, varargin)
%DECODESYNCCANDIDATE Decode one complete DMR sync/burst candidate.
if nargin < 5 || isempty(cfg), cfg = dmr.config(); end
p = inputParser;
p.addParameter('CenterOffset', 0);
p.parse(varargin{:});
syncType = char(syncType);
pdu = [];
if contains(syncType, 'VOICE')
    phase = dmr.lockVoicePhase(y, center, polarity, syncType);
    collector = lateEntryInit();
    for j = 0:cfg.voiceBurstCount-1
        bits = dmr.recoverSteppedBurstBits( ...
            y, center, j, phase, polarity, cfg.voiceBurstStrideSamples);
        if isempty(bits), break; end
        [collector, item] = lateEntryFeed(collector, bits);
        if ~isempty(item)
            sample = round(center + cfg.voiceBurstStrideSamples * j + ...
                p.Results.CenterOffset);
            pdu = stampPdu(item, sample, syncType);
            return;
        end
    end
    return;
end

symbols = dmr.recoverBurst(y, center, polarity, syncType);
if isempty(symbols), return; end
pdu = dmr.decodeBurst(symbols, syncType);
if ~isempty(pdu)
    pdu = stampPdu(pdu, ...
        round(center + p.Results.CenterOffset), syncType);
end
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
    return;
end
expectedContinuation = numel(collector.frags) < 3;
if expectedContinuation
    expectedLcss = 3;
else
    expectedLcss = 2;
end
if lcss ~= expectedLcss
    collector = lateEntryInit();
    if lcss == 1
        collector.collecting = true;
        collector.frags = {signalling};
    end
    return;
end
collector.frags{end+1} = signalling;
if numel(collector.frags) ~= 4, return; end
bits128 = [collector.frags{:}];
collector = lateEntryInit();
lc77 = dmr.vbptc128DataBits(bits128);
lc72 = lc77(1:72);
rxCs5 = dmr.bitsToInt(lc77(73:77));
cs5ok = dmr.fiveBitChecksumOk(lc72, rxCs5);
if ~cs5ok, return; end
flc = dmr.parseFullLinkControl(lc77);
if isempty(flc), return; end
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

function pdu = stampPdu(pdu, sample, syncType)
if ~isfield(pdu, 'extra') || isempty(pdu.extra)
    pdu.extra = struct();
end
pdu.extra.fs_start = sample;
pdu.extra.sync_center_sample = sample;
pdu.extra.sync_type = syncType;
end
