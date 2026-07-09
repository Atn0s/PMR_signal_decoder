function pdus = pdusFromSlotReport(slotReport, cfg, context)
%PDUSFROMSLOTREPORT Convert decoded DMO bursts into shared radio PDU structs.
if nargin < 2 || isempty(cfg)
    cfg = tetra.config();
end
if nargin < 3 || isempty(context)
    context = struct();
end

pdus = repmat(emptyPdu(), 0, 1);
if ~isfield(slotReport, 'bursts') || isempty(slotReport.bursts)
    return;
end

bursts = slotReport.bursts;
for k = 1:numel(bursts)
    b = bursts(k);
    if isfield(b, 'dmacSyncOk') && b.dmacSyncOk && ~isempty(b.dmacSync)
        pdus = appendPdu(pdus, syncPdu(b, context, cfg));
    end
    if isfield(b, 'macBlocks') && ~isempty(b.macBlocks)
        for m = 1:numel(b.macBlocks)
            mb = b.macBlocks(m);
            if mb.decodeOk
                pdus = appendPdu(pdus, macPdu(b, mb, context, cfg));
            elseif strcmp(mb.logicalChannel, 'SCH/F') || strcmp(mb.logicalChannel, 'TCH')
                if getCfg(cfg, 'scanEmitTchCandidates', true)
                    pdus = appendPdu(pdus, tchCandidatePdu(b, mb, context, cfg));
                end
            end
        end
    end
end

sessions = sessionPdus(pdus);
for k = 1:numel(sessions)
    pdus = appendPdu(pdus, sessions(k));
end
end

function pdu = syncPdu(burst, context, cfg)
sync = burst.dmacSync;
src = zeroIfNan(sync.sourceAddress);
dst = zeroIfNan(sync.destinationAddress);
extra = baseExtra(burst, context, cfg);
extra.logical_channel = sync.logicalChannel;
extra.pdu_name = sync.syncPduTypeText;
extra.message_type = sync.messageType;
extra.message_type_text = sync.messageTypeText;
extra.system_code = sync.systemCode;
extra.system_code_text = sync.systemCodeText;
extra.communication_type = sync.communicationType;
extra.communication_type_text = sync.communicationTypeText;
extra.ab_channel_usage = sync.abChannelUsage;
extra.ab_channel_usage_text = sync.abChannelUsageText;
extra.air_interface_encryption_state = sync.airInterfaceEncryptionState;
extra.air_interface_encryption_state_text = sync.airInterfaceEncryptionStateText;
extra.source_address_type = sync.sourceAddressType;
extra.source_address_type_text = sync.sourceAddressTypeText;
extra.destination_address_type = sync.destinationAddressType;
extra.destination_address_type_text = sync.destinationAddressTypeText;
extra.mni = sync.mobileNetworkIdentity;
extra.frame_countdown = sync.frameCountdown;
extra.frame_countdown_text = sync.frameCountdownText;
extra.fragmentation_flag = sync.fragmentationFlag;
extra.number_of_schf_slots = sync.numberOfSchFSlots;
extra.fill_bit_indication = sync.fillBitIndication;
extra.dcc_valid = sync.dccValid;
extra.dcc = sync.dccText;
extra.message_dependent = sync.message.messageDependent;
extra.dm_sdu = sync.message.dmSdu;
extra.sch_s_block_errors = burst.schS.blockCodeErrors;
extra.sch_s_tail_errors = burst.schS.tailErrors;
extra.sch_h_block_errors = burst.schH.blockCodeErrors;
extra.sch_h_tail_errors = burst.schH.tailErrors;
extra.service = serviceText(sync.message);
pdu = makePdu('TETRA_DMAC_SYNC', src, dst, burst.slotNumber, sync.messageTypeText, extra, ...
    syncBits(sync));
end

function pdu = macPdu(burst, block, context, cfg)
mp = block.pdu;
src = pduAddress(mp, 'sourceAddress', burst);
dst = pduAddress(mp, 'destinationAddress', burst);
msgText = fieldOr(mp, 'messageTypeText', fieldOr(mp, 'pduName', ''));
if fieldOr(mp, 'nullPduFlag', false)
    msgText = 'NULL';
end
if strcmp(block.logicalChannel, 'SCH/F')
    typ = 'TETRA_SCHF';
else
    typ = 'TETRA_STCH';
