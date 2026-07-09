function writeJson(pdus, path, varargin)
%WRITEJSON Write decoded PDUs as JSON.
p = inputParser;
p.addParameter('IncludeRawBits', false);
p.parse(varargin{:});

pdus = radio.normalizePdus(pdus);
if ~p.Results.IncludeRawBits
    pdus = stripRawBits(pdus);
end
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

function pdus = stripRawBits(pdus)
if isfield(pdus, 'raw_bits')
    pdus = rmfield(pdus, 'raw_bits');
end
end
