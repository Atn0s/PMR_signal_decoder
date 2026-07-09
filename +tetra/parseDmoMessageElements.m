function parsed = parseDmoMessageElements(messageType, bits, varargin)
%PARSEDMOMESSAGEELEMENTS Parse DMO message-dependent fields and DM-SDU bits.
p = inputParser;
p.addParameter('FillBitIndication', false);
p.addParameter('LogicalChannel', '');
p.parse(varargin{:});

bits = bits(:) ~= 0;
messageType = double(messageType);
pos = 1;
truncated = false;
md = struct();
dm = struct();

switch messageType
    case 0
        [md, pos, truncated] = takeBitField(md, bits, pos, 'channelReservationType', truncated);
        [md, pos, truncated] = takeIntField(md, bits, pos, 'reservationTimeRemaining', 6, truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingFlag', truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'requestsFlag', truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'changeoverRequestsFlag', truncated);
        if flagTrue(md, 'requestsFlag')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'requestsBitmap', 8, truncated);
        end
        [md, pos, truncated] = takeIntField(md, bits, pos, 'powerClass', 3, truncated);
        md.powerClassText = powerClassText(getField(md, 'powerClass'));
        [md, pos, truncated] = takeBitField(md, bits, pos, 'powerControlFlag', truncated);
        [md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);
        [md, pos] = takeOptionalBitField(md, bits, pos, 'dualWatchSynchronizationFlag');
        [md, pos] = takeOptionalBitField(md, bits, pos, 'twoFrequencyCallFlag');

    case 1
        [md, pos, truncated] = takeIntField(md, bits, pos, 'sdsTimeRemaining', 4, truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'sdsTransactionType', truncated);
        [md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);

    case 2
        [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);

    case 3
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingAcceptanceFlag', truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingChangeAnnounced', truncated);
        if flagTrue(md, 'timingChangeAnnounced')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);
        end

    case {8, 12, 13}
        [md, dm, pos, truncated] = parseSetupLike(md, dm, bits, pos, truncated);

    case 9
        [md, dm, pos, truncated] = parseSetupPresence(md, dm, bits, pos, truncated);

    case 10
        [md, pos, truncated] = takeIntField(md, bits, pos, 'circuitModeType', 4, truncated);
        md.circuitModeTypeText = circuitModeTypeText(getField(md, 'circuitModeType'));
        [md, pos, truncated] = takeIntField(md, bits, pos, 'reserved4', 4, truncated);
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'reserved4', 4, truncated);

    case 11
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'disconnectCause', 4, truncated);
        dm.disconnectCauseText = causeText(getField(dm, 'disconnectCause'), 'disconnect');

    case 14
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'releaseCause', 4, truncated);
        if getField(dm, 'releaseCause') == 15
            [dm, pos, truncated] = takeIntField(dm, bits, pos, 'releaseCauseExtension', 5, truncated);
        end

    case 15
        [md, pos, truncated] = takeIntField(md, bits, pos, 'reservationTimeRemaining', 6, truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingFlag', truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'requestsFlag', truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'changeoverRequestsFlag', truncated);
        if flagTrue(md, 'requestsFlag')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'requestsBitmap', 8, truncated);
        end
        [md, pos, truncated] = takeBitField(md, bits, pos, 'recentUserPriorityFlag', truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingChangeAnnounced', truncated);
        if flagTrue(md, 'timingChangeAnnounced')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);
        end
        [md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'ceaseCause', 4, truncated);

    case 16
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingChangeRequired', truncated);
        if flagTrue(md, 'timingChangeRequired')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);
        end
        [md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);

    case 17
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingChangeAnnounced', truncated);
        if flagTrue(md, 'timingChangeAnnounced')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);
        end

    case 18
        [md, pos, truncated] = takeIntField(md, bits, pos, 'perceivedChannelState', 2, truncated);
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingChangeRequired', truncated);
        if flagTrue(md, 'timingChangeRequired')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);
        end
        [md, pos, truncated] = takeBitField(md, bits, pos, 'newCallPreEmption', truncated);
        [md, pos, truncated] = takeIntField(md, bits, pos, 'typeOfPreEmption', 4, truncated);
        [md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);

    case 19
        [md, pos, truncated] = takeBitField(md, bits, pos, 'timingChangeAnnounced', truncated);
        if flagTrue(md, 'timingChangeAnnounced')
            [md, pos, truncated] = takeIntField(md, bits, pos, 'timingAdjustment', 12, truncated);
        end
        [md, pos, truncated] = takeBitField(md, bits, pos, 'newCallPreEmption', truncated);
        [md, pos, truncated] = takeIntField(md, bits, pos, 'typeOfPreEmption', 4, truncated);

    case 20
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'rejectCause', 4, truncated);

    case 21
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'informationType', 3, truncated);
        if getField(dm, 'informationType') == 0
            [dm, pos, truncated] = takeIntField(dm, bits, pos, 'callingPartyTsi', 48, truncated);
        end

    case {22, 23}
        [md, dm, pos, truncated] = parseSdsData(md, dm, bits, pos, truncated);

    case 24
        [md, pos, truncated] = takeBitField(md, bits, pos, 'fcsFlag', truncated);
        [dm, pos, truncated] = takeIntField(dm, bits, pos, 'acknowledgementType', 4, truncated);
        if getField(dm, 'acknowledgementType') == 1
            [dm, pos, truncated] = takeIntField(dm, bits, pos, 'sdti', 4, truncated);
        end
