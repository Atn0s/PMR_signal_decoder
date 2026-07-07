function [session, call] = sessionFeed(session, frame, lc, fsStart, sps)
%SESSIONFEED Feed one frame into the P25 call assembler.
call = [];
symbolRate = 4800.0;
if frame.is_terminator
    if ~session.active
        return;
    end
    first = session.first_fs;
    if isempty(first)
        first = fsStart;
    end
    duration = (fsStart - first) / (sps * symbolRate);
    flco = '';
    if session.is_group
        flco = 'GROUP';
    end
    call = struct( ...
        'protocol', 'P25', ...
        'type', 'P25_CALL', ...
        'src', session.src, ...
        'dst', session.dst, ...
        'ts', 0, ...
        'flco', flco, ...
        'fid', '', ...
        'extra', struct('nac', session.nac, 'duration_s', round(duration, 3), 'ldu_count', session.ldu_count), ...
        'raw_bits', []);
    session = p25.sessionInit();
    return;
end

if ~session.active && any(strcmp(frame.duid_name, {'HDU', 'LDU1', 'LDU2'}))
    session.active = true;
    session.nac = frame.nac;
    session.first_fs = fsStart;
end

if session.active
    if frame.is_voice
        session.ldu_count = session.ldu_count + 1;
    end
    if ~isempty(lc)
        session.src = lc.src;
        session.dst = lc.dst;
        session.is_group = lc.is_group;
    end
end
end

