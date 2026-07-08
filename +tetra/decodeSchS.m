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

descrambled = xor(syncBlockBits, tetra.scramblingSequence(120));
type3Bits = tetra.blockDeinterleave(descrambled, 11);
[type2Bits, rcpcInfo] = tetra.rcpcDecodeRate23(type3Bits, 80);

type1Bits = type2Bits(1:60);
rxParity = type2Bits(61:76);
calcParity = tetra.dmoBlockCodeParity(type1Bits);
tailBits = type2Bits(77:80);
blockCodeErrors = nnz(rxParity ~= calcParity);
tailErrors = nnz(tailBits);

pdu = tetra.parseDmacSyncSchS(type1Bits);
ok = blockCodeErrors <= getCfg(cfg, 'schSBlockCodeMaxErrors', 0) && ...
    tailErrors <= getCfg(cfg, 'schSTailMaxErrors', 0) && ...
    pdu.isDmacSync && pdu.hasValidTiming;

decoded = struct();
decoded.logicalChannel = 'SCH/S';
decoded.ok = ok;
decoded.type1Bits = type1Bits;
decoded.type2Bits = type2Bits;
decoded.type3Bits = type3Bits;
decoded.descrambledBits = descrambled;
decoded.blockCodeErrors = blockCodeErrors;
decoded.tailErrors = tailErrors;
decoded.rcpcMetric = rcpcInfo.metric;
decoded.rcpcFinalState = rcpcInfo.finalState;
decoded.rcpcEndedInZeroState = rcpcInfo.endedInZeroState;
decoded.pdu = pdu;
decoded.frameNumber = pdu.frameNumber;
decoded.slotNumber = pdu.slotNumber;
decoded.abChannelUsage = pdu.abChannelUsage;
decoded.abChannelUsageText = pdu.abChannelUsageText;
decoded.communicationType = pdu.communicationType;
decoded.communicationTypeText = pdu.communicationTypeText;
end

function value = getCfg(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
