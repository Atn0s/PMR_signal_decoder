function sessions = sessionizePdus(pdus)
%SESSIONIZEPDUS Build DMO session summaries from time-ordered TETRA events.
pdus = radio.normalizePdus(pdus);
pdus = sortByTime(pdus);
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

function pdus = sortByTime(pdus)
if isempty(pdus)
    return;
end
t = NaN(numel(pdus), 1);
for k = 1:numel(pdus)
    t(k) = radio.getNestedField(pdus(k), 'extra.start_time_s', ...
        radio.getNestedField(pdus(k), 'extra.end_time_s', k));
end
[~, order] = sort(t);
pdus = pdus(order);
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
pdu = emptyPdu();
pdu.protocol = 'TETRA';
pdu.type = 'TETRA_SESSION';
pdu.src = session.src;
pdu.dst = session.dst;
pdu.ts = [];
pdu.flco = 'DMO_SESSION';
pdu.fid = '';
pdu.extra = extra;
pdu.raw_bits = [];
end

function state = sessionState(session, fallbackState)
if ~isempty(session.releaseMessage)
    state = 'closed';
else
    state = fallbackState;
end
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