end

remaining = bits(min(pos, numel(bits) + 1):end);
if ismember(messageType, [22 23])
    dm.sdsPayloadBits = remaining;
elseif ~isempty(remaining)
    dm.remainingBits = remaining;
end

parsed = struct();
parsed.messageType = messageType;
parsed.messageTypeText = messageTypeText(messageType);
parsed.logicalChannel = char(p.Results.LogicalChannel);
parsed.fillBitIndication = logical(p.Results.FillBitIndication);
parsed.rawBits = bits;
parsed.messageDependent = md;
parsed.dmSdu = dm;
parsed.remainingBits = remaining;
parsed.remainingBitCount = numel(remaining);
parsed.truncated = truncated;
end

function [md, dm, pos, truncated] = parseSetupLike(md, dm, bits, pos, truncated)
[md, pos, truncated] = takeBitField(md, bits, pos, 'timingFlag', truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'lchInFrame18Flag', truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'preEmptionFlag', truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'powerClass', 3, truncated);
md.powerClassText = powerClassText(getField(md, 'powerClass'));
[md, pos, truncated] = takeBitField(md, bits, pos, 'powerControlFlag', truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'reserved2', 2, truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'dualWatchSynchronizationFlag', truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'twoFrequencyCallFlag', truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'circuitModeType', 4, truncated);
md.circuitModeTypeText = circuitModeTypeText(getField(md, 'circuitModeType'));
[md, pos, truncated] = takeIntField(md, bits, pos, 'reserved4', 4, truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);
[dm, pos, truncated] = takeSetupDmSdu(dm, bits, pos, truncated);
end

function [md, dm, pos, truncated] = parseSetupPresence(md, dm, bits, pos, truncated)
[md, pos, truncated] = takeIntField(md, bits, pos, 'reserved3', 3, truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'powerClass', 3, truncated);
md.powerClassText = powerClassText(getField(md, 'powerClass'));
[md, pos, truncated] = takeBitField(md, bits, pos, 'powerControlFlag', truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'reserved2', 2, truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'dualWatchSynchronizationFlag', truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'twoFrequencyCallFlag', truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'circuitModeType', 4, truncated);
md.circuitModeTypeText = circuitModeTypeText(getField(md, 'circuitModeType'));
[md, pos, truncated] = takeIntField(md, bits, pos, 'reserved4', 4, truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);
[dm, pos, truncated] = takeSetupDmSdu(dm, bits, pos, truncated);
end

function [dm, pos, truncated] = takeSetupDmSdu(dm, bits, pos, truncated)
[dm, pos, truncated] = takeBitField(dm, bits, pos, 'endToEndEncryptionFlag', truncated);
[dm, pos, truncated] = takeBitField(dm, bits, pos, 'callTypeFlag', truncated);
[dm, pos, truncated] = takeBitField(dm, bits, pos, 'externalSourceFlag', truncated);
[dm, pos, truncated] = takeIntField(dm, bits, pos, 'reserved2', 2, truncated);
end

