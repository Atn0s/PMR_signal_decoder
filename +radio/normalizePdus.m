function pdus = normalizePdus(pdus)
%NORMALIZEPDUS Normalize decoded JSON structs to MATLAB-friendly field names.
if isempty(pdus)
    pdus = struct([]);
    return;
end
if iscell(pdus)
    pdus = [pdus{:}];
end
for k = 1:numel(pdus)
    if ~isfield(pdus(k), 'protocol') || isempty(pdus(k).protocol)
        pdus(k).protocol = 'DMR';
    end
    defaults = {'type', ''; 'src', 0; 'dst', 0; 'ts', []; 'flco', ''; 'fid', ''};
    for j = 1:size(defaults, 1)
        field = defaults{j, 1};
        if ~isfield(pdus(k), field)
            pdus(k).(field) = defaults{j, 2};
        end
    end
    if ~isfield(pdus(k), 'extra') || isempty(pdus(k).extra)
        pdus(k).extra = struct();
    end
    if isfield(pdus(k), 'x_fo_hz') && ~isfield(pdus(k), 'fo_hz')
        pdus(k).fo_hz = pdus(k).x_fo_hz;
    end
end
end

