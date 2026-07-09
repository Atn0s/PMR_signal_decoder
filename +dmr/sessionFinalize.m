function [session, callPdu] = sessionFinalize(session, sps)
%SESSIONFINALIZE Emit an end-of-scan DMR call summary if a call is active.
if nargin < 2 || isempty(sps)
    sps = dmr.config().samplesPerSymbol;
end
if ~session.active
    callPdu = [];
    return;
end
dummy = struct('extra', struct());
[session, callPdu] = finalizeViaTerminator(session, dummy, sps);
end

function [session, callPdu] = finalizeViaTerminator(session, lastPdu, sps)
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
extra.closed_by = 'end_of_scan';
extra.last_sync_type = radio.getNestedField(lastPdu, 'extra.sync_type', '');
callPdu = struct( ...
    'protocol', 'DMR', ...
    'type', 'DMR_CALL', ...
    'src', session.src, ...
    'dst', session.dst, ...
    'ts', 0, ...
    'flco', session.flco, ...
    'fid', session.fid, ...
    'extra', extra, ...
    'raw_bits', []);
session = dmr.sessionInit();
end

function value = valueOr(value, defaultValue)
if isempty(value)
    value = defaultValue;
end
end
