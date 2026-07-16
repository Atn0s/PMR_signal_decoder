function [state, summaries] = sessionDecoderFeed(state, pdus)
%SESSIONDECODERFEED Advance a TETRA DMO session with new time-ordered PDUs.
if state.finalized
    error('tetra:sessionDecoderFeed:Finalized', ...
        'Cannot feed a finalized TETRA session decoder.');
end
pdus = sortByTime(radio.normalizePdus(pdus));
summaries = struct([]);
for k = 1:numel(pdus)
    pdu = pdus(k);
    typ = char(pdu.type);
    message = char(pdu.flco);
    if strcmp(typ, 'TETRA_TCH_CANDIDATE')
        if state.session.active
            state.session.tchCandidateCount = ...
                state.session.tchCandidateCount + 1;
            state.session.lastTime = radio.getNestedField( ...
                pdu, 'extra.end_time_s', state.session.lastTime);
            state.session.endBit = radio.getNestedField( ...
                pdu, 'extra.slot_end_bit', state.session.endBit);
        end
        continue;
    end
    if ~startsWith(typ, 'TETRA_') || strcmp(typ, 'TETRA_SESSION')
        continue;
    end

    startsSession = any(strcmp(message, {'DM-SETUP', 'DM-OCCUPIED'}));
    endsSession = any(strcmp(message, ...
        {'DM-RELEASE', 'DM-TX CEASED'}));
    src = radio.getField(pdu, 'src', 0);
    dst = radio.getField(pdu, 'dst', 0);
    if startsSession
        if state.session.active && ...
                (state.session.src ~= src || state.session.dst ~= dst)
            summaries = appendPdu(summaries, ...
                tetra.sessionDecoderPdu( ...
                    state.session, 'closed_by_new_session'));
            fresh = tetra.sessionDecoderInit();
            state.session = fresh.session;
        end
        if ~state.session.active
            state.session = startSession(pdu);
        end
    end
    if state.session.active
        state.session = updateSession(state.session, pdu);
    elseif startsSession
        state.session = startSession(pdu);
    end
    if endsSession && state.session.active
        state.session.releaseMessage = message;
    end
end
summaries = radio.normalizePdus(summaries);
end

function pdus = sortByTime(pdus)
if isempty(pdus), return; end
times = NaN(numel(pdus), 1);
for k = 1:numel(pdus)
    times(k) = radio.getNestedField(pdus(k), 'extra.start_time_s', ...
        radio.getNestedField(pdus(k), 'extra.end_time_s', k));
end
[~, order] = sort(times);
pdus = pdus(order);
end

function session = startSession(pdu)
fresh = tetra.sessionDecoderInit();
session = fresh.session;
session.active = true;
session.src = radio.getField(pdu, 'src', 0);
session.dst = radio.getField(pdu, 'dst', 0);
session.mni = radio.getNestedField(pdu, 'extra.mni', NaN);
session.dcc = radio.getNestedField(pdu, 'extra.dcc', '');
session.startTime = radio.getNestedField( ...
    pdu, 'extra.start_time_s', NaN);
session.lastTime = radio.getNestedField( ...
    pdu, 'extra.end_time_s', session.startTime);
session.startBit = radio.getNestedField( ...
    pdu, 'extra.slot_start_bit', NaN);
session.endBit = radio.getNestedField( ...
    pdu, 'extra.slot_end_bit', session.startBit);
session.startFrame = radio.getNestedField( ...
    pdu, 'extra.frame_number', NaN);
session.startSlot = radio.getNestedField( ...
    pdu, 'extra.slot_number', NaN);
session.endFrame = session.startFrame;
session.endSlot = session.startSlot;
session.service = radio.getNestedField(pdu, 'extra.service', '');
end

function session = updateSession(session, pdu)
typ = char(pdu.type);
if strcmp(typ, 'TETRA_DMAC_SYNC')
    session.syncEventCount = session.syncEventCount + 1;
elseif strcmp(typ, 'TETRA_STCH') || strcmp(typ, 'TETRA_SCHF')
    session.stchEventCount = session.stchEventCount + ...
        strcmp(typ, 'TETRA_STCH');
end
session.controlEventCount = session.controlEventCount + 1;
session.lastTime = radio.getNestedField( ...
    pdu, 'extra.end_time_s', session.lastTime);
session.endBit = radio.getNestedField( ...
    pdu, 'extra.slot_end_bit', session.endBit);
session.endFrame = radio.getNestedField( ...
    pdu, 'extra.frame_number', session.endFrame);
session.endSlot = radio.getNestedField( ...
    pdu, 'extra.slot_number', session.endSlot);
if isempty(session.service)
    session.service = radio.getNestedField(pdu, 'extra.service', '');
end
end

function values = appendPdu(values, pdu)
if isempty(pdu), return; end
if isempty(values), values = pdu; else, values(end+1) = pdu; end
end
