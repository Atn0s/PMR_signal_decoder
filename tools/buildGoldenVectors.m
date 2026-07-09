function buildGoldenVectors(varargin)
%BUILDGOLDENVECTORS Generate Python baseline JSON files.
p = inputParser;
p.addParameter('PythonRoot', pybackend.defaultPythonRoot());
p.addParameter('PythonExecutable', pybackend.pythonExecutable());
p.addParameter('OutDir', fullfile(projectRoot(), 'golden', 'current'));
p.addParameter('RawOutDir', '');
p.addParameter('Deduplicate', true);
p.parse(varargin{:});

script = fullfile(projectRoot(), 'tools', 'build_golden_vectors.py');
args = {p.Results.PythonExecutable, script, '--project-root', p.Results.PythonRoot, ...
    '--out-dir', p.Results.OutDir};
if ~p.Results.Deduplicate
    args = [args, {'--no-dedup'}]; %#ok<AGROW>
end
if ~isempty(p.Results.RawOutDir)
    args = [args, {'--raw-out-dir', p.Results.RawOutDir}]; %#ok<AGROW>
end
cmd = strjoin(cellfun(@pybackend.shellQuote, args, 'UniformOutput', false), ' ');
[status, output] = system(cmd);
if status ~= 0
    error('tools:buildGoldenVectors:Failed', ...
        'Golden vector generation failed with status %d:\n%s', status, output);
end
disp(output);
end

function root = projectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
