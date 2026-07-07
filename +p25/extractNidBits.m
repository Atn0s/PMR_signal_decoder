function out = extractNidBits(fsNidBits)
%EXTRACTNIDBITS Return logical 64-bit NID, skipping in-header status dibit.
c = p25.constants();
required = c.fsBits + c.nidAirSymbols * 2;
if numel(fsNidBits) < required
    error('p25:extractNidBits:TooShort', 'P25 FS+NID bits are too short.');
end
start = c.fsBits + 1;
status = c.fsBits + c.nidStatusSymbolOffset * 2 + 1;
last = c.fsBits + c.nidAirSymbols * 2;
out = [fsNidBits(start:status-1), fsNidBits(status+2:last)];
if numel(out) ~= c.nidBits
    error('p25:extractNidBits:BadLength', 'P25 NID extraction did not produce 64 bits.');
end
out = out(:).';
end

