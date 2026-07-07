function text = formatCch(records)
%FORMATCCH Format dPMR CCH records when present.
text = '';
if isempty(records)
    return;
end
if iscell(records)
    records = [records{:}];
end
if ~isstruct(records)
    return;
end

parts = {};
for k = 1:numel(records)
    r = records(k);
    parts{end + 1} = sprintf('FN=%s IDH=0x%03X M=%s V=%s F=%s E=%s RES=%s SLD=0x%05X', ...
        txt(val(r, 'frame_number', 0)), double(val(r, 'id_half', 0)), ...
        txt(val(r, 'communication_mode', 0)), txt(val(r, 'version', 0)), ...
        txt(val(r, 'comms_format', 0)), txt(val(r, 'emergency_priority', 0)), ...
        txt(val(r, 'reserved', 0)), double(val(r, 'slow_data', 0))); %#ok<AGROW>
end
if ~isempty(parts)
    text = [' CCH=[' strjoin(parts, '; ') ']'];
end
end

function out = val(s, name, fallback)
if isfield(s, name)
    out = s.(name);
else
    out = fallback;
end
end

function text = txt(value)
if isnumeric(value)
    text = num2str(value);
elseif isstring(value)
    text = char(value);
elseif ischar(value)
    text = value;
else
    text = char(string(value));
end
end
