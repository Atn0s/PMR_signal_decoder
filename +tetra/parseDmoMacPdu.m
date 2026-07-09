function pdu = parseDmoMacPdu(type1Bits, logicalChannel, context)
%PARSEDMOMACPDU Parse DMO MAC PDUs carried on STCH or SCH/F.
if nargin < 2 || isempty(logicalChannel)
    logicalChannel = '';
end
if nargin < 3
    context = struct();
end

type1Bits = type1Bits(:) ~= 0;
pos = 1;
truncated = false;
[macPduType, pos, truncated] = takeInt(type1Bits, pos, 2, truncated);

pdu = struct();
pdu.logicalChannel = char(logicalChannel);
pdu.rawBits = type1Bits;
pdu.macPduType = macPduType;
pdu.macPduTypeText = macPduTypeText(macPduType);
pdu.communicationType = contextField(context, 'communicationType', NaN);
pdu.communicationTypeText = contextField(context, 'communicationTypeText', '');
pdu.truncated = truncated;
pdu.ok = ~truncated;

switch macPduType
    case 0
        [pdu, pos, truncated] = parseDmacData(pdu, type1Bits, pos, context, truncated);
    case 1
        [pdu, pos, truncated] = parseDmacFragEnd(pdu, type1Bits, pos, truncated);
    case 3
        [pdu, pos, truncated] = parseDmacUSignal(pdu, type1Bits, pos, truncated);
    otherwise
        pdu.reservedBits = type1Bits(min(pos, numel(type1Bits) + 1):end);
        pdu.ok = false;
end

pdu.remainingBits = type1Bits(min(pos, numel(type1Bits) + 1):end);
pdu.remainingBitCount = numel(pdu.remainingBits);
pdu.truncated = pdu.truncated || truncated;
pdu.ok = pdu.ok && ~pdu.truncated;
end

function [pdu, pos, truncated] = parseDmacData(pdu, bits, pos, context, truncated)
pdu.pduName = 'DMAC-DATA';
[pdu.fillBitIndication, pos, truncated] = takeBit(bits, pos, truncated);
[pdu.secondHalfSlotStolenFlag, pos, truncated] = takeBit(bits, pos, truncated);
[pdu.fragmentationFlag, pos, truncated] = takeBit(bits, pos, truncated);
[pdu.nullPduFlag, pos, truncated] = takeBit(bits, pos, truncated);
if pdu.nullPduFlag
    pdu.isNullPdu = true;
    return;
end
pdu.isNullPdu = false;
[pdu.frameCountdown, pos, truncated] = takeInt(bits, pos, 2, truncated);
pdu.frameCountdownText = frameCountdownText(pdu.frameCountdown);
[pdu.airInterfaceEncryptionState, pos, truncated] = takeInt(bits, pos, 2, truncated);
pdu.airInterfaceEncryptionStateText = encryptionStateText(pdu.airInterfaceEncryptionState);
[pdu.destinationAddressType, pos, truncated] = takeInt(bits, pos, 2, truncated);
pdu.destinationAddressTypeText = addressTypeText(pdu.destinationAddressType);
if pdu.destinationAddressType ~= 2
    [pdu.destinationAddress, pos, truncated] = takeInt(bits, pos, 24, truncated);
else
    pdu.destinationAddress = NaN;
end
[pdu.sourceAddressType, pos, truncated] = takeInt(bits, pos, 2, truncated);
pdu.sourceAddressTypeText = addressTypeText(pdu.sourceAddressType);
if pdu.sourceAddressType ~= 2
    [pdu.sourceAddress, pos, truncated] = takeInt(bits, pos, 24, truncated);
else
    pdu.sourceAddress = NaN;
end
commType = contextField(context, 'communicationType', NaN);
if commType == 0 || commType == 1
    [pdu.mobileNetworkIdentity, pos, truncated] = takeInt(bits, pos, 24, truncated);
else
    pdu.mobileNetworkIdentity = NaN;
end
[pdu.messageType, pos, truncated] = takeInt(bits, pos, 5, truncated);
msgBits = bits(min(pos, numel(bits) + 1):end);
pdu.message = tetra.parseDmoMessageElements(pdu.messageType, msgBits, ...
    'FillBitIndication', pdu.fillBitIndication, ...
    'LogicalChannel', pdu.logicalChannel);
pdu.messageTypeText = pdu.message.messageTypeText;
pos = numel(bits) - pdu.message.remainingBitCount + 1;
truncated = truncated || pdu.message.truncated;
end

function [pdu, pos, truncated] = parseDmacFragEnd(pdu, bits, pos, truncated)
[subtype, pos, truncated] = takeBit(bits, pos, truncated);
pdu.subtype = double(subtype);
if subtype
    pdu.pduName = 'DMAC-END';
else
    pdu.pduName = 'DMAC-FRAG';
end
[pdu.fillBitIndication, pos, truncated] = takeBit(bits, pos, truncated);
pdu.dmSduBits = bits(min(pos, numel(bits) + 1):end);
pdu.dmSduBitCount = numel(pdu.dmSduBits);
pos = numel(bits) + 1;
end

function [pdu, pos, truncated] = parseDmacUSignal(pdu, bits, pos, truncated)
pdu.pduName = 'DMAC-U-SIGNAL';
[pdu.secondHalfSlotStolenFlag, pos, truncated] = takeBit(bits, pos, truncated);
n = min(121, max(0, numel(bits) - pos + 1));
pdu.uPlaneDmSduBits = bits(pos:pos + n - 1);
pdu.uPlaneDmSduBitCount = n;
if n < 121
    truncated = true;
end
pos = pos + n;
end

function [value, pos, truncated] = takeInt(bits, pos, width, truncated)
if pos + width - 1 > numel(bits)
    value = NaN;
    truncated = true;
    return;
end
value = tetra.bitsToInt(bits(pos:pos + width - 1));
pos = pos + width;
end

function [value, pos, truncated] = takeBit(bits, pos, truncated)
if pos > numel(bits)
    value = false;
    truncated = true;
    return;
end
value = bits(pos);
pos = pos + 1;
end

function value = contextField(context, name, defaultValue)
if isstruct(context) && isfield(context, name)
    value = context.(name);
else
    value = defaultValue;
end
end

function txt = macPduTypeText(value)
switch value
    case 0
        txt = 'DMAC-DATA';
    case 1
        txt = 'DMAC-FRAG/END';
    case 2
        txt = 'reserved';
    case 3
        txt = 'DMAC-U-SIGNAL';
    otherwise
        txt = 'unknown';
end
end

function txt = addressTypeText(value)
switch value
    case 0
        txt = 'true SSI with MNI';
    case 1
        txt = 'pseudo SSI';
    case 2
        txt = 'no address';
    otherwise
        txt = 'reserved';
end
end

function txt = frameCountdownText(value)
switch value
    case 0
        txt = 'final frame';
    case 1
        txt = 'one frame to follow';
    case 2
        txt = 'two frames to follow';
    case 3
        txt = 'three frames to follow';
    otherwise
        txt = 'unknown';
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
