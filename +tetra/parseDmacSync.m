function sync = parseDmacSync(schSInput, schHInput, cfg)
%PARSEDMACSYNC Parse the complete DMO DMAC-SYNC PDU from SCH/S and SCH/H.
if nargin < 3 || isempty(cfg) %#ok<INUSD>
    cfg = tetra.config();
end

schSBits = type1BitsFrom(schSInput, 60, 'SCH/S');
schHBits = type1BitsFrom(schHInput, 124, 'SCH/H');
schS = tetra.parseDmacSyncSchS(schSBits);

pos = 1;
truncated = false;
h = struct();
h.rawBits = schHBits;

switch schS.communicationType
    case 1
        [h.repeaterAddress, pos, truncated] = takeInt(schHBits, pos, 10, truncated);
        h.repeaterAddressText = sprintf('%d', h.repeaterAddress);
    case {2, 3}
        [h.gatewayAddress, pos, truncated] = takeInt(schHBits, pos, 10, truncated);
        h.gatewayAddressText = sprintf('%d', h.gatewayAddress);
    otherwise
        [h.reserved10, pos, truncated] = takeInt(schHBits, pos, 10, truncated);
        h.reserved10Errors = countBits(h.reserved10, 10);
end

[h.fillBitIndication, pos, truncated] = takeBit(schHBits, pos, truncated);
[h.fragmentationFlag, pos, truncated] = takeBit(schHBits, pos, truncated);
if h.fragmentationFlag
    [h.numberOfSchFSlots, pos, truncated] = takeInt(schHBits, pos, 4, truncated);
else
    h.numberOfSchFSlots = NaN;
end
[h.frameCountdown, pos, truncated] = takeInt(schHBits, pos, 2, truncated);
h.frameCountdownText = frameCountdownText(h.frameCountdown);

[h.destinationAddressType, pos, truncated] = takeInt(schHBits, pos, 2, truncated);
h.destinationAddressTypeText = addressTypeText(h.destinationAddressType);
if h.destinationAddressType ~= 2
    [h.destinationAddress, pos, truncated] = takeInt(schHBits, pos, 24, truncated);
else
    h.destinationAddress = NaN;
end

[h.sourceAddressType, pos, truncated] = takeInt(schHBits, pos, 2, truncated);
h.sourceAddressTypeText = addressTypeText(h.sourceAddressType);
if h.sourceAddressType ~= 2
    [h.sourceAddress, pos, truncated] = takeInt(schHBits, pos, 24, truncated);
else
    h.sourceAddress = NaN;
end

if schS.communicationType == 0 || schS.communicationType == 1
    [h.mobileNetworkIdentity, pos, truncated] = takeInt(schHBits, pos, 24, truncated);
else
    h.mobileNetworkIdentity = NaN;
end

[h.messageType, pos, truncated] = takeInt(schHBits, pos, 5, truncated);
messageStub = tetra.parseDmoMessageElements(h.messageType, false(0, 1));
h.messageTypeText = messageStub.messageTypeText;
remaining = schHBits(min(pos, numel(schHBits) + 1):end);
h.message = tetra.parseDmoMessageElements(h.messageType, remaining, ...
    'FillBitIndication', h.fillBitIndication, ...
    'LogicalChannel', 'SCH/H');
h.remainingBits = h.message.remainingBits;
h.remainingBitCount = h.message.remainingBitCount;
h.truncated = truncated || h.message.truncated;

dccValid = ~isnan(h.mobileNetworkIdentity) && ~isnan(h.sourceAddress);
if dccValid
    dccBits = tetra.dmoDcc(h.mobileNetworkIdentity, h.sourceAddress);
else
    dccBits = false(30, 1);
end

sync = struct();
sync.logicalChannel = 'SCH/S+SCH/H';
sync.ok = schS.isDmacSync && schS.hasValidTiming && ~h.truncated;
sync.schS = schS;
sync.schH = h;
sync.systemCode = schS.systemCode;
sync.systemCodeText = schS.systemCodeText;
sync.syncPduType = schS.syncPduType;
sync.syncPduTypeText = schS.syncPduTypeText;
sync.communicationType = schS.communicationType;
sync.communicationTypeText = schS.communicationTypeText;
sync.abChannelUsage = schS.abChannelUsage;
sync.abChannelUsageText = schS.abChannelUsageText;
sync.frameNumber = schS.frameNumber;
sync.slotNumber = schS.slotNumber;
sync.airInterfaceEncryptionState = schS.airInterfaceEncryptionState;
sync.airInterfaceEncryptionStateText = schS.airInterfaceEncryptionStateText;
sync.fillBitIndication = h.fillBitIndication;
sync.fragmentationFlag = h.fragmentationFlag;
sync.numberOfSchFSlots = h.numberOfSchFSlots;
sync.frameCountdown = h.frameCountdown;
sync.frameCountdownText = h.frameCountdownText;
sync.destinationAddressType = h.destinationAddressType;
sync.destinationAddressTypeText = h.destinationAddressTypeText;
sync.destinationAddress = h.destinationAddress;
sync.sourceAddressType = h.sourceAddressType;
sync.sourceAddressTypeText = h.sourceAddressTypeText;
sync.sourceAddress = h.sourceAddress;
sync.mobileNetworkIdentity = h.mobileNetworkIdentity;
sync.messageType = h.messageType;
sync.messageTypeText = h.messageTypeText;
sync.message = h.message;
sync.dccBits = dccBits;
sync.dccText = char('0' + double(dccBits(:).'));
sync.dccValid = dccValid;
sync.truncated = h.truncated;
end

function bits = type1BitsFrom(input, expectedLength, label)
if isstruct(input) && isfield(input, 'type1Bits')
    bits = input.type1Bits(:) ~= 0;
else
    bits = input(:) ~= 0;
end
if numel(bits) ~= expectedLength
    error('tetra:parseDmacSync:BadLength', ...
        '%s type-1 bits must be exactly %d bits.', label, expectedLength);
end
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

function n = countBits(value, width)
if isnan(value)
    n = NaN;
else
    n = nnz(tetra.intToBits(value, width));
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
