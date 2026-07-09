function [session, callPdu] = sessionFeed(session, pdu, sps)
%SESSIONFEED Feed one DMR signalling PDU into the call summary state.
if nargin < 3 || isempty(sps)
    sps = dmr.config().samplesPerSymbol;
end
callPdu = [];
ptype = char(radio.getField(pdu, 'type', ''));
if ~any(strcmp(ptype, {'LC_HEADER', 'LATE_ENTRY', 'TERMINATOR', 'CSBK'}))
    return;
end

if strcmp(ptype, 'TERMINATOR')
    if ~session.active
        return;
    end
    session = updateSession(session, pdu);
    callPdu = emitCall(session, pdu, sps, 'terminator');
    session = dmr.sessionInit();
    return;
end

if any(strcmp(ptype, {'LC_HEADER', 'LATE_ENTRY'}))
    if ~session.active
        session.active = true;
        session.firstSample = sampleOf(pdu);
    end
    session = updateSession(session, pdu);
    if strcmp(ptype, 'LATE_ENTRY')
        session.lateEntryCount = session.lateEntryCount + 1;
    end
elseif strcmp(ptype, 'CSBK')
    session.csbkCount = session.csbkCount + 1;
    if ~session.active && (nonzero(radio.getField(pdu, 'src', 0)) || nonzero(radio.getField(pdu, 'dst', 0)))
        session.active = true;
        session.firstSample = sampleOf(pdu);
        session = updateSession(session, pdu);
    end
end

session.signallingCount = session.signallingCount + 1;
end

function session = updateSession(session, pdu)
sample = sampleOf(pdu);
if ~isempty(sample)
    if isempty(session.firstSample)
        session.firstSample = sample;
    end
    session.lastSample = sample;
end
src = radio.getField(pdu, 'src', 0);
dst = radio.getField(pdu, 'dst', 0);
if nonzero(src)
    session.src = src;
end
if nonzero(dst)
    session.dst = dst;
end
flco = radio.getField(pdu, 'flco', '');
fid = radio.getField(pdu, 'fid', '');
if ~isempty(flco)
    session.flco = char(flco);
end
if ~isempty(fid)
    session.fid = char(fid);
end
colorCode = radio.getNestedField(pdu, 'extra.color_code', []);
if ~isempty(colorCode)
    session.colorCode = colorCode;
end
callType = radio.getNestedField(pdu, 'extra.flc.call_type', '');
if isempty(callType)
    callType = inferCallType(session.flco);
end
if ~isempty(callType)
    session.callType = char(callType);
end
end

function pdu = emitCall(session, lastPdu, sps, closedBy)
first = valueOr(session.firstSample, 0);
last = valueOr(session.lastSample, first);
duration = max(0, double(last - first) / (double(sps) * dmr.config().symbolRateHz));
extra = struct();
extra.call_type = session.callType;
extra.color_code = session.colorCode;
extra.start_sample = session.firstSample;
extra.end_sample = session.lastSample;
extra.duration_s = round(duration, 3);
extra.signalling_count = session.signallingCount;
extra.late_entry_count = session.lateEntryCount;
extra.csbk_count = session.csbkCount;
extra.closed_by = closedBy;
if ~isempty(lastPdu)
    extra.last_data_type_name = radio.getNestedField(lastPdu, 'extra.data_type_name', '');
    extra.last_sync_type = radio.getNestedField(lastPdu, 'extra.sync_type', '');
end
pdu = struct( ...
    'protocol', 'DMR', ...
    'type', 'DMR_CALL', ...
    'src', session.src, ...
    'dst', session.dst, ...
    'ts', 0, ...
    'flco', session.flco, ...
    'fid', session.fid, ...
    'extra', extra, ...
    'raw_bits', []);
end

function sample = sampleOf(pdu)
sample = radio.getNestedField(pdu, 'extra.fs_start', []);
if ~isempty(sample)
    sample = double(sample);
end
end

function yes = nonzero(value)
yes = isnumeric(value) && isscalar(value) && value ~= 0;
end

function value = valueOr(value, defaultValue)
if isempty(value)
    value = defaultValue;
end
end

function text = inferCallType(flco)
switch char(flco)
    case 'GroupVoiceChannelUser'
        text = 'group';
    case 'UnitToUnitVoiceChannelUser'
        text = 'unit_to_unit';
    otherwise
        text = '';
end
end
