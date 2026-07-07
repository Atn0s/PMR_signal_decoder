function writeJson(pdus, path)
%WRITEJSON Write decoded PDUs as JSON.
pdus = radio.normalizePdus(pdus);
folder = fileparts(path);
if ~isempty(folder) && exist(folder, 'dir') ~= 7
    mkdir(folder);
end
fid = fopen(path, 'w');
if fid < 0
    error('radio:writeJson:OpenFailed', 'Unable to write JSON: %s', path);
end
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(pdus, 'PrettyPrint', true));
end