end
extra = baseExtra(burst, context, cfg);
extra.logical_channel = block.logicalChannel;
extra.block_name = block.blockName;
extra.block_start_bit = block.absoluteStartBit;
extra.block_end_bit = block.absoluteEndBit;
extra.pdu_name = fieldOr(mp, 'pduName', '');
extra.mac_pdu_type = fieldOr(mp, 'macPduType', NaN);
extra.mac_pdu_type_text = fieldOr(mp, 'macPduTypeText', '');
extra.message_type = fieldOr(mp, 'messageType', NaN);
extra.message_type_text = msgText;
extra.second_half_slot_stolen = fieldOr(mp, 'secondHalfSlotStolenFlag', false);
extra.null_pdu = fieldOr(mp, 'nullPduFlag', false);
extra.fragmentation_flag = fieldOr(mp, 'fragmentationFlag', false);
extra.frame_countdown = fieldOr(mp, 'frameCountdown', NaN);
extra.frame_countdown_text = fieldOr(mp, 'frameCountdownText', '');
extra.air_interface_encryption_state = fieldOr(mp, 'airInterfaceEncryptionState', NaN);
extra.air_interface_encryption_state_text = fieldOr(mp, 'airInterfaceEncryptionStateText', '');
extra.mni = fieldOr(mp, 'mobileNetworkIdentity', contextMni(burst));
extra.context_source_slot_start_bit = block.contextSourceSlotStartBit;
extra.context_message_type_text = block.contextMessageTypeText;
extra.block_code_errors = block.blockCodeErrors;
extra.tail_errors = block.tailErrors;
extra.rcpc_metric = block.rcpcMetric;
extra.block_valid_bit_count = fieldOr(block, 'validBitCount', 0);
extra.block_invalid_bit_count = fieldOr(block, 'invalidBitCount', 0);
extra.block_valid_ratio = fieldOr(block, 'validRatio', NaN);
if isfield(mp, 'message')
    extra.message_dependent = mp.message.messageDependent;
    extra.dm_sdu = mp.message.dmSdu;
else
    extra.message_dependent = struct();
    extra.dm_sdu = struct();
end
if isfield(mp, 'uPlaneDmSduBitCount')
    extra.u_plane_dm_sdu_bit_count = mp.uPlaneDmSduBitCount;
end
if isfield(mp, 'dmSduBitCount')
    extra.dm_sdu_bit_count = mp.dmSduBitCount;
end
pdu = makePdu(typ, src, dst, burst.slotNumber, msgText, extra, decodedBits(block));
end

function pdu = tchCandidatePdu(burst, block, context, cfg)
ctx = burst.dmoContext;
src = zeroIfNan(fieldOr(ctx, 'sourceAddress', 0));
dst = zeroIfNan(fieldOr(ctx, 'destinationAddress', 0));
extra = baseExtra(burst, context, cfg);
extra.logical_channel = 'TCH';
extra.block_name = block.blockName;
extra.block_start_bit = block.absoluteStartBit;
extra.block_end_bit = block.absoluteEndBit;
extra.status = block.status;
extra.schf_attempted = strcmp(block.logicalChannel, 'SCH/F');
extra.schf_block_code_errors = block.blockCodeErrors;
extra.schf_tail_errors = block.tailErrors;
extra.schf_rcpc_metric = block.rcpcMetric;
extra.context_source_slot_start_bit = block.contextSourceSlotStartBit;
extra.context_message_type_text = block.contextMessageTypeText;
extra.mni = fieldOr(ctx, 'mobileNetworkIdentity', NaN);
extra.dcc = fieldOr(ctx, 'dccText', '');
extra.service = contextService(ctx);
extra.block_valid_bit_count = fieldOr(block, 'validBitCount', 0);
extra.block_invalid_bit_count = fieldOr(block, 'invalidBitCount', 0);
extra.block_valid_ratio = fieldOr(block, 'validRatio', NaN);
pdu = makePdu('TETRA_TCH_CANDIDATE', src, dst, burst.slotNumber, 'TCH', extra, []);
end

