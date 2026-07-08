function pdu = parseDmacSyncSchS(type1Bits)
%PARSEDMACSYNCSCHS Parse the 60-bit DMAC-SYNC PDU carried on SCH/S.
type1Bits = type1Bits(:) ~= 0;
if numel(type1Bits) ~= 60
    error('tetra:parseDmacSyncSchS:BadLength', ...
        'DMAC-SYNC SCH/S parsing expects exactly 60 type-1 bits.');
end

pos = 1;
[systemCode, pos] = takeInt(type1Bits, pos, 4);
[syncPduType, pos] = takeInt(type1Bits, pos, 2);
[communicationType, pos] = takeInt(type1Bits, pos, 2);

firstConditional = type1Bits(pos); pos = pos + 1;
secondConditional = type1Bits(pos); pos = pos + 1;
[abChannelUsage, pos] = takeInt(type1Bits, pos, 2);
[slotCode, pos] = takeInt(type1Bits, pos, 2);
[frameCode, pos] = takeInt(type1Bits, pos, 5);
[airInterfaceEncryptionState, pos] = takeInt(type1Bits, pos, 2);

pdu = struct();
pdu.rawBits = type1Bits;
pdu.systemCode = systemCode;
pdu.systemCodeText = systemCodeText(systemCode);
pdu.syncPduType = syncPduType;
pdu.syncPduTypeText = syncPduTypeText(syncPduType);
pdu.communicationType = communicationType;
pdu.communicationTypeText = communicationTypeText(communicationType);

if communicationType == 1 || communicationType == 3
    pdu.masterSlaveLinkFlag = firstConditional;
    pdu.reservedAfterCommunicationType = false;
else
    pdu.masterSlaveLinkFlag = false;
    pdu.reservedAfterCommunicationType = firstConditional;
end
if communicationType == 2 || communicationType == 3
    pdu.gatewayGeneratedMessageFlag = secondConditional;
    pdu.reservedBeforeAbUsage = false;
else
    pdu.gatewayGeneratedMessageFlag = false;
    pdu.reservedBeforeAbUsage = secondConditional;
end

pdu.abChannelUsage = abChannelUsage;
pdu.abChannelUsageText = abChannelUsageText(abChannelUsage);
pdu.slotCode = slotCode;
pdu.slotNumber = slotCode + 1;
pdu.frameCode = frameCode;
if frameCode >= 1 && frameCode <= 18
    pdu.frameNumber = frameCode;
else
    pdu.frameNumber = NaN;
end
pdu.airInterfaceEncryptionState = airInterfaceEncryptionState;
pdu.airInterfaceEncryptionStateText = encryptionStateText(airInterfaceEncryptionState);

remaining = type1Bits(pos:end);
pdu.encryptionDependentBits = remaining;
if airInterfaceEncryptionState == 0
    pdu.reserved39 = remaining;
    pdu.reserved39Errors = nnz(remaining);
    pdu.tvp = NaN;
    pdu.ksgNumber = NaN;
    pdu.encryptionKeyNumber = NaN;
else
    pdu.tvp = tetra.bitsToInt(remaining(1:29));
    pdu.reservedEncryptionBit = remaining(30);
    pdu.ksgNumber = tetra.bitsToInt(remaining(31:34));
    pdu.encryptionKeyNumber = tetra.bitsToInt(remaining(35:39));
    pdu.reserved39 = false(0, 1);
    pdu.reserved39Errors = NaN;
end

pdu.isDmacSync = syncPduType == 0;
pdu.isDirectMsMs = communicationType == 0;
pdu.hasValidTiming = pdu.slotNumber >= 1 && pdu.slotNumber <= 4 && ...
    ~isnan(pdu.frameNumber);
end

function [value, pos] = takeInt(bits, pos, width)
value = tetra.bitsToInt(bits(pos:pos + width - 1));
pos = pos + width;
end

function txt = systemCodeText(value)
switch value
    case 12
        txt = 'ETS 300 396-3 DMO';
    case 13
        txt = 'EN 300 396-3 DMO AI';
    otherwise
        if value >= 10
            txt = 'DMO reserved';
        else
            txt = 'TMO or reserved';
        end
end
end

function txt = syncPduTypeText(value)
switch value
    case 0
        txt = 'DMAC-SYNC';
    case 1
        txt = 'DPRES-SYNC';
    otherwise
        txt = 'reserved';
end
end

function txt = communicationTypeText(value)
switch value
    case 0
        txt = 'Direct MS-MS';
    case 1
        txt = 'Via DM-REP';
    case 2
        txt = 'Via DM-GATE';
    case 3
        txt = 'Via DM-REP/GATE';
    otherwise
        txt = 'unknown';
end
end

function txt = abChannelUsageText(value)
switch value
    case 0
        txt = 'Channel A, normal mode';
    case 1
        txt = 'Channel A, frequency efficient mode';
    case 2
        txt = 'Channel B';
    otherwise
        txt = 'reserved';
end
end

function txt = encryptionStateText(value)
switch value
    case 0
        txt = 'DM-1 no air interface encryption';
    case 1
        txt = 'DM-2-C';
    case 2
        txt = 'DM-2-A';
    case 3
        txt = 'DM-2-B';
    otherwise
        txt = 'unknown';
end
end
