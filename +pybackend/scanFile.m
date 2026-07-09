function pdus = scanFile(path, varargin)
%SCANFILE Run the Python scanner and read its JSON output into MATLAB.
p = inputParser;
p.addParameter('FreqList', []);
p.addParameter('BlindSearch', false);
p.addParameter('ProtocolNames', {});
p.addParameter('SampleRate', []);
p.addParameter('IqDType', 'int16');
p.addParameter('PythonRoot', '');
p.addParameter('PythonExecutable', '');
p.addParameter('Deduplicate', true);
p.parse(varargin{:});

root = char(p.Results.PythonRoot);
if isempty(root)
    root = pybackend.defaultPythonRoot();
end
pyexe = char(p.Results.PythonExecutable);
if isempty(pyexe)
    pyexe = pybackend.pythonExecutable();
end

thisDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(thisDir);
helper = fullfile(projectDir, 'tools', 'python_scan_json.py');
jsonPath = [tempname '.json'];
cleanupJson = onCleanup(@() deleteIfExists(jsonPath));

args = {pyexe, helper, '--project-root', root, '--target', char(path), ...
    '--json', jsonPath, '--iq-dtype', char(p.Results.IqDType)};
if ~p.Results.Deduplicate
    args = [args, {'--no-dedup'}]; %#ok<AGROW>
end

if ~isempty(p.Results.SampleRate)
    args = [args, {'--sample-rate', num2str(double(p.Results.SampleRate), '%.17g')}]; %#ok<AGROW>
end
if p.Results.BlindSearch
    args = [args, {'--blind-search'}]; %#ok<AGROW>
end
freqList = p.Results.FreqList;
for k = 1:numel(freqList)
    args = [args, {'--fo', num2str(double(freqList(k)), '%.17g')}]; %#ok<AGROW>
end
protocolNames = normalizeProtocolCell(p.Results.ProtocolNames);
for k = 1:numel(protocolNames)
    args = [args, {'--protocol', protocolNames{k}}]; %#ok<AGROW>
end

cmdParts = cellfun(@pybackend.shellQuote, args, 'UniformOutput', false);
cmd = strjoin(cmdParts, ' ');
[status, output] = system(cmd);
if status ~= 0
    error('pybackend:scanFile:PythonFailed', ...
        'Python scanner failed with status %d:\n%s', status, output);
end
if exist(jsonPath, 'file') ~= 2
    error('pybackend:scanFile:MissingJson', ...
        'Python scanner did not produce JSON output. Output was:\n%s', output);
end

raw = strtrim(fileread(jsonPath));
if isempty(raw)
    pdus = struct([]);
else
    decoded = jsondecode(raw);
    pdus = radio.normalizePdus(decoded);
end
end

function names = normalizeProtocolCell(value)
if isempty(value)
    names = {};
elseif ischar(value) || (isstring(value) && isscalar(value))
    names = cellstr(value);
elseif isstring(value)
    names = cellstr(value(:));
else
    names = value;
end
end

function deleteIfExists(path)
if exist(path, 'file') == 2
    delete(path);
end
end
