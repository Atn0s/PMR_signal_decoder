function pdus = addMeta(pdus, name, value)
%ADDMETA Add MATLAB-friendly metadata to every PDU struct.
if isempty(pdus)
    return;
end
if strcmp(name, '_fo_hz')
    name = 'fo_hz';
end
for k = 1:numel(pdus)
    pdus(k).(name) = value;
end
end

