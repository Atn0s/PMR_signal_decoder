function [session, src, dst, part] = sessionFeed(session, cch0, cch1)
%SESSIONFEED Feed CCH pair into dPMR ID assembler.
part = 'unknown';
records = {};
if ~isempty(cch0) && cch0.crc_ok, records{end + 1} = cch0; end %#ok<AGROW>
if ~isempty(cch1) && cch1.crc_ok, records{end + 1} = cch1; end %#ok<AGROW>
for k = 1:numel(records)
    rec = records{k};
    if ~isKey(session.records, rec.frame_number)
        session.records(rec.frame_number) = rec;
    else
        current = session.records(rec.frame_number);
        if rec.crc_ok && ~current.crc_ok
            session.records(rec.frame_number) = rec;
        end
    end
end
dstCandidate = assemblePair(session.records, 0, 1);
srcCandidate = assemblePair(session.records, 2, 3);
if ~isempty(dstCandidate)
    session.dst = dstCandidate;
    part = 'dst';
end
if ~isempty(srcCandidate)
    session.src = srcCandidate;
    part = 'src';
end
src = session.src;
dst = session.dst;
end

function text = assemblePair(records, first, second)
text = '';
if ~isKey(records, first) || ~isKey(records, second)
    return;
end
a = records(first);
b = records(second);
value = bitand(bitshift(uint32(a.id_half), 12) + uint32(b.id_half), uint32(hex2dec('FFFFFF')));
text = dpmr.airInterfaceIdToStr(value);
end

