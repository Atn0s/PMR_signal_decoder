function flc = parseFullLinkControl(bits)
%PARSEFULLLINKCONTROL Parse 96-bit or 77-bit DMR Full Link Control bits.
if numel(bits) < 72
    flc = [];
    return;
end
flco = dmr.bitsToInt(bits(3:8));
fid = dmr.bitsToInt(bits(9:16));
if flco == 0
    dst = dmr.bitsToInt(bits(25:48));
    src = dmr.bitsToInt(bits(49:72));
elseif flco == 3
    dst = dmr.bitsToInt(bits(25:48));
    src = dmr.bitsToInt(bits(49:72));
else
    dst = 0;
    src = 0;
end
flc = struct('flco', flco, 'flco_name', dmr.flcoName(flco), ...
    'fid', fid, 'fid_name', dmr.fidName(fid), 'src', src, 'dst', dst);
end

