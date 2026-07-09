function [session, callPdu] = callSessionFinalize(session, sps)
%CALLSESSIONFINALIZE Emit dPMR call summary at end of scan.
if nargin < 2 || isempty(sps)
    sps = dpmr.config().samplesPerSymbol;
end
if ~session.active
    callPdu = [];
    return;
end
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
extra.closed_by = 'end_of_scan';
if session.voiceCount > 0
    flco = 'VOICE';
else
    flco = 'HEADER';
end
callPdu = struct('protocol', 'dPMR', 'type', 'dPMR_CALL', ...
    'src', session.src, 'dst', session.dst, 'ts', 0, 'flco', flco, ...
    'fid', '', 'extra', extra, 'raw_bits', []);
session = dpmr.callSessionInit();
end

function value = valueOr(value, defaultValue)
if isempty(value)
    value = defaultValue;
end
end
