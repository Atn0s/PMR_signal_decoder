function [session, callPdu] = sessionFeed(session, pdu, cfg)
%SESSIONFEED Feed an NXDN signalling PDU into call summary state.
if nargin < 3 || isempty(cfg), cfg = nxdn.config(); end
callPdu = [];
ptype = char(radio.getField(pdu, 'type', ''));
sample = radio.getNestedField(pdu, 'extra.fs_start', []);
if strcmp(ptype, 'NXDN_VCALL')
    if ~session.active
        session.active = true;
        session.first_sample = sample;
    end
    session.src = radio.getField(pdu, 'src', session.src);
    session.dst = radio.getField(pdu, 'dst', session.dst);
    session.call_type = radio.getNestedField(pdu, 'extra.call_type', session.call_type);
    session.ran = radio.getNestedField(pdu, 'extra.ran', session.ran);
    session.last_sample = sample;
    session.message_count = session.message_count + 1;
elseif strcmp(ptype, 'NXDN_PROP_ALIAS') && session.active
    part = radio.getNestedField(pdu, 'extra.alias_segment', 0);
    total = radio.getNestedField(pdu, 'extra.alias_total', 0);
    bytes = radio.getNestedField(pdu, 'extra.alias_bytes', []);
    if part >= 1 && total >= part
        if numel(session.alias_parts) < total
            session.alias_parts{total} = [];
        end
        session.alias_parts{part} = bytes;
        session.alias_total = total;
        session.alias = assembleAlias(session.alias_parts, total);
    end
    session.last_sample = sample;
elseif any(strcmp(ptype, {'NXDN_TX_REL', 'NXDN_TX_REL_EX', 'NXDN_DISC'}))
    if session.active
        session.last_sample = sample;
        callPdu = emitCall(session, pdu, cfg, ptype);
        session = nxdn.sessionInit();
    end
end
end

function alias = assembleAlias(parts, total)
bytes = [];
for k = 1:min(total, numel(parts))
    bytes = [bytes parts{k}]; %#ok<AGROW>
end
bytes = bytes(bytes >= 32 & bytes <= 126);
alias = strtrim(char(bytes));
end

function pdu = emitCall(session, lastPdu, cfg, closedBy)
first = valueOr(session.first_sample, 0);
last = valueOr(session.last_sample, first);
duration = max(0, (double(last) - double(first)) / cfg.targetSampleRateHz);
extra = struct('call_type', session.call_type, 'ran', session.ran, ...
    'start_sample', session.first_sample, 'end_sample', session.last_sample, ...
    'duration_s', round(duration, 3), 'message_count', session.message_count, ...
    'alias', session.alias, 'closed_by', closedBy, ...
    'last_payload_hex', radio.getNestedField(lastPdu, 'extra.payload_hex', ''));
pdu = struct('protocol', 'NXDN', 'type', 'NXDN_CALL', 'src', session.src, ...
    'dst', session.dst, 'ts', 0, 'flco', upper(session.call_type), 'fid', '', ...
    'extra', extra, 'raw_bits', false(0, 1));
end

function value = valueOr(value, fallback)
if isempty(value), value = fallback; end
end