function extra = baseExtra(burst, context, cfg)
extra = struct();
extra.mode = 'DMO';
extra.burst_type = burst.burstType;
extra.training_name = burst.trainingName;
extra.frame_number = burst.frameNumber;
extra.slot_number = burst.slotNumber;
extra.timing_label = burst.timingLabel;
extra.slot_start_bit = burst.slotStartBit;
extra.slot_end_bit = burst.slotEndBit;
extra.start_time_s = bitTimeSec(burst.slotStartBit, context, cfg);
extra.end_time_s = bitTimeSec(burst.slotEndBit, context, cfg);
extra.active_start_s = fieldOr(context, 'activeStartSec', NaN);
extra.active_end_s = fieldOr(context, 'activeEndSec', NaN);
extra.decision_variant = fieldOr(context, 'decisionVariant', '');
extra.timing_phase_samples = fieldOr(context, 'timingPhaseSamples', NaN);
extra.timing_error_rad = fieldOr(context, 'timingErrorRad', NaN);
extra.coarse_frequency_offset_hz = fieldOr(context, 'coarseFrequencyOffsetHz', NaN);
extra.residual_correction_hz = fieldOr(context, 'residualCorrectionHz', NaN);
extra.valid_bit_count = fieldOr(burst, 'validBitCount', 0);
extra.invalid_bit_count = fieldOr(burst, 'invalidBitCount', 0);
extra.valid_transition_ratio = fieldOr(burst, 'validBitRatio', NaN);
end

function sessions = sessionPdus(pdus)
sessions = repmat(emptyPdu(), 0, 1);
session = emptySession();
for k = 1:numel(pdus)
    p = pdus(k);
    typ = char(p.type);
    msg = char(p.flco);
    if strcmp(typ, 'TETRA_TCH_CANDIDATE')
        if session.active
            session.tchCandidateCount = session.tchCandidateCount + 1;
            session.lastTime = radio.getNestedField(p, 'extra.end_time_s', session.lastTime);
            session.endBit = radio.getNestedField(p, 'extra.slot_end_bit', session.endBit);
        end
        continue;
    end
    if ~startsWith(typ, 'TETRA_') || strcmp(typ, 'TETRA_SESSION')
        continue;
    end

    startsSession = any(strcmp(msg, {'DM-SETUP', 'DM-OCCUPIED'}));
    endsSession = any(strcmp(msg, {'DM-RELEASE', 'DM-TX CEASED'}));
    src = radio.getField(p, 'src', 0);
    dst = radio.getField(p, 'dst', 0);
    if startsSession
        if session.active && (session.src ~= src || session.dst ~= dst)
            sessions = appendPdu(sessions, sessionToPdu(session, sessionState(session, 'closed_by_new_session')));
            session = emptySession();
        end
        if ~session.active
            session = startSession(p);
        end
    end
    if session.active
        session = updateSession(session, p);
    elseif startsSession
        session = startSession(p);
    end
    if endsSession && session.active
        session.releaseMessage = msg;
    end
end
if session.active
    sessions = appendPdu(sessions, sessionToPdu(session, sessionState(session, 'open')));
end
end

function session = emptySession()
session = struct( ...
    'active', false, ...
    'src', 0, ...
    'dst', 0, ...
    'mni', NaN, ...
    'dcc', '', ...
    'startTime', NaN, ...
    'lastTime', NaN, ...
    'startBit', NaN, ...
    'endBit', NaN, ...
    'startFrame', NaN, ...
    'startSlot', NaN, ...
    'endFrame', NaN, ...
    'endSlot', NaN, ...
    'syncEventCount', 0, ...
    'stchEventCount', 0, ...
    'controlEventCount', 0, ...
    'tchCandidateCount', 0, ...
    'releaseMessage', '', ...
    'service', '');
end

function session = startSession(pdu)
session = emptySession();
session.active = true;
session.src = radio.getField(pdu, 'src', 0);
session.dst = radio.getField(pdu, 'dst', 0);
session.mni = radio.getNestedField(pdu, 'extra.mni', NaN);
session.dcc = radio.getNestedField(pdu, 'extra.dcc', '');
session.startTime = radio.getNestedField(pdu, 'extra.start_time_s', NaN);
session.lastTime = radio.getNestedField(pdu, 'extra.end_time_s', session.startTime);
session.startBit = radio.getNestedField(pdu, 'extra.slot_start_bit', NaN);
session.endBit = radio.getNestedField(pdu, 'extra.slot_end_bit', session.startBit);
session.startFrame = radio.getNestedField(pdu, 'extra.frame_number', NaN);
session.startSlot = radio.getNestedField(pdu, 'extra.slot_number', NaN);
session.endFrame = session.startFrame;
session.endSlot = session.startSlot;
session.service = radio.getNestedField(pdu, 'extra.service', '');
end

function session = updateSession(session, pdu)
typ = char(pdu.type);
if strcmp(typ, 'TETRA_DMAC_SYNC')
    session.syncEventCount = session.syncEventCount + 1;
elseif strcmp(typ, 'TETRA_STCH') || strcmp(typ, 'TETRA_SCHF')
    session.stchEventCount = session.stchEventCount + strcmp(typ, 'TETRA_STCH');