function [md, dm, pos, truncated] = parseSdsData(md, dm, bits, pos, truncated)
[md, pos, truncated] = takeIntField(md, bits, pos, 'sdsTimeRemaining', 4, truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'sdsTransactionType', truncated);
[md, pos, truncated] = takeIntField(md, bits, pos, 'priorityLevel', 2, truncated);
[md, pos, truncated] = takeBitField(md, bits, pos, 'fcsFlag', truncated);
[dm, pos, truncated] = takeBitField(dm, bits, pos, 'additionalAddressingFlag', truncated);
if flagTrue(dm, 'additionalAddressingFlag')
    [dm, pos, truncated] = takeIntField(dm, bits, pos, 'additionalAddressTypes', 4, truncated);
end
if canTake(bits, pos, 4)
    [dm, pos, truncated] = takeIntField(dm, bits, pos, 'sdti', 4, truncated);
end
end

function [s, pos, truncated] = takeBitField(s, bits, pos, name, truncated)
if ~canTake(bits, pos, 1)
    s.(name) = false;
    truncated = true;
    return;
end
s.(name) = bits(pos);
pos = pos + 1;
end

function [s, pos, truncated] = takeIntField(s, bits, pos, name, width, truncated)
if ~canTake(bits, pos, width)
    s.(name) = NaN;
    truncated = true;
    return;
end
s.(name) = tetra.bitsToInt(bits(pos:pos + width - 1));
pos = pos + width;
end

function [s, pos] = takeOptionalBitField(s, bits, pos, name)
if canTake(bits, pos, 1)
    s.(name) = bits(pos);
    pos = pos + 1;
else
    s.(name) = false;
end
end

function yes = canTake(bits, pos, width)
yes = pos + width - 1 <= numel(bits);
end

function yes = flagTrue(s, name)
yes = isfield(s, name) && islogical(s.(name)) && isscalar(s.(name)) && s.(name);
end

function value = getField(s, name)
if isfield(s, name)
    value = s.(name);
else
    value = NaN;
end
end

function txt = messageTypeText(value)
switch value
    case 0
        txt = 'DM-RESERVED';
    case 1
        txt = 'DM-SDS OCCUPIED';
    case 2
        txt = 'DM-TIMING REQUEST';
    case 3
        txt = 'DM-TIMING ACK';
    case 8
        txt = 'DM-SETUP';
    case 9
        txt = 'DM-SETUP PRES';
    case 10
        txt = 'DM-CONNECT';
    case 11
        txt = 'DM-DISCONNECT';
    case 12
        txt = 'DM-CONNECT ACK';
    case 13
        txt = 'DM-OCCUPIED';
    case 14
        txt = 'DM-RELEASE';
    case 15
        txt = 'DM-TX CEASED';
    case 16
        txt = 'DM-TX REQUEST';
    case 17
        txt = 'DM-TX ACCEPT';
    case 18
        txt = 'DM-PREEMPT';
    case 19
        txt = 'DM-PRE ACCEPT';
    case 20
        txt = 'DM-REJECT';
    case 21
        txt = 'DM-INFO';
    case 22
        txt = 'DM-SDS UDATA';
    case 23
        txt = 'DM-SDS DATA';
    case 24
        txt = 'DM-SDS ACK';
    otherwise
        if value >= 4 && value <= 7
            txt = 'reserved';
        elseif value == 25
            txt = 'gateway-specific';
        elseif value >= 30 && value <= 31
            txt = 'proprietary';
        else
            txt = 'reserved';
        end
end
end

function txt = circuitModeTypeText(value)
switch value
    case 0
        txt = 'TETRA encoded speech';
    case 1
        txt = 'TCH/7.2 data';
    case 2
        txt = 'TCH/4.8 data, N=1';
    case 3
        txt = 'TCH/4.8 data, N=4';
    case 4
        txt = 'TCH/4.8 data, N=8';
    case 5
        txt = 'TCH/2.4 data, N=1';
    case 6
        txt = 'TCH/2.4 data, N=4';
    case 7
        txt = 'TCH/2.4 data, N=8';
    case 8
        txt = 'proprietary encoded speech';
    otherwise
        txt = 'reserved';
end
end

function txt = powerClassText(value)
switch value
    case 0
        txt = 'class 0';
    case 1
        txt = 'class 1';
    case 2
        txt = 'class 2';
    case 3
        txt = 'class 3';
    case 4
        txt = 'class 4';
    otherwise
        txt = 'reserved';
end
end

function txt = causeText(value, prefix)
if isnan(value)
    txt = 'unknown';
else
    txt = sprintf('%s cause %d', prefix, value);
end
end
