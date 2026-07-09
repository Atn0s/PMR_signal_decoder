function [session, callPdu] = callSessionFeed(session, pdu, sps)
%CALLSESSIONFEED Feed one CCH-bearing dPMR PDU into call aggregation state.
if nargin < 3 || isempty(sps)
    sps = dpmr.config().samplesPerSymbol;
end
callPdu = [];
ptype = char(radio.getField(pdu, 'type', ''));
if ~any(strcmp(ptype, {'DPMR_HEADER', 'DPMR_VOICE'}))
    return;
end

if session.active && shouldSplit(session, pdu)
    callPdu = emitCall(session, sps, 'new_session');
    session = dpmr.callSessionInit();
end

if ~session.active
    session.active = true;
    session.firstSample = sampleOf(pdu);
end
session = updateSession(session, pdu);
end

function yes = shouldSplit(session, pdu)
yes = false;
cc = radio.getNestedField(pdu, 'extra.color_code', []);
if ~isempty(cc) && ~isempty(session.colorCode) && double(cc) ~= double(session.colorCode)
    yes = true;
    return;
end
src = char(string(radio.getField(pdu, 'src', '')));
dst = char(string(radio.getField(pdu, 'dst', '')));
yes = ~isempty(session.src) && ~isempty(session.dst) && ...
    ~isempty(src) && ~isempty(dst) && ...
    (~strcmp(src, session.src) || ~strcmp(dst, session.dst));
end

function session = updateSession(session, pdu)
sample = sampleOf(pdu);
if ~isempty(sample)
    if isempty(session.firstSample)
        session.firstSample = sample;
    end
    session.lastSample = sample;
end
ptype = char(radio.getField(pdu, 'type', ''));
if strcmp(ptype, 'DPMR_HEADER')
    session.headerCount = session.headerCount + 1;
elseif strcmp(ptype, 'DPMR_VOICE')
    session.voiceCount = session.voiceCount + 1;
end

src = char(string(radio.getField(pdu, 'src', '')));
dst = char(string(radio.getField(pdu, 'dst', '')));
if ~isempty(src)
    session.src = src;
end
if ~isempty(dst)
    session.dst = dst;
end

cc = radio.getNestedField(pdu, 'extra.color_code', []);
if ~isempty(cc) && double(cc) >= 0
    session.colorCode = cc;
end
syncType = radio.getNestedField(pdu, 'extra.sync_type', '');
if ~isempty(syncType)
    session.syncTypes = addUniqueText(session.syncTypes, syncType);
end
part = radio.getNestedField(pdu, 'extra.superframe_part', '');
if ~isempty(part)
    session.superframeParts = addUniqueText(session.superframeParts, part);
end

cch = radio.getNestedField(pdu, 'extra.cch', []);
if isstruct(cch)
    for k = 1:numel(cch)
        session = storeRecord(session, cch(k));
    end
end
[src2, dst2] = assembledIds(session.records);
if ~isempty(src2)
    session.src = src2;
end
if ~isempty(dst2)
    session.dst = dst2;
end
end

function session = storeRecord(session, rec)
if ~fieldOr(rec, 'crc_ok', false) && ~fieldOr(rec, 'hamming_ok', false)
    return;
end
session.cchCount = session.cchCount + 1;
fn = fieldOr(rec, 'frame_number', []);
if isempty(fn)
    return;
end
idx = find(arrayfun(@(r) fieldOr(r, 'frame_number', NaN) == fn, session.records), 1);
if isempty(idx)
    session.records = appendRecord(session.records, rec);
elseif fieldOr(rec, 'crc_ok', false) && ~fieldOr(session.records(idx), 'crc_ok', false)
    session.records(idx) = rec;
end
session.communicationModes = addUniqueNumber(session.communicationModes, fieldOr(rec, 'communication_mode', []));
session.versions = addUniqueNumber(session.versions, fieldOr(rec, 'version', []));
session.commsFormats = addUniqueNumber(session.commsFormats, fieldOr(rec, 'comms_format', []));
session.emergencyPriorities = addUniqueNumber(session.emergencyPriorities, fieldOr(rec, 'emergency_priority', []));
end

function callPdu = emitCall(session, sps, closedBy)
first = valueOr(session.firstSample, 0);
last = valueOr(session.lastSample, first);
duration = max(0, double(last - first) / (double(sps) * dpmr.config().symbolRateHz));
extra = struct();
extra.color_code = session.colorCode;
extra.start_sample = session.firstSample;
extra.end_sample = session.lastSample;
extra.duration_s = round(duration, 3);
extra.header_count = session.headerCount;
extra.voice_count = session.voiceCount;
extra.cch_count = session.cchCount;
extra.sync_types = session.syncTypes;
extra.superframe_parts = session.superframeParts;
extra.communication_modes = session.communicationModes;
extra.versions = session.versions;
extra.comms_formats = session.commsFormats;
extra.emergency_priorities = session.emergencyPriorities;
extra.closed_by = closedBy;
if session.voiceCount > 0
    flco = 'VOICE';
else
    flco = 'HEADER';
end
callPdu = struct('protocol', 'dPMR', 'type', 'dPMR_CALL', ...
    'src', session.src, 'dst', session.dst, 'ts', 0, 'flco', flco, ...
    'fid', '', 'extra', extra, 'raw_bits', []);
end

function [src, dst] = assembledIds(records)
src = '';
dst = '';
dst = assemblePair(records, 0, 1);
src = assemblePair(records, 2, 3);
end

function text = assemblePair(records, first, second)
text = '';
if isempty(records)
    return;
end
aIdx = find(arrayfun(@(r) fieldOr(r, 'frame_number', NaN) == first, records), 1);
bIdx = find(arrayfun(@(r) fieldOr(r, 'frame_number', NaN) == second, records), 1);
if isempty(aIdx) || isempty(bIdx)
    return;
end
if ~fieldOr(records(aIdx), 'crc_ok', false) || ~fieldOr(records(bIdx), 'crc_ok', false)
    return;
end
value = bitor(bitshift(uint32(fieldOr(records(aIdx), 'id_half', 0)), 12), ...
    uint32(fieldOr(records(bIdx), 'id_half', 0)));
text = dpmr.airInterfaceIdToStr(bitand(value, uint32(hex2dec('FFFFFF'))));
end

function sample = sampleOf(pdu)
sample = radio.getNestedField(pdu, 'extra.fs_start', []);
if ~isempty(sample)
    sample = double(sample);
end
end

function records = appendRecord(records, rec)
if isempty(records)
    records = rec;
else
    records(end+1) = rec;
end
end

function values = addUniqueText(values, value)
text = char(string(value));
if isempty(values) || ~any(strcmp(values, text))
    values{end+1} = text;
end
end

function values = addUniqueNumber(values, value)
if isempty(value)
    return;
end
value = double(value);
if isempty(values) || ~any(values == value)
    values(end+1) = value;
end
end

function value = valueOr(value, defaultValue)
if isempty(value)
    value = defaultValue;
end
end

function value = fieldOr(s, name, defaultValue)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = defaultValue;
end
end
