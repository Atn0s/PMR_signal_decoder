function decoded = decodeSchS(syncBlockBits, cfg)
%DECODESCHS Decode the 120-bit DMO SCH/S synchronization block.
if nargin < 2 || isempty(cfg)
    cfg = tetra.config();
end

syncBlockBits = syncBlockBits(:) ~= 0;
if numel(syncBlockBits) ~= 120
    error('tetra:decodeSchS:BadLength', ...
        'SCH/S decoding expects exactly 120 scrambled synchronization bits.');
end

base = tetra.decodeDmoSignallingBlock(syncBlockBits, 'SCH/S', zeros(30, 1) ~= 0, cfg);
type1Bits = base.type1Bits;
pdu = tetra.parseDmacSyncSchS(type1Bits);
ok = base.ok && pdu.isDmacSync && pdu.hasValidTiming;

decoded = struct();
decoded.logicalChannel = 'SCH/S';
decoded.ok = ok;
decoded.type1Bits = type1Bits;
decoded.type2Bits = base.type2Bits;
decoded.type3Bits = base.type3Bits;
decoded.descrambledBits = base.descrambledBits;
decoded.blockCodeErrors = base.blockCodeErrors;
decoded.tailErrors = base.tailErrors;
decoded.rcpcMetric = base.rcpcMetric;
decoded.rcpcFinalState = base.rcpcFinalState;
decoded.rcpcEndedInZeroState = base.rcpcEndedInZeroState;
decoded.base = base;
decoded.pdu = pdu;
decoded.frameNumber = pdu.frameNumber;
decoded.slotNumber = pdu.slotNumber;
decoded.abChannelUsage = pdu.abChannelUsage;
decoded.abChannelUsageText = pdu.abChannelUsageText;
decoded.communicationType = pdu.communicationType;
decoded.communicationTypeText = pdu.communicationTypeText;
end