end
session.controlEventCount = session.controlEventCount + 1;
session.lastTime = radio.getNestedField(pdu, 'extra.end_time_s', session.lastTime);
session.endBit = radio.getNestedField(pdu, 'extra.slot_end_bit', session.endBit);
session.endFrame = radio.getNestedField(pdu, 'extra.frame_number', session.endFrame);
session.endSlot = radio.getNestedField(pdu, 'extra.slot_number', session.endSlot);
if isempty(session.service)
    session.service = radio.getNestedField(pdu, 'extra.service', '');
end
end

function pdu = sessionToPdu(session, state)
extra = struct();
extra.mode = 'DMO';
extra.state = state;
extra.start_time_s = session.startTime;
extra.end_time_s = session.lastTime;
extra.duration_s = session.lastTime - session.startTime;
extra.start_bit = session.startBit;
extra.end_bit = session.endBit;
extra.start_frame_number = session.startFrame;
extra.start_slot_number = session.startSlot;
extra.end_frame_number = session.endFrame;
extra.end_slot_number = session.endSlot;
extra.mni = session.mni;
extra.dcc = session.dcc;
extra.sync_event_count = session.syncEventCount;
extra.stch_event_count = session.stchEventCount;
extra.control_event_count = session.controlEventCount;
extra.tch_candidate_count = session.tchCandidateCount;
extra.release_message = session.releaseMessage;
extra.service = session.service;
pdu = makePdu('TETRA_SESSION', session.src, session.dst, [], 'DMO_SESSION', extra, []);
end

function state = sessionState(session, fallbackState)
if ~isempty(session.releaseMessage)
    state = 'closed';
else
    state = fallbackState;
end
end

function pdu = makePdu(typeName, src, dst, ts, flco, extra, rawBits)
pdu = emptyPdu();
pdu.protocol = 'TETRA';
pdu.type = typeName;
pdu.src = src;
pdu.dst = dst;
pdu.ts = ts;
pdu.flco = flco;
pdu.fid = '';
pdu.extra = extra;
pdu.raw_bits = rawBits;
end

function pdu = emptyPdu()
pdu = struct( ...
    'protocol', '', ...
    'type', '', ...
    'src', 0, ...
    'dst', 0, ...
    'ts', [], ...
    'flco', '', ...
    'fid', '', ...
    'extra', struct(), ...
    'raw_bits', []);
end

function out = appendPdu(out, pdu)
if isempty(out)
    out = pdu;
else
    out(end+1, 1) = pdu;
end
end

function sec = bitTimeSec(bitIndex, context, cfg)
activeStart = fieldOr(context, 'activeStartSec', 0);
if isnan(bitIndex)
    sec = NaN;
else
    sec = activeStart + max(0, double(bitIndex) - 1) / (2 * cfg.symbolRateHz);
end
end

function value = pduAddress(pdu, name, burst)
value = fieldOr(pdu, name, NaN);
if isnan(value) && isfield(burst, 'dmoContext') && ~isempty(burst.dmoContext)
    if strcmp(name, 'sourceAddress')
        value = fieldOr(burst.dmoContext, 'sourceAddress', NaN);
    else
        value = fieldOr(burst.dmoContext, 'destinationAddress', NaN);
    end
end
value = zeroIfNan(value);
end

function value = contextMni(burst)
value = NaN;
if isfield(burst, 'dmoContext') && ~isempty(burst.dmoContext)
    value = fieldOr(burst.dmoContext, 'mobileNetworkIdentity', NaN);
end
end

function text = contextService(ctx)
text = '';
if isfield(ctx, 'service') && ~isempty(ctx.service)
    text = char(ctx.service);
elseif isfield(ctx, 'messageTypeText')
    text = char(ctx.messageTypeText);
end
end

function text = serviceText(message)
text = '';
if isfield(message, 'messageDependent')
    md = message.messageDependent;
    if isfield(md, 'circuitModeTypeText')
        text = md.circuitModeTypeText;
    end
end
end

function bits = syncBits(sync)
bits = [sync.schS.rawBits(:); sync.schH.rawBits(:)];
end

function bits = decodedBits(block)
if isfield(block, 'decoded') && ~isempty(block.decoded)
    bits = block.decoded.type1Bits(:);
else
    bits = [];
end
end

function value = fieldOr(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end

function value = zeroIfNan(value)
if isnumeric(value) && isscalar(value) && isnan(value)
    value = 0;
end
end

function value = getCfg(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
