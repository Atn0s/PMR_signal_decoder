function name = callTypeName(value)
%CALLTYPENAME Decode the three-bit NXDN call type.
names = {'broadcast', 'conference_group', 'unspecified', 'reserved', ...
    'individual', 'reserved', 'interconnect', 'speed_dial'};
if value >= 0 && value < numel(names)
    name = names{value + 1};
else
    name = 'unknown';
end
end
